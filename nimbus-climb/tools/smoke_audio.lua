-- smoke_audio.lua: the original audio (nimbus-climb/audio/, Config.Audio <- shared/AudioIds.lua <- tools/upload_assets.py
-- --audio; client/SoundFx, client/Controllers/RingAmbience). Loaded by tools/smoke.py in the server and the client world:
--   audio_ring_pocket   (server, booted) the real Champion Ring pocket (ArenaBuilder.BuildPocket(i, "Ring")) has the
--                       child model "Crowd" RingAmbience hangs the crowd + drums on; the fighter's pad is inside the
--                       crowd's hearing range (CrowdCheer Max), the next pocket's crowd far outside it
--   client_audio_keys   Config.Audio.Keys = exactly the 59 keys of audio/audio.json (12 originals + 47 of wave 2) + the
--                       pending FountainLoop (one each); Config.Audio holds exactly the AudioIds that exist; a Config
--                       copy beside a FAKE AudioIds maps every key to its number, leaves out a missing / junk one; one
--                       place for slot volumes (every key; music under every SFX but the UnderMusic hits / ticks, which
--                       sit at or under it; the ring's crowd + drums under the music) + the positional ranges;
--                       SoundFx.NAMES has the new Inhale / Shatter / CrowdCheer / DrumLoop and every Sfx / Ambient name
--   client_audio_silent (no ids, the shipped state) every Play / PlayVariant / Music / SetLayer / Positional, the charge
--                       hooks, a battle Start / Hit / KO / End, a dungeon run, a ring pocket, a "bad" toast, the fountain
--                       and an NPC dialog make no Sound, no error, no warning
--   client_audio_music  (ids given for the test) Music loops; Battle on my fight's Start, back to Lobby at its End (+ the
--                       win's Reward), a won ring round keeps Battle until the next round, a spectator hears no battle
--                       music; a dungeon run plays Dungeon (rooms too), its boss room Battle, back to Dungeon after it,
--                       Lobby when the run ends; the chest and a room's loot play Reward; the Music / Sfx settings apply
--                       at once to the music and the positional loops (also while a track is still fading in); a
--                       dungeon room's won End plays no Reward of its own (its Loot does: one Reward per room);
--                       MainMenuController starts the track SoundFx.Wanted() names (not a hard "Lobby")
--   client_audio_charge BattleController's special charge plays SoundFx "Inhale" (PlaybackSpeed 0.75 rising to 1.35, faded
--                       in / out) and a broken charge "Shatter" (the Sounds carry the Inhale / Shatter ids)
--   client_audio_ring   RingAmbience on a ring pocket: CrowdCheer + DrumLoop looped, InverseTapered, Config.Audio
--                       Positional Min / Max, at the crowd stand, slot volume x setting; a Drummer added later takes the
--                       drums, so does a crowd model marked Drummer = true (the art-wave crowd); a tagged plaza crowd
--                       (NC_RingCrowd) gets its own; a destroyed pocket takes its sounds; LATE PARTS: an empty Crowd whose
--                       parts land after it (a small one first) gets both loops at the whole stand's middle, one drum loop,
--                       a VFX part elsewhere in the pocket triggers no re-scan, a tagged model's late parts get its loop
-- Deterministic: mock clock only, fixed ids (fake numbers given for the test, never uploaded). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()

-- every sound of audio/audio.json, wired into Config.Audio.Keys (the 12 originals + audio wave 2: the owner's
-- 2026-10-29 SFX picks and 2026-10-30 NPC voices, audio/README.md; wiring: .superpowers/audio-pitch/wave2/wiring-plan.md)
local AUDIO_KEYS = { "Click", "Confirm", "CrowdCheer", "DrumLoop", "Error", "Inhale", "MusicBattle", "MusicDungeon", "MusicLobby", "Reward", "Shatter", "Whoosh",
	"Crit", "Dash", "DialogBlip", "DialogNext", "DialogOpen", "HitCelestial", "HitEarth", "HitFlame", "HitFrost", "HitNature",
	"HitShadow", "HitStorm", "HitWater", "HouseTier", "KO", "KO2", "KO3", "KO4", "Parry", "PortalArrive", "PortalEnter", "RevealCommon",
	"RevealLegendary", "RevealRare", "SpinLand", "SpinStart", "SpinTick", "StationBuild", "TutorialStep",
	"NpcCaptainPenguinGreet", "NpcCaptainPenguinHmm", "NpcCaptainPenguinPleased", "NpcCoachCorgiGreet", "NpcCoachCorgiHmm", "NpcCoachCorgiPleased",
	"NpcGrannyOwlGreet", "NpcGrannyOwlHmm", "NpcGrannyOwlPleased", "NpcMayorPandaGreet", "NpcMayorPandaHmm", "NpcMayorPandaPleased",
	"NpcProfessorAxolotlGreet", "NpcProfessorAxolotlHmm", "NpcProfessorAxolotlPleased", "NpcSparkyFoxGreet", "NpcSparkyFoxHmm", "NpcSparkyFoxPleased" }
table.sort(AUDIO_KEYS)
-- uploaded to audio/audio.json, NOT wired yet (move a key up into AUDIO_KEYS when it is wired): none today
local WAVE2_KEYS = {}
-- wired in Config.Audio.Keys before any take exists (no file in audio.json, no AudioIds id: silent until one is approved)
local PENDING_KEYS = { "FountainLoop" }
local MANIFEST_KEYS = {}
for _, list in ipairs({ AUDIO_KEYS, WAVE2_KEYS }) do
	for _, key in ipairs(list) do
		MANIFEST_KEYS[#MANIFEST_KEYS + 1] = key
	end
end
table.sort(MANIFEST_KEYS)
local CONFIG_KEYS = {}
for _, list in ipairs({ AUDIO_KEYS, PENDING_KEYS }) do
	for _, key in ipairs(list) do
		CONFIG_KEYS[#CONFIG_KEYS + 1] = key
	end
end
table.sort(CONFIG_KEYS)

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
	T.eq(table.concat(mkeys, " "), table.concat(MANIFEST_KEYS, " "), "audio keys: audio/audio.json lists the 59 sounds (12 originals + the 47 of wave 2)")
	T.check(table.concat(ckeys, " ") == table.concat(CONFIG_KEYS, " ") and #dup == 0, "audio keys: Config.Audio.Keys maps exactly the 59 AudioIds keys (+ FountainLoop, no take yet), each once",
		table.concat(ckeys, " ") .. " dup: " .. table.concat(dup, " "))
	T.eq(A.Keys.Sfx.Inhale, "Inhale", "audio keys: Sfx.Inhale = AudioIds.Inhale")
	T.eq(A.Keys.Sfx.Shatter, "Shatter", "audio keys: Sfx.Shatter = AudioIds.Shatter")
	T.eq(A.Keys.Ambient.CrowdCheer, "CrowdCheer", "audio keys: Ambient.CrowdCheer = AudioIds.CrowdCheer")
	T.eq(A.Keys.Ambient.DrumLoop, "DrumLoop", "audio keys: Ambient.DrumLoop = AudioIds.DrumLoop")
	-- the shipped stub: no ids -> every group empty
	local ids = moduleAt(ROOTS.shared .. "/AudioIds")
	-- only the wired keys count: a wave-2 id uploaded before its wiring is in AudioIds but not (yet) in Config.Audio
	local wired = {}
	for _, key in ipairs(AUDIO_KEYS) do
		wired[key] = true
	end
	local nIds = 0
	for key in pairs(ids or {}) do
		if wired[key] then
			nIds = nIds + 1
		end
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
		-- the real AudioIds has every id since the upload: wipe the Music ids for this one call
		local realMusic = Config.Audio.Music
		Config.Audio.Music = {}
		local id = SF.Id("Music", "Lobby")
		Config.Audio.Music = realMusic
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
	for _, key in ipairs(CONFIG_KEYS) do
		if type(V[key]) ~= "number" or V[key] <= 0 or V[key] > 1 then
			missing[#missing + 1] = key
		end
	end
	for _, key in pairs(A.Keys.Music) do
		musicMax = math.max(musicMax, V[key] or 0)
	end
	-- (audio wave 2) the frequent quiet keys (UnderMusic: the element hits, SpinTick, DialogBlip, DialogNext) may sit at or
	-- under the music; every other effect sits above it
	local under = A.UnderMusic or {}
	local underLoud = {}
	for _, key in pairs(A.Keys.Sfx) do
		if under[key] then
			if (V[key] or 1) > musicMax then
				underLoud[#underLoud + 1] = key
			end
		else
			sfxMin = math.min(sfxMin, V[key] or 0)
		end
	end
	local underList = {}
	for key in pairs(under) do
		underList[#underList + 1] = key
	end
	table.sort(underList)
	T.eq(table.concat(underList, " "), "DialogBlip DialogNext HitCelestial HitEarth HitFlame HitFrost HitNature HitShadow HitStorm HitWater SpinTick",
		"audio volumes: UnderMusic = the frequent quiet keys only (the 8 element hits, SpinTick, DialogBlip, DialogNext)")
	local musicMin = 1
	for _, key in pairs(A.Keys.Music) do
		musicMin = math.min(musicMin, V[key] or 1)
	end
	T.check(#missing == 0, "audio volumes: Config.Audio.Volume gives every key a slot volume in (0, 1]", table.concat(missing, " "))
	T.check(musicMax < sfxMin, "audio volumes: the music sits under every sound effect (but the UnderMusic ones)", fmt("music max %.2f, sfx min %.2f", musicMax, sfxMin))
	T.check(#underLoud == 0, "audio volumes: ... and every UnderMusic key really sits at or under the music", table.concat(underLoud, " "))
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
	local fountain = SF.Positional("Fountain", part)
	local ko = SF.PlayVariant("KO")
	T.check(allNil and m1 == nil and m2 == nil and m3 == nil and pos == nil and fountain == nil and ko == nil,
		"audio silent: Play / PlayVariant / Music / SetLayer / Positional (the fountain too) return nil while no id exists")
	-- the battle's charge sounds, a battle Start / End, a dungeon run, a ring pocket
	BC.FxHooks()
	local hk = AF.Hooks
	local inh = hk.Inhale and hk.Inhale(0.6, "silent1", true)
	if hk.Shatter then
		hk.Shatter(true)
	end
	BC.HandleState("Start", startPayload("audio_silent", "Duel", 1), "audio_silent")
	KC.advance(0.2)
	BC.HandleState("Events", { { type = "Hit", from = 1, to = 2, dmg = 10, crit = true }, { type = "KO", unit = 2 }, { type = "Parry", unit = 1 } }, "audio_silent")
	KC.advance(0.2)
	BC.HandleState("End", { BattleId = "audio_silent", Mode = "Duel", Outcome = "Win", Won = true, Rewards = { Cash = 10 } }, "audio_silent")
	KC.advance(0.2)
	-- (wave 2) a refused action's toast, the fountain's falls: still silent
	KC.toClient("Notify", "Audio silent: refused", "bad", 2)
	local falls = Instance.new("Part")
	falls.Parent = Workspace
	CollectionService:AddTag(falls, "OasisFalls")
	KC.advance(0.2)
	falls:Destroy()
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
	-- <= : a track that was playing with the real ids may stop once they are wiped; no NEW Sound may appear
	T.check(inh ~= true and after <= before and anchors == 0, "audio silent: the charge hooks, a battle, a dungeon run (chest) and a ring pocket make no Sound and leave no anchor",
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
		local roomEndReward = false
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) and s.IsPlaying then
				roomEndReward = true
			end
		end
		T.check(not roomEndReward, "audio reward: a won dungeon room's End plays no Reward of its own (the room's Loot does: one per room)")
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
		-- a settings change while a track is still fading in wins over the fade's target
		SF.Music("Dungeon")
		KC.advance(0.1)
		CS.Set("Music", 0)
		KC.advance(2)
		local _, fading = music(SF)
		local fadeMuted = fading ~= nil and fading.Name == "Music_Dungeon" and fading.Volume == 0
		CS.Set("Music", 10)
		KC.advance(2)
		T.check(fadeMuted and math.abs(fading.Volume - Config.Audio.Volume.MusicDungeon) < 1e-6,
			"audio settings: Music 0 during a track's fade-in keeps it muted (the fade does not end on the old volume); back to 10 -> its slot volume",
			fading and fmt("muted %s, then %.3f", tostring(fadeMuted), fading.Volume) or "no music")
		SF.Music("Lobby")
		CS.Set("Music", m0)
		CS.Set("Sfx", s0)
		part:Destroy()
		-- MainMenuController starts the music the layers ask for (a battle already on is not overridden by Lobby)
		local mm = readFile("src/client/Controllers/MainMenuController.lua") or ""
		T.check(string.find(mm, "SoundFx.Wanted()", 1, true) ~= nil and string.find(mm, 'SoundFx.Music, "Lobby")', 1, true) == nil,
			"audio music: MainMenuController starts SoundFx.Music(SoundFx.Wanted()), not a hard Lobby")
		SF.SetLayer("Battle", true)
		local wanted = SF.Wanted()
		SF.SetLayer("Battle", false)
		T.eq(wanted, "Battle", "audio music: SoundFx.Wanted() names the Battle layer while it is on")
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
	-- (the requirement is pinned by behaviour below: the hooks' Sounds carry Config.Audio.Sfx.Inhale / Shatter ids)
	local restore = giveIds(Config)
	BC.FxHooks()
	local hk = AF.Hooks
	local folder = function()
		return SoundService:FindFirstChild("NimbusSounds")
	end
	-- (wave 6 fix round) SoundFx pools 3 Sounds per name, and an earlier battle scenario's inhale / shatter (faded to
	-- Volume 0, its own id) may still be playing in the folder: those are stopped first, and the inhale checked is the
	-- one this token's hook started (BattleController's inhale record), not the first match
	for _, s in ipairs(folder() and folder():GetChildren() or {}) do
		if s:IsA("Sound") and string.find(s.Name, "Sfx_", 1, true) == 1 then
			s:Stop()
		end
	end
	local played = hk.Inhale and hk.Inhale(0.8, "audio_charge", true)
	local recs = type(BC._Inhales) == "function" and BC._Inhales() or {}
	local inhale = recs.audio_charge and recs.audio_charge.sound or nil
	if inhale and not (string.find(inhale.Name, "Sfx_Inhale", 1, true) and inhale.IsPlaying and inhale:IsDescendantOf(SoundService)) then
		inhale = nil
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
	T.check(shatter ~= nil and shatter.SoundId == "rbxassetid://" .. tostring(Config.Audio.Sfx.Shatter), "audio charge: a broken charge plays SoundFx Shatter",
		shatter and shatter.SoundId or fmt("none (hook %s)", tostring(hk.Shatter ~= nil)))
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
		-- the art-wave crowd: a spectator model marked Drummer = true (no "Drummer" name) takes the drums of its pocket
		local pocket2, crowd2 = fakePocket(Vector3.new(-6000, 900, 4000))
		KC.advance(0.1)
		local drizzle = Instance.new("Model")
		drizzle.Name = "Spectator_drizzle"
		drizzle:SetAttribute("Drummer", true)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2.8, 2.5, 2.2)
		body.CFrame = CFrame.new(-6000 + 6, 905, 4000 + 44)
		body.Parent = drizzle
		drizzle.Parent = crowd2
		KC.advance(0.1)
		local drums2 = {}
		for _, s in ipairs(sounds(pocket2)) do
			if s.Name == "Loop_DrumLoop" then
				drums2[#drums2 + 1] = s
			end
		end
		T.check(#drums2 == 1 and drums2[1]:IsDescendantOf(drizzle), "audio ring: a crowd model marked Drummer = true (the art-wave drummer) takes the DrumLoop",
			fmt("%d drum loops", #drums2))
		pocket2:Destroy()
		KC.advance(0.1)
		-- a late join: the pocket and an EMPTY Crowd model replicate first, its parts after (one, then the rest)
		local folder = Workspace:FindFirstChild("BattlePockets")
		local late = Instance.new("Model")
		late.Name = "RingPocket_" .. (190 + pocketSeq)
		late.Parent = folder
		KC.advance(0.1)
		local lateCrowd = Instance.new("Model")
		lateCrowd.Name = "Crowd"
		lateCrowd.Parent = late
		KC.advance(0.1)
		local empty = #sounds(late)
		local base = Vector3.new(-8000, 900, 4000)
		local steps = {}
		for i, spec in ipairs({ { 4, 1, 2, 0.5, 1.9, -14 }, { 34, 1.5, 3.8, 0.75, 1.9, 0 }, { 28, 3.5, 3.8, 1.75, 5.7, 0 } }) do
			local step = Instance.new("Part")
			step.Name = "StandStep"
			step.Size = Vector3.new(spec[1], spec[2], spec[3])
			step.CFrame = CFrame.new(base + Vector3.new(spec[6], spec[4], 37.6 + spec[5]))
			step.Parent = lateCrowd
			steps[i] = step
			if i == 1 then
				KC.advance(0.1) -- (a small part lands alone first: it must not stay the anchor)
			end
		end
		KC.advance(0.1)
		local lateList = sounds(late)
		local lc, ld = nil, nil
		for _, s in ipairs(lateList) do
			if s.Name == "Loop_CrowdCheer" then
				lc = s
			elseif s.Name == "Loop_DrumLoop" then
				ld = s
			end
		end
		T.check(empty == 0 and #lateList == 2 and lc and ld and lc.IsPlaying and ld.IsPlaying,
			"audio ring: a Crowd whose parts replicate after it still gets its CrowdCheer + DrumLoop once they land (no rejoin needed)",
			fmt("empty %d, then %d sounds", empty, #lateList))
		if lc then
			local lpos = lc.Parent.WorldPosition
			T.check(lc.Parent.Parent == steps[3] and math.abs(lpos.X - base.X) < 1 and lpos.Z > base.Z + 37 and lpos.Z < base.Z + 50,
				"audio ring: ... at the whole stand's middle on its biggest step (not on the first small part that landed)", tostring(lpos))
		end
		local lateDrums = 0
		for _, s in ipairs(lateList) do
			if s.Name == "Loop_DrumLoop" then
				lateDrums = lateDrums + 1
			end
		end
		T.eq(lateDrums, 1, "audio ring: the late crowd's re-scans leave one DrumLoop (no duplicates)")
		-- a battle's VFX part in the pocket (not in the crowd) does not move the loops
		local before = lc
		local vfx = Instance.new("Part")
		vfx.Name = "Spark"
		vfx.Size = Vector3.new(80, 80, 80)
		vfx.CFrame = CFrame.new(base + Vector3.new(0, 10, 0))
		local scans, scan0 = 0, RA.Scan
		RA.Scan = function(...)
			scans = scans + 1
			return scan0(...)
		end
		vfx.Parent = late
		KC.advance(0.1)
		RA.Scan = scan0
		local still = nil
		for _, s in ipairs(sounds(late)) do
			if s.Name == "Loop_CrowdCheer" then
				still = s
			end
		end
		T.check(before ~= nil and still == before and scans == 0, "audio ring: a VFX part elsewhere in the pocket leaves the crowd's loop where it is (no re-scan)",
			fmt("%d scans", scans))
		late:Destroy()
		KC.advance(0.1)
		-- a tagged plaza stand model whose parts land after its tag
		local lateStand = Instance.new("Model")
		lateStand.Name = "PlazaStandsLate"
		CollectionService:AddTag(lateStand, "NC_RingCrowd")
		lateStand.Parent = Workspace
		KC.advance(0.1)
		local standEmpty = #sounds(lateStand)
		local standPart = Instance.new("Part")
		standPart.Size = Vector3.new(20, 4, 6)
		standPart.CFrame = CFrame.new(300, 10, 300)
		standPart.Parent = lateStand
		KC.advance(0.1)
		local standList = sounds(lateStand)
		T.check(standEmpty == 0 and #standList == 1 and standList[1].Name == "Loop_CrowdCheer",
			"audio ring: a tagged NC_RingCrowd model whose parts land after it gets its CrowdCheer then", fmt("%d -> %d", standEmpty, #standList))
		lateStand:Destroy()
		KC.advance(0.1)
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

----------------------------------------------------------------------------------------------------
-- audio wave 2: the mechanics (pitch per key, MinGap, the Hit cap, the KO rotation, Scale) and the call sites
----------------------------------------------------------------------------------------------------
-- records every SoundFx.Play (PlayVariant goes through it too): { name, opts, sound, vol, speed }
local function spy(SF)
	local log = {}
	local play0 = SF.Play
	SF.Play = function(name, opts)
		local s = play0(name, opts)
		log[#log + 1] = { name = name, opts = opts, sound = s, vol = s and s.Volume or nil, speed = s and s.PlaybackSpeed or nil }
		return s
	end
	return log, function()
		SF.Play = play0
	end
end

-- the plays of `name` (a Lua pattern when `pattern`) that made a sound, since index `from`
local function playsOf(log, name, from, pattern)
	local out = {}
	for i = (from or 0) + 1, #log do
		local e = log[i]
		if e.sound and ((pattern and string.find(e.name, name)) or e.name == name) then
			out[#out + 1] = e
		end
	end
	return out
end

local function freshGaps(SF)
	local St = SF._St
	St.Last = {}
	St.Recent = {}
	St.LastVariant = {}
end

local function pressKey(keyName)
	Mock.FireSignal(game:GetService("UserInputService"), "InputBegan", Mock.NewInput(keyName, "Keyboard", "Begin"), false)
end

-- "sparky_fox" -> "SparkyFox" (NpcController's voice key name)
local function camelId(id)
	local out = string.gsub(id, "(%w)(%w*)", function(a, b)
		return string.upper(a) .. b
	end)
	return (string.gsub(out, "[^%w]", ""))
end

S.client_audio_mechanics = guarded("client_audio_mechanics", function()
	local M = mods()
	local Config, SF, CS = M.Config, M.SF, M.CS
	if not T.check(Config and SF and CS and type(SF.PlayVariant) == "function", "audio mechanics: SoundFx.PlayVariant exists") then
		return
	end
	local A = Config.Audio
	local restore = giveIds(Config)
	local s0 = CS.Get("Sfx")
	local okRun, err = pcall(function()
		CS.Set("Sfx", 10)
		-- every one-shot key plays at its slot volume, its own id, a pitch inside its range
		local bad, n = {}, 0
		for name, key in pairs(A.Keys.Sfx) do
			freshGaps(SF)
			local s = SF.Play(name)
			local r = A.Pitch[key] or { 0.95, 1.05 }
			n = n + 1
			if not s or math.abs(s.Volume - A.Volume[key]) > 1e-6 or s.PlaybackSpeed < r[1] - 1e-9 or s.PlaybackSpeed > r[2] + 1e-9
				or s.SoundId ~= "rbxassetid://" .. string.format("%d", A.Sfx[name]) then
				bad[#bad + 1] = name .. (s and fmt("(vol %.2f speed %.3f)", s.Volume, s.PlaybackSpeed) or "(nil)")
			end
		end
		T.check(#bad == 0 and n >= 54, "audio mechanics: every one-shot key plays its own id at its slot volume, pitch inside Config.Audio.Pitch (" .. n .. " keys)", table.concat(bad, " "))
		-- the pitch ranges: hits wide, celestial narrow, the tuned reveals fixed
		local function speeds(name, count)
			local lo, hi = 9, 0
			for _ = 1, count do
				freshGaps(SF)
				local s = SF.Play(name)
				if s then
					lo, hi = math.min(lo, s.PlaybackSpeed), math.max(hi, s.PlaybackSpeed)
				end
			end
			return lo, hi
		end
		local eLo, eHi = speeds("HitEarth", 40)
		local cLo, cHi = speeds("HitCelestial", 40)
		local rLo, rHi = speeds("RevealLegendary", 10)
		local vLo, vHi = speeds("NpcGrannyOwlGreet", 30)
		T.check(eLo >= 0.92 - 1e-9 and eHi <= 1.06 + 1e-9 and eHi - eLo > 0.06, "audio mechanics: HitEarth's pitch spreads over 0.92-1.06", fmt("%.3f-%.3f", eLo, eHi))
		T.check(cLo >= 0.96 - 1e-9 and cHi <= 1.04 + 1e-9 and cHi - cLo > 0.03, "audio mechanics: HitCelestial stays narrow (0.96-1.04: shimmer must not detune)", fmt("%.3f-%.3f", cLo, cHi))
		T.check(rLo == 1 and rHi == 1, "audio mechanics: the reveal motif never pitch-shifts", fmt("%.3f-%.3f", rLo, rHi))
		T.check(vLo >= 0.98 - 1e-9 and vHi <= 1.02 + 1e-9, "audio mechanics: an NPC voice stays within 0.98-1.02", fmt("%.3f-%.3f", vLo, vHi))
		-- MinGap: a second play inside the gap is dropped, after it plays again
		local function gapHolds(name, wait)
			freshGaps(SF)
			local a = SF.Play(name)
			local b = SF.Play(name)
			KC.advance(wait)
			local c = SF.Play(name)
			return a ~= nil and b == nil and c ~= nil
		end
		T.check(gapHolds("DialogBlip", 0.05), "audio mechanics: DialogBlip MinGap 0.045 s (a second blip at once is dropped, one 0.05 s later plays)")
		T.check(gapHolds("SpinTick", 0.034), "audio mechanics: SpinTick MinGap 0.025 s")
		T.check(gapHolds("HitWater", 0.07), "audio mechanics: a hit's MinGap 0.06 s")
		T.check(gapHolds("Crit", 0.16), "audio mechanics: Crit MinGap 0.15 s")
		T.check(gapHolds("Error", 1.05), "audio mechanics: Error MinGap 1 s")
		-- the Hit group cap: at most 8 hits per 0.25 s (whatever their element)
		freshGaps(SF)
		local okHits = 0
		for _, el in ipairs({ "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
			if SF.Play("Hit" .. el) then
				okHits = okHits + 1
			end
		end
		KC.advance(0.1)
		local ninth = SF.Play("HitWater")
		KC.advance(0.2)
		local later = SF.Play("HitWater")
		T.check(okHits == 8 and ninth == nil and later ~= nil, "audio mechanics: the hits cap at 8 per 0.25 s (a 9th in the window is dropped, one after it plays)",
			fmt("%d at once, 9th %s, later %s", okHits, tostring(ninth ~= nil), tostring(later ~= nil)))
		-- the KO rotation: 40 KOs never repeat back to back and use all four files
		local log, unspy = spy(SF)
		freshGaps(SF)
		local seq, used, repeats = {}, {}, 0
		for i = 1, 40 do
			SF._St.Last = {}
			local s = SF.PlayVariant("KO")
			local e = log[#log]
			seq[i] = s and e and e.name or "nil"
			used[seq[i]] = true
			if i > 1 and seq[i] == seq[i - 1] then
				repeats = repeats + 1
			end
		end
		T.check(repeats == 0 and used.KO and used.KO2 and used.KO3 and used.KO4 and not used["nil"], "audio mechanics: 40 KOs rotate through KO / KO2 / KO3 / KO4, never the same file twice in a row",
			table.concat(seq, " "))
		local volOk = true
		for _, e in ipairs(playsOf(log, "^KO", 0, true)) do
			volOk = volOk and math.abs(e.vol - 0.7) < 1e-6 and e.speed >= 0.97 - 1e-9 and e.speed <= 1.03 + 1e-9
		end
		T.check(volOk, "audio mechanics: every KO file plays at 0.7, pitch 0.97-1.03")
		-- the rotation shares KO's MinGap (0.25 s), whichever file it picks
		freshGaps(SF)
		local k1 = SF.PlayVariant("KO")
		local k2 = SF.PlayVariant("KO")
		KC.advance(0.27)
		local k3 = SF.PlayVariant("KO")
		T.check(k1 ~= nil and k2 == nil and k3 ~= nil, "audio mechanics: the KO rotation shares one MinGap (0.25 s)")
		-- a missing id drops out of the rotation; one id left = that one each time
		local sv = { A.Sfx.KO2, A.Sfx.KO3, A.Sfx.KO4 }
		A.Sfx.KO2, A.Sfx.KO3, A.Sfx.KO4 = nil, nil, nil
		local only = true
		for _ = 1, 5 do
			SF._St.Last = {}
			local s = SF.PlayVariant("KO")
			only = only and s ~= nil and log[#log].name == "KO"
		end
		A.Sfx.KO2, A.Sfx.KO3, A.Sfx.KO4 = sv[1], sv[2], sv[3]
		T.check(only, "audio mechanics: with only KO's id the rotation plays KO each time (a missing id drops out)")
		unspy()
		-- opts.Scale and the Sfx setting
		freshGaps(SF)
		local half = SF.Play("Parry", { Scale = 0.5 })
		CS.Set("Sfx", 5)
		freshGaps(SF)
		local set5 = SF.Play("Parry")
		CS.Set("Sfx", 10)
		T.check(half and math.abs(half.Volume - 0.4) < 1e-6 and set5 and math.abs(set5.Volume - 0.4) < 1e-6,
			"audio mechanics: opts.Scale 0.5 and the Sfx setting 5 each halve Parry's 0.8", fmt("%s / %s", half and fmt("%.3f", half.Volume) or "nil", set5 and fmt("%.3f", set5.Volume) or "nil"))
	end)
	T.check(okRun, "client_audio_mechanics ran to the end", tostring(err))
	CS.Set("Sfx", s0)
	freshGaps(SF)
	restore()
end)

-- a real BattleSim duel's Start payload (my team vs Rival 78; side 0 = I only watch: 77 vs 78)
local function duelStart(id, side)
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
	if not Sim or not PC then
		return nil
	end
	local function team(skip)
		local out = {}
		for _, def in ipairs(PC.Pets or {}) do
			if def.Role == "Combat" and def.Rarity ~= "Secret" and not def.EventOnly and type(def.Special) == "table" then
				if skip > 0 then
					skip = skip - 1
				else
					out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = 10, Tier = "Normal", Slot = #out + 1 }
					if #out >= 2 then
						break
					end
				end
			end
		end
		return out
	end
	local me = side == 0 and 77 or LocalPlayer.UserId
	local sim = Sim.new({ Mode = "Duel", Seed = 5, Id = id, Teams = { { Owner = me, Side = 1, Pets = team(0), Auto = true }, { Owner = 78, Side = 2, Pets = team(3), Auto = true } } })
	if not sim then
		return nil
	end
	local p = sim:Describe()
	p.BattleId = id
	p.Zone = { CFrame = CFrame.new(0, 400, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
	p.Names = { [tostring(LocalPlayer.UserId)] = LocalPlayer.Name, ["77"] = "Buddy", ["78"] = "Rival" }
	p.Side = side
	p.Spectator = side == 0
	p.T = sim:Time()
	local mine, theirs = nil, nil
	p.Sim = sim
	for _, info in ipairs(p.Units or {}) do
		if info.side == 1 and not mine then
			mine = info
		elseif info.side == 2 and not theirs then
			theirs = info
		end
	end
	return p, mine, theirs
end

-- the render clock runs on snapshots: the sim's still picture, its T moving on (no Step: no events of its own)
local function feed(p, seconds)
	for _ = 1, math.max(1, math.floor(seconds / 0.1 + 0.5)) do
		p.T = p.T + 0.1
		local snap = p.Sim:Snapshot()
		snap.T = p.T
		snap.BattleId = p.BattleId
		mods().BC.HandleState("Snapshot", snap, p.BattleId)
		KC.advance(0.1)
	end
end

S.client_audio_battle = guarded("client_audio_battle", function()
	local M = mods()
	local Config, SF, BC = M.Config, M.SF, M.BC
	if not T.check(Config and SF and BC and type(BC._Unit) == "function", "audio battle: SoundFx and BattleController load") then
		return
	end
	local restore = giveIds(Config)
	local log, unspy = spy(SF)
	local cam = Workspace.CurrentCamera
	local cam0 = cam and cam.CFrame
	local okRun, err = pcall(function()
		freshGaps(SF)
		local p, mine, theirs = duelStart("audio_w2_duel", 1)
		if not T.check(p ~= nil and mine and theirs and type(mine.element) == "string", "audio battle: a BattleSim duel to fight (my pet, the rival's)") then
			return
		end
		if cam then
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 430, 40), Vector3.new(0, 400, 0)) -- (my fight's camera looks at the ring)
		end
		BC.HandleState("Start", p, p.BattleId)
		feed(p, 0.4)
		local my, foe = BC._Unit(mine.id), BC._Unit(theirs.id)
		T.check(my and my.mine and foe and not foe.mine, "audio battle: my unit is mine, the rival's is not")
		local function fire(list)
			local from = #log
			BC.HandleState("Events", list, p.BattleId)
			feed(p, 0.8)
			return from
		end
		local hitKey = "Hit" .. mine.element
		-- a landed hit: the attacker's element, once, full volume in my own fight
		local f = fire({ { type = "Hit", from = mine.id, to = theirs.id, dmg = 12 } })
		local hits = playsOf(log, "^Hit", f, true)
		T.check(#hits == 1 and hits[1].name == hitKey and math.abs(hits[1].vol - SF.SlotVolume(hitKey)) < 1e-6,
			"audio battle: a landed hit plays the attacker's element hit (" .. hitKey .. ") once at its slot volume", fmt("%d hits %s", #hits, hits[1] and hits[1].name or "-"))
		-- the rival hits me: its own element
		f = fire({ { type = "Hit", from = theirs.id, to = mine.id, dmg = 9 } })
		hits = playsOf(log, "^Hit", f, true)
		T.check(#hits == 1 and hits[1].name == "Hit" .. theirs.element, "audio battle: the rival's hit on my pet plays the rival's element", hits[1] and hits[1].name or "none")
		-- a crit: the hit + Crit's sparkle on top
		f = fire({ { type = "Hit", from = mine.id, to = theirs.id, dmg = 30, crit = true } })
		T.check(#playsOf(log, "^Hit", f, true) == 1 and #playsOf(log, "Crit", f) == 1, "audio battle: a critical hit plays the element hit and Crit together")
		-- burn / zone ticks, a dodged hit, a 0-damage hit: no hit sound
		f = fire({ { type = "Hit", from = mine.id, to = theirs.id, dmg = 4, burn = true }, { type = "Hit", from = mine.id, to = theirs.id, dmg = 4, zone = true } })
		local f2 = fire({ { type = "Hit", from = mine.id, to = theirs.id, dmg = 0, miss = true }, { type = "Hit", from = mine.id, to = theirs.id, dmg = 0 } })
		local burnHits = #playsOf(log, "^Hit", f, true) - #playsOf(log, "^Hit", f2, true)
		T.check(burnHits == 0, "audio battle: burn and zone ticks are silent (they come in bursts)", burnHits .. " hits")
		T.check(#playsOf(log, "^Hit", f2, true) == 0, "audio battle: a dodged / 0-damage hit plays no hit sound")
		-- a parry: the parried hit plays no hit, the Parry event plays Parry once (fixed pitch)
		f = fire({ { type = "Hit", from = theirs.id, to = mine.id, dmg = 0, miss = true, parry = true }, { type = "Parry", unit = mine.id } })
		local par = playsOf(log, "Parry", f)
		T.check(#playsOf(log, "^Hit", f, true) == 0 and #par == 1 and par[1].speed == 1 and math.abs(par[1].vol - SF.SlotVolume("Parry")) < 1e-6,
			"audio battle: a parry plays Parry once (0.8, fixed pitch) and no hit sound", fmt("%d parry", #par))
		f = fire({ { type = "Parry", unit = theirs.id } })
		T.eq(#playsOf(log, "Parry", f), 0, "audio battle: the rival's parry is silent here (my pets' skill reward only)")
		-- a dash: my pet's plays Dash once (Net.Pre's early start + the handler: still one), the rival's is silent
		f = fire({ { type = "Dash", unit = mine.id, dx = 1, dz = 0 } })
		T.eq(#playsOf(log, "Dash", f), 1, "audio battle: my pet's dash plays Dash once")
		KC.advance(0.6)
		f = fire({ { type = "Dash", unit = theirs.id, dx = -1, dz = 0 } })
		T.eq(#playsOf(log, "Dash", f), 0, "audio battle: the rival's dash is silent")
		-- a KO: one of the four KO files
		f = fire({ { type = "KO", unit = theirs.id } })
		local kos = playsOf(log, "^KO%d?$", f, true)
		T.check(#kos == 1 and math.abs(kos[1].vol - SF.SlotVolume(kos[1].name)) < 1e-6, "audio battle: a KO plays one KO file of the rotation at 0.7", fmt("%d (%s)", #kos, kos[1] and kos[1].name or "-"))
		BC.HandleState("End", { BattleId = p.BattleId, Mode = "Duel", Outcome = "Loss", Won = false, Rewards = {} }, p.BattleId)
		KC.advance(8)
		-- a spectator: half volume near the camera, nothing far away
		freshGaps(SF)
		local q, a, b = duelStart("audio_w2_watch", 0)
		BC.HandleState("Start", q, q.BattleId)
		feed(q, 0.4)
		local au = BC._Unit(a.id)
		local at = au and au.root and au.root.Position or Vector3.new(0, 400, 0)
		if cam then
			cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 20, 30), at)
		end
		local fireQ = function(list)
			local from = #log
			BC.HandleState("Events", list, q.BattleId)
			feed(q, 0.8)
			return from
		end
		f = fireQ({ { type = "Hit", from = a.id, to = b.id, dmg = 10 } })
		local near = playsOf(log, "^Hit", f, true)
		T.check(#near == 1 and math.abs(near[1].vol - SF.SlotVolume("Hit" .. a.element) * 0.5) < 1e-6,
			"audio battle: a spectator hears a hit near the camera at half volume", near[1] and fmt("%.3f", near[1].vol) or "none")
		if cam then
			cam.CFrame = CFrame.new(at + Vector3.new(0, 400, 900))
		end
		f = fireQ({ { type = "Hit", from = a.id, to = b.id, dmg = 10 }, { type = "KO", unit = b.id } })
		T.check(#playsOf(log, "^Hit", f, true) == 0 and #playsOf(log, "^KO", f, true) == 0, "audio battle: ... and nothing from a fight more than 80 studs from the camera")
		BC.HandleState("End", { BattleId = q.BattleId, Mode = "Duel", Spectator = true, Reason = "OutOfRange" }, q.BattleId)
		KC.advance(0.5)
		-- a won Champion Ring round plays Reward (and keeps the Battle track)
		freshGaps(SF)
		BC.HandleState("Start", startPayload("audio_w2_ring", "Ring", 1, { Ring = { Round = 1, Best = 0 } }), "audio_w2_ring")
		KC.advance(0.3)
		f = #log
		BC.HandleState("End", { BattleId = "audio_w2_ring", Mode = "Ring", Outcome = "Win", Won = true, Rewards = { Round = 1, Next = 2, Cash = 5, Xp = 5 } }, "audio_w2_ring")
		KC.advance(0.3)
		T.check(#playsOf(log, "Reward", f) == 1 and SF.Current() == "Battle", "audio battle: a won Champion Ring round plays one Reward and keeps the Battle track",
			fmt("%d rewards, %s", #playsOf(log, "Reward", f), tostring(SF.Current())))
		BC.HandleState("End", { BattleId = "audio_w2_ring", Mode = "Ring", Outcome = "Loss", Won = false, Rewards = { Round = 1, Final = true } }, "audio_w2_ring")
		KC.advance(8)
	end)
	T.check(okRun, "client_audio_battle ran to the end", tostring(err))
	if cam and cam0 then
		cam.CFrame = cam0
	end
	unspy()
	SF.SetLayer("Battle", false)
	freshGaps(SF)
	restore()
	SF.Music("Lobby")
end)

S.client_audio_sites = guarded("client_audio_sites", function()
	local M = mods()
	local Config, SF = M.Config, M.SF
	if not T.check(Config and SF, "audio sites: Config and SoundFx load") then
		return
	end
	local restore = giveIds(Config)
	local log, unspy = spy(SF)
	local e0 = #Mock.Errors
	local okRun, err = pcall(function()
		freshGaps(SF)
		-- a refused action: a NEW "bad" toast plays Error once; its merged repeat and a good toast are silent
		local f = #log
		KC.toClient("Notify", "You cannot claim this home", "bad", 3)
		KC.advance(0.2)
		KC.toClient("Notify", "You cannot claim this home", "bad", 3)
		KC.toClient("Notify", "Welcome back!", "good", 3)
		KC.advance(0.2)
		T.eq(#playsOf(log, "Error", f), 1, "audio sites: a new \"bad\" toast plays Error once (its merged repeat and a good toast do not)")
		KC.toClient("Notify", "Every home is taken right now", "bad", 3)
		KC.advance(0.2)
		T.eq(#playsOf(log, "Error", f), 1, "audio sites: ... another bad toast inside 1 s stays silent (Error MinGap)")
		KC.advance(6)
		-- the tutorial: a finished step plays TutorialStep, the finale Reward
		local Steps = moduleAt(ROOTS.shared .. "/TutorialSteps")
		if T.check(Steps and type(Steps.Steps) == "table" and #Steps.Steps >= 3, "audio sites: TutorialSteps loads") then
			local function payload(index, over)
				local step = Steps.Steps[index]
				local st = { Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = tostring(step.Text), CompleteOn = step.CompleteOn,
					Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true, Gift = step.Gift == true, Chapter = step.Chapter,
					Done = false, Completed = false, Skipped = false, Reward = 0 }
				for k, v in pairs(over or {}) do
					st[k] = v
				end
				return st
			end
			KC.toClient("TutorialState", payload(1))
			KC.advance(0.5)
			f = #log
			KC.toClient("TutorialState", payload(2))
			KC.advance(0.5)
			T.eq(#playsOf(log, "TutorialStep", f), 1, "audio sites: a finished tutorial step plays TutorialStep")
			f = #log
			KC.toClient("TutorialState", payload(#Steps.Steps, { Done = true, Completed = true, Reward = 100 }))
			KC.advance(0.5)
			T.check(#playsOf(log, "Reward", f) == 1 and #playsOf(log, "TutorialStep", f) == 0, "audio sites: the tutorial's finale plays Reward")
			KC.advance(8)
		end
		-- the roulette: SpinStart, a SpinTick per cell, SpinLand, the reveal by rarity
		local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
		local possible = PC and type(PC.PossiblePets) == "function" and PC.PossiblePets("Cloud") or {}
		if T.check(#possible > 0, "audio sites: the Cloud roulette's pets") then
			local strip = {}
			for i = 1, 40 do
				strip[i] = possible[(i % #possible) + 1].Id
			end
			local winner = possible[1]
			strip[34] = winner.Id
			freshGaps(SF)
			f = #log
			KC.toClient("RouletteResult", { Ok = true, RouletteId = "Cloud", PetId = winner.Id, IsNew = true, Count = 1, Tokens = 550, Strip = strip })
			KC.advance(0.2)
			local started = #playsOf(log, "SpinStart", f)
			KC.advance(10)
			local want = ({ Common = "RevealCommon", Uncommon = "RevealCommon", Rare = "RevealRare", Epic = "RevealRare", Legendary = "RevealLegendary",
				Mythic = "RevealLegendary", Secret = "RevealLegendary" })[winner.Rarity]
			local ticks = #playsOf(log, "SpinTick", f)
			T.check(started == 1, "audio sites: a roulette spin plays SpinStart once", tostring(started))
			T.check(ticks >= 8, "audio sites: the strip ticks as cells pass the pointer (SpinTick)", ticks .. " ticks")
			T.eq(#playsOf(log, "SpinLand", f), 1, "audio sites: the strip's landing plays SpinLand once")
			T.check(#playsOf(log, want or "?", f) == 1 and #playsOf(log, "^Reveal", f, true) == 1,
				"audio sites: the reveal card plays " .. tostring(want) .. " for a " .. tostring(winner.Rarity) .. " pet")
			pressKey("Escape")
			KC.advance(0.6)
			pressKey("Escape")
			KC.advance(0.6)
		end
		-- my home portal: PortalEnter when it opens, PortalArrive on my arrival; another player's: silent
		local At = Config.Attr or {}
		local portalAttr, arrivedAttr = At.HomePortal or "HomePortal", At.PortalArrived or "PortalArrived"
		local now = Workspace:GetServerTimeNow()
		freshGaps(SF)
		f = #log
		LocalPlayer:SetAttribute(portalAttr, "120,20,120,0," .. string.format("%.2f", now + 10))
		KC.advance(0.3)
		T.eq(#playsOf(log, "PortalEnter", f), 1, "audio sites: my home portal opening plays PortalEnter")
		local other = Mock.AddPlayer("PortalNeighbour", 6202)
		KC.advance(0.2)
		f = #log
		other:SetAttribute(portalAttr, "160,20,120,0," .. string.format("%.2f", now + 10))
		other:SetAttribute(arrivedAttr, now)
		KC.advance(0.3)
		T.check(#playsOf(log, "PortalEnter", f) == 0 and #playsOf(log, "PortalArrive", f) == 0, "audio sites: another player's portal and arrival are silent")
		f = #log
		LocalPlayer:SetAttribute(arrivedAttr, now + 0.5)
		KC.advance(0.3)
		local hasRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") ~= nil
		T.check(hasRoot and #playsOf(log, "PortalArrive", f) == 1, "audio sites: my arrival through the portal plays PortalArrive", "root " .. tostring(hasRoot))
		LocalPlayer:SetAttribute(portalAttr, nil)
		other:SetAttribute(portalAttr, nil)
		KC.advance(0.6)
		Mock.RemovePlayer(other)
		-- a lobby Travel gate (GateService's AltarGatePrompt): PortalEnter
		KC.advance(1.1)
		local gate = Instance.new("Part")
		gate.Name = "AudioGate"
		gate.Parent = Workspace
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AltarGatePrompt"
		prompt.Parent = gate
		local talk = Instance.new("ProximityPrompt")
		talk.Name = "SomeOtherPrompt"
		talk.Parent = gate
		f = #log
		Mock.Trigger(talk, LocalPlayer)
		KC.advance(0.2)
		local none = #playsOf(log, "PortalEnter", f)
		Mock.Trigger(prompt, LocalPlayer)
		KC.advance(0.2)
		T.check(none == 0 and #playsOf(log, "PortalEnter", f) == 1, "audio sites: using a Travel gate's prompt plays PortalEnter (another prompt does not)")
		gate:Destroy()
		-- my home: a new station pops in (StationBuild), my house's new tier (HouseTier); a neighbour's home is silent
		local function home(owner, at)
			local folder = Instance.new("Folder")
			folder.Name = "AudioHome_" .. owner
			folder:SetAttribute("OwnerUserId", owner)
			folder:SetAttribute("PlotCenter", at)
			folder.Parent = Workspace
			CollectionService:AddTag(folder, "NC_Home")
			return folder
		end
		local function station(folder, id, level, at)
			local m = Instance.new("Model")
			m.Name = "Station_" .. id
			m:SetAttribute("StationId", id)
			m:SetAttribute("Level", level)
			m:SetAttribute("Kind", "Decor")
			m:SetAttribute("BuiltAt", Workspace:GetServerTimeNow())
			local part = Instance.new("Part")
			part.Size = Vector3.new(4, 2, 4)
			part.CFrame = CFrame.new(at)
			part.Parent = m
			m.Parent = folder
			return m
		end
		local mineHome = home(LocalPlayer.UserId, Vector3.new(5000, 300, 5000))
		local theirHome = home(6203, Vector3.new(5200, 300, 5000))
		KC.advance(0.5)
		freshGaps(SF)
		f = #log
		station(mineHome, "DecorFence", 1, Vector3.new(5000, 301, 5000))
		KC.advance(0.3)
		local built = #playsOf(log, "StationBuild", f)
		station(mineHome, "House", 2, Vector3.new(5010, 301, 5000))
		KC.advance(0.3)
		local tier = #playsOf(log, "HouseTier", f)
		station(theirHome, "DecorFence", 1, Vector3.new(5200, 301, 5000))
		station(theirHome, "House", 3, Vector3.new(5210, 301, 5000))
		KC.advance(0.3)
		T.eq(built, 1, "audio sites: a new station of my home plays StationBuild")
		T.check(tier == 1 and #playsOf(log, "StationBuild", f) == 1, "audio sites: my house's new tier plays HouseTier instead of StationBuild")
		T.check(#playsOf(log, "HouseTier", f) == 1, "audio sites: a neighbour's new station / house tier is silent")
		mineHome:Destroy()
		theirHome:Destroy()
		KC.advance(0.3)
		-- the lobby fountain: SoundFx.Positional("Fountain") on the falls (InverseTapered, Min 10 / Max 70, the Sfx setting)
		local FF = moduleAt(ROOTS.client .. "/Controllers/FountainFx")
		if T.check(FF and FF._St and FF.K, "audio sites: FountainFx loads") then
			local old = FF._St.Sound
			FF._St.Sound = nil
			local falls = Instance.new("Part")
			falls.Name = "AudioFalls"
			falls.Parent = Workspace
			CollectionService:AddTag(falls, FF.K.FALLS_TAG)
			KC.advance(0.2)
			local s = FF._St.Sound
			T.check(s ~= nil and s.Parent == falls and s.Looped and s.IsPlaying and s.RollOffMode == Enum.RollOffMode.InverseTapered and s.RollOffMinDistance == 10
				and s.RollOffMaxDistance == FF.K.SOUND_RANGE and math.abs(s.Volume - SF.SlotVolume("Fountain")) < 1e-6
				and s.SoundId == "rbxassetid://" .. string.format("%d", Config.Audio.Ambient.Fountain),
				"audio sites: the fountain's water loops through SoundFx.Positional(\"Fountain\") once FountainLoop has an id (InverseTapered 10-70 studs, slot volume x Sfx)",
				s and fmt("%s %s %.3f", s.Name, s.SoundId, s.Volume) or "no sound")
			CollectionService:RemoveTag(falls, FF.K.FALLS_TAG)
			falls:Destroy()
			FF._St.Sound = old
		end
	end)
	T.check(okRun, "client_audio_sites ran to the end", tostring(err))
	T.check(#Mock.Errors == e0, "audio sites: no script error")
	unspy()
	freshGaps(SF)
	restore()
end)

S.client_audio_npc = guarded("client_audio_npc", function()
	local M = mods()
	local Config, SF = M.Config, M.SF
	local NC = moduleAt(ROOTS.client .. "/Controllers/NpcController")
	local ND = moduleAt(ROOTS.shared .. "/NpcDialog")
	local services = Mock.GetPath(ROOTS.server)
	services = services and services:FindFirstChild("Services")
	local npcModule = services and services:FindFirstChild("NpcService")
	if not T.check(Config and SF and NC and ND and npcModule, "audio npc: NpcController, NpcDialog and NpcService load") then
		return
	end
	local A = Config.Audio
	-- every NPC of NpcDialog has its three voice keys (Npc<CamelCase Id><Kind>)
	local lack = {}
	for _, def in ipairs(ND.Npcs) do
		for _, kind in ipairs({ "Greet", "Hmm", "Pleased" }) do
			if A.Keys.Sfx["Npc" .. camelId(def.Id) .. kind] == nil then
				lack[#lack + 1] = "Npc" .. camelId(def.Id) .. kind
			end
		end
	end
	T.check(#lack == 0 and #ND.Npcs == 6, "audio npc: the six NPCs (" .. #ND.Npcs .. ") each have Greet / Hmm / Pleased voice keys", table.concat(lack, " "))
	local restore = giveIds(Config)
	local log, unspy = spy(SF)
	local e0 = #Mock.Errors
	local NS = require(npcModule)
	local origin = (Config.Lobby and Config.Lobby.Origin) or Vector3.new(0, 10, 0)
	local spots = {}
	for i = 1, #ND.Npcs do
		local a = (i - 1) * math.pi * 2 / #ND.Npcs
		local pos = origin + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
		spots[i] = CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
	end
	local first = ND.Npcs[1]
	local saved = first.Lines
	local okRun, err = pcall(function()
		NS.Init({ NpcSpots = spots })
		KC.advance(2)
		Mock.Teleport(LocalPlayer, spots[1].Position + spots[1].LookVector * 7 + Vector3.new(0, 3, 0))
		KC.advance(0.5)
		NC.Close()
		KC.advance(2)
		first.Lines = { "Hello there, climber.", "Ready for a climb?", "Watch the sky up there!", "Well... the sky is wide.", "Off you go then." }
		freshGaps(SF)
		local voiceKey = "Npc" .. camelId(first.Id)
		T.eq(voiceKey, "NpcSparkyFox", "audio npc: sparky_fox's voice keys are NpcSparkyFox*")
		local function voicesSince(at)
			return #playsOf(log, "^" .. voiceKey, at, true)
		end
		local f = #log
		NC.Open(first.Id)
		KC.advance(0.06)
		local opened = #playsOf(log, "DialogOpen", f)
		local early = #playsOf(log, voiceKey .. "Greet", f)
		KC.advance(0.12)
		local greet = playsOf(log, voiceKey .. "Greet", f)
		T.check(opened == 1, "audio npc: opening the dialog plays DialogOpen")
		T.check(early == 0 and #greet == 1 and math.abs(greet[1].vol - 0.6 * SF.Volume("Sfx")) < 1e-6 and greet[1].speed >= 0.98 - 1e-9 and greet[1].speed <= 1.02 + 1e-9,
			"audio npc: the NPC's Greet follows ~0.12 s after DialogOpen (volume 0.6 x Sfx, pitch 0.98-1.02)", fmt("early %d, then %d", early, #greet))
		KC.advance(3)
		-- the typewriter: a blip every 3rd letter ("Hello there, climber." = 17 letters -> 6 blips), never all letters
		local blips = #playsOf(log, "DialogBlip", f)
		T.check(blips >= 5 and blips <= 6, "audio npc: the typewriter blips every 3rd letter (17 letters -> 6 blips; MinGap 0.045 s)", blips .. " blips")
		-- Next to a middle line with no "!": DialogNext + Hmm
		f = #log
		NC.Advance()
		KC.advance(0.1)
		local hmm = playsOf(log, voiceKey .. "Hmm", f)
		T.check(#playsOf(log, "DialogNext", f) == 1 and #hmm == 1 and voicesSince(f) == 1, "audio npc: Next to a middle line (no \"!\") plays DialogNext and the NPC's Hmm", fmt("%d hmm", #hmm))
		KC.advance(2)
		-- Next to a middle line holding "!": Pleased, and the NPC's previous voice is stopped first
		local hmmSound = hmm[1] and hmm[1].sound
		f = #log
		NC.Advance()
		KC.advance(0.1)
		local bang = playsOf(log, voiceKey .. "Pleased", f)
		T.check(#bang == 1 and voicesSince(f) == 1 and bang[1].sound.IsPlaying, "audio npc: Next to a line holding \"!\" plays the NPC's Pleased (not Hmm)")
		T.check(hmmSound ~= nil and not hmmSound.IsPlaying, "audio npc: ... after stopping the NPC's previous voice (never two at once)")
		-- finishing a line early is silent; a new line inside the 1.5 s voice gap: DialogNext, no voice
		f = #log
		NC.Advance() -- (still typing: finishes the line)
		KC.advance(0.1)
		local early2 = #playsOf(log, "DialogNext", f)
		local earlyVoice = voicesSince(f)
		NC.Advance()
		KC.advance(0.1)
		T.check(early2 == 0 and earlyVoice == 0, "audio npc: finishing a line early (Next while it types) plays no DialogNext and no voice")
		T.check(#playsOf(log, "DialogNext", f) == 1 and voicesSince(f) == 0, "audio npc: a fast Next within 1.5 s of the last voice gets no voice (one per 1.5 s per NPC)")
		KC.advance(2)
		-- the last line (no "!"): Pleased
		f = #log
		NC.Advance()
		KC.advance(0.1)
		local pleased = playsOf(log, voiceKey .. "Pleased", f)
		T.check(#pleased == 1 and voicesSince(f) == 1 and pleased[1].sound.IsPlaying, "audio npc: Next to the dialog's last line plays the NPC's Pleased")
		-- "Again" (back to line 1, not the last, no "!"): DialogNext + Hmm
		KC.advance(2)
		f = #log
		NC.Advance()
		KC.advance(0.3)
		T.check(#playsOf(log, "DialogNext", f) == 1 and #playsOf(log, voiceKey .. "Hmm", f) == 1 and voicesSince(f) == 1, "audio npc: Again (back to line 1, no \"!\") plays DialogNext and the NPC's Hmm")
		KC.advance(2)
		-- switching to another NPC mid-dialog: no DialogOpen, no Greet
		local second = ND.Npcs[2]
		f = #log
		NC.Open(second.Id)
		KC.advance(0.3)
		T.check(#playsOf(log, "DialogOpen", f) == 0 and #playsOf(log, "Npc" .. camelId(second.Id) .. "Greet", f) == 0,
			"audio npc: switching to another NPC mid-dialog plays no DialogOpen and no Greet")
		NC.Close()
		KC.advance(2)
		-- closing before the greet: no Greet
		f = #log
		NC.Open(first.Id)
		KC.advance(0.03)
		NC.Close()
		KC.advance(0.5)
		T.check(#playsOf(log, "DialogOpen", f) == 1 and #playsOf(log, voiceKey .. "Greet", f) == 0, "audio npc: a dialog closed before its greet is due plays no Greet")
		-- an NPC with no voice ids: DialogOpen still plays, no voice, no error
		local svIds = {}
		for _, kind in ipairs({ "Greet", "Hmm", "Pleased" }) do
			svIds[kind] = A.Sfx[voiceKey .. kind]
			A.Sfx[voiceKey .. kind] = nil
		end
		KC.advance(2)
		f = #log
		NC.Open(first.Id)
		KC.advance(0.4)
		for _ = 1, #first.Lines do
			NC.Advance()
			KC.advance(0.1)
			NC.Advance()
			KC.advance(0.1)
		end
		T.check(#playsOf(log, "DialogOpen", f) == 1 and #playsOf(log, "^" .. voiceKey, f, true) == 0, "audio npc: an NPC without voice ids talks silently (no voice, no error)")
		for kind, v in pairs(svIds) do
			A.Sfx[voiceKey .. kind] = v
		end
		NC.Close()
		KC.advance(0.5)
	end)
	first.Lines = saved
	T.check(okRun, "client_audio_npc ran to the end", tostring(err))
	T.check(#Mock.Errors == e0, "audio npc: no script error")
	local holder = Workspace:FindFirstChild("NimbusNpcs")
	if holder then
		holder:Destroy()
	end
	KC.advance(0.5)
	Mock.Teleport(LocalPlayer, Vector3.new(0, 20, 0))
	unspy()
	freshGaps(SF)
	restore()
end)

return S
