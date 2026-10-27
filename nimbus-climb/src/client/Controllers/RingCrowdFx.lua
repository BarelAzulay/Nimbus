-- RingCrowdFx (client, bug #11 "crowd needs animation and sound"; the player's pick: the Sky-Sailors' Ring with a
-- drummer): the Champion Ring's crowd of retired weather clouds comes alive. The server (ArenaBuilder Ring.spectator)
-- builds each spectator as a Model tagged "RingCrowd" with separate anchored ROOT parts: Body, ArmL, ArmR, Cap and
-- (Drizzle, the ship's drummer boy) Drum. Each root carries its mesh pivot in the "CrowdOff" attribute; once the
-- Blender keys are uploaded the dressed meshes are welded to the roots (ML_Weld) and simply ride them. Next to the
-- spectators hang the FlagLine (the signal flags) and the ship's Bell. Here, on this client only:
--   * idle: the whole stand sways in time with Drizzle's drum (120 beats a minute, the sticks alternate, every cloud
--     bobs on every second beat a little after the drum, each with its own lag, and breathes; Drizzle himself drops
--     onto every stroke with no lag, leaning in, and the drum dips under it), Fog's spyglass droops as he dozes,
--     the signal flags swing in the wind, Rain drips and Snow lets flakes drift (particles, off on Low graphics);
--   * a big hit or a KO (BattleState "Events" of a Champion Ring battle: a KO, a Special, or a hit far above the
--     battle's running average): everyone leans back with the arms up ("rumble-oooh"), the Thunder Captain flashes with
--     a lightning bolt (a PointLight + two Beams), Drizzle misses a beat, Fog snaps his spyglass up;
--   * a round won ("End" won): they hop and throw their arms up, the caps fly, the bell swings, the drum goes double
--     time (ship's bell + rain-patter applause);
--   * a round lost: they droop ("awww");
--   * a boss round ("Start".Ring.Champion.Boss): the clouds darken and lean in, drizzle falls from all of them, the
--     drum rolls (a low thunder roll), until that round ends.
-- Sounds play only when Config.Audio.Crowd holds ids (all empty today: the owner pastes them; README); the idle drum
-- tap only during a ring fight. The ids and the Sfx volume are read once per REFRESH, not per sound. Voices are 3D
-- Sounds on each body with its own PlaybackSpeed (0.9 - 1.2), so a cheer sounds like a crowd and not one voice.
-- Cheap: ONE Heartbeat connection, UPDATE_HZ (LOW_HZ on Low graphics), only stands within RANGE studs of the camera
-- move; out of range, on Stop() or when the tag goes away every part returns exactly to its rest frame and colour.
--
--   RingCrowdFx.Init()                       idempotent (Main.client.lua starts it)
--   RingCrowdFx.Stop()                       everything back at rest, client instances removed
--   RingCrowdFx.Step(dt)                     one Heartbeat step (tests drive it)
--   RingCrowdFx.Cue(name)                    "Hit" | "Won" | "Lost" | "Boss" | "BossEnd" (the battle hooks call it; tests)
--   RingCrowdFx.HandleState(kind, payload)   the BattleState remote's handler (Start / Events / End)
--   RingCrowdFx.Pose(spec, t, cue, cueT, boss) -> pose   pure: the offsets of one spectator at time t
--   RingCrowdFx.StickAngle(side, beat, mode) -> radians  pure: a drumstick's lift (0 = on the drum head)
--   RingCrowdFx.Stats() -> { Spectators, Moving, Writes, Beats, Cue, Boss, Quality, Sounds, Emitters }
--   RingCrowdFx.K                            the tuning numbers
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RingCrowdFx = {}

local K = {
	TAG = "RingCrowd",
	RANGE = 160, -- studs from the camera: farther stands rest
	UPDATE_HZ = 30,
	LOW_HZ = 15,
	REFRESH = 0.5,
	BPM = 120, -- Drizzle's beat (a ship's quick march)
	-- the idle has to read from the fighter's spawn (~45 studs) for a whole run: the fix round raised it from
	-- 0.08 studs / 0.045 rad / 0.14 rad, which looked static even close up
	BOB = 0.3, -- studs: the idle bob on every second beat
	SWAY = 0.1, -- radians: the idle side-to-side roll (one sway per 4 beats)
	BREATHE = 0.05, -- radians: a slow breathing lean, back and forth (BREATH_S seconds)
	BREATH_S = 3.2,
	LAG = 0.22, -- beats: the most a cloud lags behind the drum
	ARM_IDLE = 0.3, -- radians the arms swing in idle
	STICK_UP = 0.65, -- radians a drumstick (the whole stick arm) lifts between two hits (0.5 before; more and the
	-- raised stick covers his eyes from the front)
	-- Drizzle carries the beat with his whole body, on the beat, no lag: he bobs up between hits and drops onto every
	-- hit, leaning into it, his shoulders rocking toward the hitting stick, and the drum dips under the stroke
	DRUM_DIP = 0.2, -- studs
	DRUM_LEAN = 0.1, -- radians (forward, on the hit)
	DRUM_ROLL = 0.06, -- radians (toward the stick that is coming down)
	DRUM_BOUNCE = 0.08, -- studs the drum dips under a stroke
	ROLL_HZ = 7, -- strokes per second per stick in a drum roll
	HIT_TIME = 1.2,
	WON_TIME = 2.8,
	LOST_TIME = 2.2,
	HOP = 0.9, -- studs: a round-won hop
	CAP_FLY = 2.2, -- studs a sailor cap flies up when a round is won (the captain's 1.2)
	BELL_SWING = 0.65, -- radians
	BOSS_DARK = 0.38, -- how far the clouds go toward the storm colour in a boss round
	BOSS_LEAN = -0.13, -- radians (forward)
	STORM = Color3.fromRGB(78, 84, 108),
	FLAG_SWING = 0.07, -- radians
	BIG_HIT = 1.8, -- a hit this many times the battle's running average is a big hit
	BIG_MIN_HITS = 3,
	CUE_GAP = 2.0, -- seconds between two big-hit cues
	VOICE = 0.32, -- volume of one cloud's voice x the Sfx setting
	SOUND_RANGE = 90,
}
RingCrowdFx.K = K

local TWO_PI = math.pi * 2
local sin, cos, abs, max, min, exp, floor, sqrt = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.floor, math.sqrt
local SIDES = { "ArmL", "ArmR" }
local PIECES = { "Body", "ArmL", "ArmR", "Cap", "Drum" }

local St = {
	Started = false,
	Specs = {}, -- [model] = rec
	Count = 0,
	Extras = {}, -- [part] = { Part, Kind = "Flags" | "Bell", Rest, Kids }
	Conns = {},
	Time = 0,
	Acc = 0,
	RefreshAcc = 0,
	Quality = "High",
	Quality0 = nil,
	Writes = 0,
	Beats = 0,
	LastBeat = -1,
	Cue = nil, -- { Name, T0 }
	Boss = false,
	BossFade = 0,
	Battle = nil, -- { Id, Hits, Sum, LastCue }
	Sounds = {},
	Audio = nil, -- Config.Audio.Crowd, cached (refreshed every REFRESH)
	Sfx = 1, -- the Sfx setting 0..1, cached (refreshed every REFRESH)
	Emitters = 0,
	Rng = Random.new(11),
}
RingCrowdFx._St = St

local function quality()
	if St.Quality0 == nil then
		St.Quality0 = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" and type(mod.Effective) == "function" then
				St.Quality0 = mod
			end
		end
	end
	if St.Quality0 then
		local ok, mode = pcall(St.Quality0.Effective)
		if ok and (mode == "Low" or mode == "High") then
			return mode
		end
	end
	return "High"
end

local function clamp01(x)
	return max(0, min(1, x))
end

-- 0 -> 1 -> 0 over `span` seconds (a cue's envelope)
local function env(t, span)
	if t < 0 or t > span then
		return 0
	end
	return sin(math.pi * t / span)
end

----------------------------------------------------------------------
-- Pure motion (tests and the renders use these)
----------------------------------------------------------------------
-- a drumstick's lift at `beat` (beats since start). side -1 = left (hits on even beats), 1 = right (odd beats).
-- mode: "idle" | "double" (two hits per beat) | "roll" (fast, small) | "miss" (both held up)
function RingCrowdFx.StickAngle(side, beat, mode)
	if mode == "miss" then
		return K.STICK_UP * 1.4
	end
	if mode == "roll" then
		local f = (beat * 60 / K.BPM) * K.ROLL_HZ + ((side < 0) and 0 or 0.5)
		return K.STICK_UP * 0.3 * sin(math.pi * (f % 1)) ^ 2
	end
	local per = (mode == "double") and 1 or 2 -- beats between two hits of one stick
	local off = (side < 0) and 0 or per / 2
	local p = ((beat - off) / per) % 1
	return K.STICK_UP * sin(math.pi * p) ^ 2
end

-- the pose of one spectator. spec = { Name, Phase (0..1), Drummer, Captain, Cap ("sailor" | "captain" | nil) };
-- cue = "Hit" | "Won" | "Lost" | nil and cueT = seconds since it began; boss = 0..1 (the boss fade).
-- -> { Lift, Lean, Roll, ArmL, ArmR (extra roll out, radians), StickL, StickR, Glass (spyglass pitch), CapUp, CapSpin,
--      Flash (0..1), BellSwing, DrumDip (studs, <= 0) }
-- out (optional): a table to fill in place (RingCrowdFx keeps one per spectator: no allocation per tick)
function RingCrowdFx.Pose(spec, t, cue, cueT, boss, out)
	local beat = t * K.BPM / 60
	local ph = spec.Phase or 0
	local b2 = (beat / 2 - ph * K.LAG * 2) % 1 -- every second beat, a little after the drum
	local pose = out or {}
	local bob = K.BOB * (0.5 + 0.5 * cos(TWO_PI * b2))
	pose.Lift = bob
	pose.Lean = K.BREATHE * sin(TWO_PI * (t / K.BREATH_S + ph))
	pose.Roll = K.SWAY * sin(TWO_PI * (beat / 4 + ph))
	pose.ArmL = K.ARM_IDLE * sin(TWO_PI * (beat / 2 + ph))
	pose.ArmR = K.ARM_IDLE * sin(TWO_PI * (beat / 2 + ph + 0.5))
	pose.StickL = 0
	pose.StickR = 0
	pose.Glass = -0.12 - 0.1 * (0.5 + 0.5 * sin(TWO_PI * (t / 7 + ph))) -- Fog dozes: the spyglass sinks, comes back
	pose.CapUp = 0
	pose.CapSpin = 0
	pose.Flash = 0
	pose.BellSwing = 0
	pose.DrumDip = 0
	local mode = "idle"
	boss = boss or 0
	if boss > 0 then
		pose.Lean = pose.Lean + K.BOSS_LEAN * boss
		pose.Lift = pose.Lift * (1 - 0.6 * boss)
		bob = bob * (1 - 0.6 * boss)
		mode = "roll"
	end
	if cue == "Hit" and cueT and cueT <= K.HIT_TIME then
		local e = env(cueT, K.HIT_TIME)
		pose.Lean = pose.Lean + 0.26 * e
		pose.ArmL = pose.ArmL + 0.9 * e
		pose.ArmR = pose.ArmR + 0.9 * e
		pose.Glass = pose.Glass + (0.3 - pose.Glass) * clamp01(e * 2) -- Fog wakes up and looks
		if spec.Captain then
			pose.Flash = clamp01(1 - cueT / 0.45)
		end
		if cueT < 0.6 then
			mode = "miss"
		end
	elseif cue == "Won" and cueT and cueT <= K.WON_TIME then
		local e = env(cueT, K.WON_TIME)
		local hopT = cueT + ph * 0.2
		pose.Lift = pose.Lift + K.HOP * abs(sin(math.pi * hopT / 0.62)) * (1 - cueT / K.WON_TIME)
		pose.ArmL = pose.ArmL + 1.7 * clamp01(e * 2)
		pose.ArmR = pose.ArmR + 1.7 * clamp01(e * 2)
		local fly = (spec.Cap == "captain") and K.CAP_FLY * 0.55 or K.CAP_FLY
		if cueT < 1.1 then
			pose.CapUp = fly * sin(math.pi * cueT / 1.1)
			pose.CapSpin = TWO_PI * cueT / 1.1
		end
		pose.BellSwing = K.BELL_SWING * exp(-cueT / 1.2) * sin(TWO_PI * cueT / 0.9)
		pose.Glass = 0.25
		mode = "double"
	elseif cue == "Lost" and cueT and cueT <= K.LOST_TIME then
		local e = env(cueT, K.LOST_TIME)
		pose.Lift = pose.Lift - 0.12 * e
		pose.Lean = pose.Lean - 0.14 * e
		pose.ArmL = pose.ArmL - 0.75 * e
		pose.ArmR = pose.ArmR - 0.75 * e
		mode = (cueT < 0.8) and "miss" or mode
	end
	if spec.Drummer then
		local sL = RingCrowdFx.StickAngle(-1, beat, mode)
		local sR = RingCrowdFx.StickAngle(1, beat, mode)
		pose.StickL, pose.StickR = sL, sR
		-- his body keeps the drum's time (not the crowd's lagged half-time bob): `up` is 0 on a stroke and 1 half way
		-- between two strokes; its square root makes a V, so he drops sharply onto every hit and floats up between
		local up = sqrt(clamp01(min(sL, sR) / (K.STICK_UP * 0.5)))
		local hit = 1 - up
		local amt = (mode == "roll") and 0.35 or 1
		pose.Lift = pose.Lift - bob + K.DRUM_DIP * up * amt
		pose.Lean = pose.Lean - K.DRUM_LEAN * hit * amt -- forward (negative, like BOSS_LEAN)
		pose.Roll = pose.Roll + K.DRUM_ROLL * (sR - sL) / K.STICK_UP * amt
		pose.DrumDip = -K.DRUM_BOUNCE * hit * amt
	end
	return pose
end

----------------------------------------------------------------------
-- Tracking
----------------------------------------------------------------------
-- a root part's rest record: its rest CFrame, its mesh pivot (CrowdOff) and its anchored kids' offsets
local function piece(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local off = part:GetAttribute("CrowdOff")
	if typeof(off) ~= "CFrame" then
		off = CFrame.new()
	end
	local rec = { Part = part, Rest = part.CFrame, Off = off, Pivot = part.CFrame * off, Kids = {}, Seen = {} }
	return rec
end

local function collectKids(rec)
	for _, d in ipairs(rec.Part:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored and not rec.Seen[d] then
			rec.Seen[d] = true
			rec.Kids[#rec.Kids + 1] = { Part = d, Offset = rec.Rest:ToObjectSpace(d.CFrame) }
		end
	end
end

-- puts a root (and its kids) where its mesh pivot is `pivot`
local function placePiece(rec, pivot)
	local cf = pivot * rec.Off:Inverse()
	rec.Part.CFrame = cf
	St.Writes = St.Writes + 1
	for _, k in ipairs(rec.Kids) do
		if k.Part.Parent and k.Part.Transparency < 0.99 then
			k.Part.CFrame = cf * k.Offset
			St.Writes = St.Writes + 1
		end
	end
end

local function restPiece(rec)
	if rec and rec.Part.Parent then
		rec.Part.CFrame = rec.Rest
		for _, k in ipairs(rec.Kids) do
			if k.Part.Parent then
				k.Part.CFrame = rec.Rest * k.Offset
			end
		end
	end
end

local function colourStore(rec)
	rec.Colours = rec.Colours or {}
	for _, d in ipairs(rec.Model:GetDescendants()) do
		if d:IsA("BasePart") and rec.Colours[d] == nil then
			rec.Colours[d] = d.Color
		end
	end
end

-- tints every part `amount` of the way to the storm colour; a no-op when that amount is already applied (a boss round
-- sits at a constant BOSS_DARK: no per-tick colour writes once the fade is done)
local function applyDark(rec, amount)
	if amount <= 0 and not rec.Dark then
		return
	end
	if rec.Dark and rec.DarkAmount == amount then
		return
	end
	colourStore(rec)
	for part, c in pairs(rec.Colours) do
		if part.Parent then
			part.Color = c:Lerp(K.STORM, amount)
		end
	end
	rec.Dark = amount > 0 or nil
	rec.DarkAmount = amount
end

local function restRec(rec)
	if not rec.Moving then
		return
	end
	for _, p in pairs(rec.Pieces) do
		restPiece(p)
	end
	if rec.Dark then
		applyDark(rec, 0)
		rec.Dark = nil
	end
	if rec.Light then
		rec.Light.Brightness = 0
	end
	if rec.Bolt then
		rec.Bolt.Parent = nil
	end
	for _, e in ipairs(rec.Emitters or {}) do
		e.Enabled = false
	end
	rec.Moving = false
end

local function shortName(model)
	local n = model:GetAttribute("Spectator")
	return type(n) == "string" and n or model.Name
end

local function trackExtras(crowd)
	if not crowd then
		return
	end
	for _, name in ipairs({ "FlagLine", "Bell" }) do
		local p = crowd:FindFirstChild(name)
		if p and p:IsA("BasePart") and not St.Extras[p] then
			local rec = piece(p)
			rec.Kind = (name == "FlagLine") and "Flags" or "Bell"
			collectKids(rec)
			St.Extras[p] = rec
		end
	end
end

local function track(model)
	if not model:IsA("Model") or St.Specs[model] then
		return
	end
	local name = shortName(model)
	local rec = {
		Model = model,
		Name = name,
		Phase = (St.Count * 0.37) % 1,
		Drummer = model:GetAttribute("Drummer") == true,
		Captain = name == "captain",
		Pieces = {},
		Moving = false,
		Pitch = 0.9 + St.Rng:NextNumber() * 0.3, -- this cloud's voice (0.9 - 1.2)
	}
	local body0 = model:FindFirstChild("Body")
	if not (body0 and body0:IsA("BasePart")) then
		return -- not replicated yet: refresh() retries every REFRESH (it walks the tagged models)
	end
	for _, n in ipairs(PIECES) do
		local p = model:FindFirstChild(n)
		if p then
			rec.Pieces[n] = piece(p)
			collectKids(rec.Pieces[n])
		end
	end
	for _, side in ipairs(SIDES) do -- each arm's kind, read once (not two attribute reads per tick)
		local p = rec.Pieces[side]
		if p then
			p.Kind = p.Part:GetAttribute("CrowdKey")
			p.Sgn = (side == "ArmL") and -1 or 1
		end
	end
	local cap = rec.Pieces.Cap
	rec.Cap = cap and ((cap.Part:GetAttribute("CrowdKey") == "arena_crowd_captaincap") and "captain" or "sailor") or nil
	local body = rec.Pieces.Body
	if not body then
		return
	end
	rec.Seat = body.Pivot
	-- every other piece's pivot in the seat frame (they ride the body)
	for n, p in pairs(rec.Pieces) do
		p.Local = rec.Seat:ToObjectSpace(p.Pivot)
	end
	St.Specs[model] = rec
	St.Count = St.Count + 1
	trackExtras(model.Parent)
end

local function forget(model)
	local rec = St.Specs[model]
	if rec then
		restRec(rec)
		for _, inst in ipairs(rec.Owned or {}) do
			inst:Destroy()
		end
		St.Specs[model] = nil
		St.Count = St.Count - 1
	end
	-- extras whose crowd is gone
	for part, ex in pairs(St.Extras) do
		if not part.Parent then
			St.Extras[part] = nil
		end
	end
end

----------------------------------------------------------------------
-- Client-only bits: weather particles, the captain's flash, voices
----------------------------------------------------------------------
local function own(rec, inst)
	rec.Owned = rec.Owned or {}
	rec.Owned[#rec.Owned + 1] = inst
	return inst
end

local function particles(rec, name, props)
	local body = rec.Pieces.Body and rec.Pieces.Body.Part
	if not body then
		return nil
	end
	local a = own(rec, Instance.new("Attachment"))
	a.Name = "CrowdFx_" .. name
	a.CFrame = rec.Pieces.Body.Off * CFrame.new(props.At or Vector3.new(0, 0.4, -0.6))
	a.Parent = body
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.LightInfluence = 0.6
	e.Enabled = false
	for k, v in pairs(props) do
		if k ~= "At" then
			e[k] = v
		end
	end
	e.Parent = a
	rec.Emitters = rec.Emitters or {}
	rec.Emitters[#rec.Emitters + 1] = e
	St.Emitters = St.Emitters + 1
	return e
end

local function ensureClientBits(rec)
	if rec.Bits then
		return
	end
	rec.Bits = true
	if rec.Name == "rain" then
		rec.Weather = particles(rec, "Drips", {
			At = Vector3.new(0, 0.35, -0.9),
			Color = ColorSequence.new(Color3.fromRGB(126, 186, 242)),
			Rate = 3,
			Lifetime = NumberRange.new(0.5, 0.7),
			Speed = NumberRange.new(0.5, 1),
			Acceleration = Vector3.new(0, -14, 0),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.14),
			Transparency = NumberSequence.new(0.1),
		})
	elseif rec.Name == "snow" then
		rec.Weather = particles(rec, "Flakes", {
			At = Vector3.new(0, 3.4, -0.4),
			Color = ColorSequence.new(Color3.fromRGB(250, 252, 255)),
			Rate = 2,
			Lifetime = NumberRange.new(2.5, 3.5),
			Speed = NumberRange.new(0.3, 0.6),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(30, 30),
			RotSpeed = NumberRange.new(-40, 40),
			Size = NumberSequence.new(0.16),
			Transparency = NumberSequence.new(0.15),
		})
	end
	-- boss-round drizzle under every cloud
	rec.Drizzle = particles(rec, "Drizzle", {
		At = Vector3.new(0, 0.3, -0.5),
		Color = ColorSequence.new(Color3.fromRGB(150, 176, 220)),
		Rate = 6,
		Lifetime = NumberRange.new(0.45, 0.6),
		Speed = NumberRange.new(1, 2),
		Acceleration = Vector3.new(0, -16, 0),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new(0.12),
		Transparency = NumberSequence.new(0.2),
	})
	if rec.Captain and rec.Pieces.Body then
		local body = rec.Pieces.Body.Part
		local light = own(rec, Instance.new("PointLight"))
		light.Name = "CrowdFx_Flash"
		light.Color = Color3.fromRGB(255, 236, 140)
		light.Brightness = 0
		light.Range = 14
		light.Shadows = false
		light.Parent = body
		rec.Light = light
		-- the lightning bolt: a zig-zag of two Beams over his cap (shown only during the flash)
		local bolt = own(rec, Instance.new("Folder"))
		bolt.Name = "CrowdFx_Bolt"
		local pts = { Vector3.new(-0.3, 7.2, -0.3), Vector3.new(0.5, 5.6, -0.4), Vector3.new(-0.1, 4.2, -0.5) }
		local atts = {}
		for i, p in ipairs(pts) do
			local a = Instance.new("Attachment")
			a.Name = "BoltA" .. i
			a.CFrame = rec.Pieces.Body.Off * CFrame.new(p)
			a.Parent = body
			atts[i] = own(rec, a)
		end
		for i = 1, 2 do
			local b = Instance.new("Beam")
			b.Name = "Bolt" .. i
			b.Attachment0 = atts[i]
			b.Attachment1 = atts[i + 1]
			b.Width0 = 0.55
			b.Width1 = 0.4
			b.Color = ColorSequence.new(Color3.fromRGB(255, 232, 90))
			b.LightEmission = 1
			b.FaceCamera = true
			b.Segments = 1
			b.Parent = bolt
		end
		rec.Bolt = bolt
	end
end

-- Config.Audio.Crowd and the Sfx setting are read once per REFRESH (refresh() -> readAudio), never per sound; no
-- WaitForChild here (it runs inside Heartbeat): a missing module just means "no ids / full volume" until the next read
local function audioIds()
	local ok, Config = pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local mod = shared and shared:FindFirstChild("Config")
		return mod and require(mod) or nil
	end)
	local audio = ok and type(Config) == "table" and Config.Audio
	local crowd = type(audio) == "table" and audio.Crowd
	return type(crowd) == "table" and crowd or {}
end

local function sfxVolume()
	local ok, ClientSettings = pcall(function()
		local client = script.Parent and script.Parent.Parent
		local mod = client and client:FindFirstChild("ClientSettings")
		return mod and require(mod) or nil
	end)
	if ok and type(ClientSettings) == "table" and type(ClientSettings.Get) == "function" then
		local v = tonumber(ClientSettings.Get("Sfx"))
		if v then
			return max(0, min(1, v / 10))
		end
	end
	return 1
end

local function readAudio()
	St.Audio = audioIds()
	St.Sfx = sfxVolume()
end

-- plays `name` from `part` (a 3D Sound, made once per part + name) when Config.Audio.Crowd[name] holds an id
local function play(part, name, volume, speed, looped)
	if not St.Audio then
		readAudio()
	end
	local id = St.Audio[name]
	if type(id) ~= "string" or id == "" or not part or not part.Parent then
		return nil
	end
	local s = St.Sounds[part] and St.Sounds[part][name]
	if not s or not s.Parent then
		s = Instance.new("Sound")
		s.Name = "Crowd_" .. name
		s.SoundId = id
		s.RollOffMaxDistance = K.SOUND_RANGE
		s.RollOffMinDistance = 12
		s.Looped = looped == true
		s.Parent = part
		St.Sounds[part] = St.Sounds[part] or {}
		St.Sounds[part][name] = s
	end
	s.Volume = (volume or K.VOICE) * (St.Sfx or 1)
	s.PlaybackSpeed = speed or 1
	pcall(function()
		s:Play()
	end)
	return s
end

local function bodyPart(rec)
	return rec.Pieces.Body and rec.Pieces.Body.Part
end

local function cueSounds(name)
	for _, rec in pairs(St.Specs) do
		if rec.On then
			local body = bodyPart(rec)
			if name == "Hit" then
				play(body, "Ooh", K.VOICE, rec.Pitch)
				if rec.Captain then
					play(body, "Thunder", 0.6, 1)
				end
			elseif name == "Won" then
				play(body, "Applause", K.VOICE, rec.Pitch)
				if rec.Drummer then
					play(body, "Drum", 0.4, 1.15)
				end
			elseif name == "Lost" then
				play(body, "Aww", K.VOICE, rec.Pitch)
			elseif name == "Boss" then
				if rec.Captain then
					play(body, "Thunder", 0.7, 0.8)
				end
				if rec.Drummer then
					play(body, "DrumRoll", 0.5, 1)
				end
			end
		end
	end
	if name == "Won" then
		for _, ex in pairs(St.Extras) do
			if ex.Kind == "Bell" and ex.On then
				play(ex.Part, "Bell", 0.55, 1)
			end
		end
	end
end

----------------------------------------------------------------------
-- Cues and the battle hooks
----------------------------------------------------------------------
function RingCrowdFx.Cue(name)
	if name == "Boss" then
		St.Boss = true
		cueSounds("Boss")
		return
	end
	if name == "BossEnd" then
		St.Boss = false
		return
	end
	if name ~= "Hit" and name ~= "Won" and name ~= "Lost" then
		return
	end
	St.Cue = { Name = name, T0 = St.Time }
	cueSounds(name)
end

local function isRing(payload)
	return type(payload) == "table" and tostring(payload.Mode) == "Ring"
end

function RingCrowdFx.HandleState(kind, payload, battleId)
	if type(payload) ~= "table" and kind ~= "Events" then
		return
	end
	if kind == "Start" then
		if not isRing(payload) then
			return
		end
		St.Battle = { Id = payload.BattleId or battleId, Hits = 0, Sum = 0, LastCue = -math.huge }
		local ring = type(payload.Ring) == "table" and payload.Ring or {}
		local champ = type(ring.Champion) == "table" and ring.Champion or {}
		if champ.Boss == true then
			RingCrowdFx.Cue("Boss")
		else
			RingCrowdFx.Cue("BossEnd")
		end
	elseif kind == "Events" then
		local b = St.Battle
		if not b or type(payload) ~= "table" then
			return
		end
		if battleId ~= nil and b.Id ~= nil and battleId ~= b.Id then
			return
		end
		local big = false
		for _, ev in ipairs(payload) do
			if type(ev) == "table" then
				if ev.type == "KO" or ev.type == "Special" then
					big = true
				elseif ev.type == "Hit" and not ev.miss and tonumber(ev.dmg) then
					local dmg = tonumber(ev.dmg)
					if b.Hits >= K.BIG_MIN_HITS and dmg >= K.BIG_HIT * (b.Sum / b.Hits) then
						big = true
					end
					b.Hits = b.Hits + 1
					b.Sum = b.Sum + dmg
				end
			end
		end
		if big and St.Time - b.LastCue >= K.CUE_GAP then
			b.LastCue = St.Time
			RingCrowdFx.Cue("Hit")
		end
	elseif kind == "End" then
		local b = St.Battle
		local id = payload.BattleId or battleId
		if not b or (id ~= nil and b.Id ~= nil and id ~= b.Id) then
			return
		end
		if payload.Spectator ~= true then
			local rw = type(payload.Rewards) == "table" and payload.Rewards or {}
			local won = payload.Won == true or payload.Outcome == "Win" or rw.Won == true
			RingCrowdFx.Cue(won and "Won" or "Lost")
		end
		RingCrowdFx.Cue("BossEnd")
		St.Battle = nil
	end
end

----------------------------------------------------------------------
-- The frame
----------------------------------------------------------------------
local function refresh()
	St.Quality = quality()
	readAudio()
	-- a spectator whose tag arrived before its Body replicated was skipped by track(): pick it up now
	if St.Started then
		for _, model in ipairs(CollectionService:GetTagged(K.TAG)) do
			if not St.Specs[model] then
				track(model)
			end
		end
	end
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for model, rec in pairs(St.Specs) do
		local body = rec.Pieces.Body
		local near = camPos == nil or (body.Pivot.Position - camPos).Magnitude <= K.RANGE
		local on = near and model.Parent ~= nil and body.Part.Parent ~= nil
		if not on then
			restRec(rec)
		else
			ensureClientBits(rec)
			if not rec.Moving then
				for _, p in pairs(rec.Pieces) do
					collectKids(p)
				end
			end
		end
		rec.On = on
		local wet = on and St.Quality ~= "Low"
		if rec.Weather then
			rec.Weather.Enabled = wet
		end
	end
	for part, ex in pairs(St.Extras) do
		local near = camPos == nil or (ex.Pivot.Position - camPos).Magnitude <= K.RANGE
		local on = near and part.Parent ~= nil
		if not on and ex.Moving then
			restPiece(ex)
			ex.Moving = false
		end
		ex.On = on
		-- the wind + rigging-creak loop rides the flag line while the stand is near (only with an id)
		if ex.Kind == "Flags" then
			if on and not ex.Ambient then
				ex.Ambient = play(part, "Ambient", 0.3, 1, true)
			elseif not on and ex.Ambient then
				ex.Ambient:Stop()
				ex.Ambient = nil
			end
		end
	end
end

local function stepRec(rec, t, cueName, cueT)
	local pose = RingCrowdFx.Pose(rec, t, cueName, cueT, St.BossFade, rec.PoseBuf)
	rec.PoseBuf = pose
	local seat = rec.Seat * CFrame.new(0, pose.Lift, 0) * CFrame.Angles(pose.Lean, 0, pose.Roll)
	local P = rec.Pieces
	placePiece(P.Body, seat)
	for _, side in ipairs(SIDES) do
		local p = P[side]
		if p then
			local kind = p.Kind
			local rot
			if kind == "arena_crowd_stick" then
				rot = CFrame.Angles((p.Sgn < 0) and pose.StickL or pose.StickR, 0, 0)
			elseif kind == "arena_crowd_spyglass" then
				rot = CFrame.Angles(pose.Glass, 0, 0)
			else
				rot = CFrame.Angles(0, 0, p.Sgn * pose[side])
			end
			placePiece(p, seat * p.Local * rot)
		end
	end
	if P.Cap then
		placePiece(P.Cap, seat * P.Cap.Local * CFrame.new(0, pose.CapUp, 0) * CFrame.Angles(0, pose.CapSpin, 0))
	end
	if P.Drum then
		placePiece(P.Drum, seat * P.Drum.Local * CFrame.new(0, pose.DrumDip, 0)) -- dips under each stroke
	end
	if rec.Light then
		rec.Light.Brightness = 4 * pose.Flash
	end
	if rec.Bolt then
		rec.Bolt.Parent = (pose.Flash > 0.05) and bodyPart(rec) or nil
	end
	local dark = K.BOSS_DARK * St.BossFade
	if dark > 0 or rec.Dark then
		applyDark(rec, dark)
	end
	if rec.Drizzle then
		rec.Drizzle.Enabled = St.BossFade > 0.5 and St.Quality ~= "Low"
	end
	rec.Moving = true
	return pose
end

function RingCrowdFx.Step(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	St.Time = St.Time + dt
	St.BossFade = St.Boss and min(1, St.BossFade + dt) or max(0, St.BossFade - dt)
	St.RefreshAcc = St.RefreshAcc + dt
	if St.RefreshAcc >= K.REFRESH then
		St.RefreshAcc = 0
		refresh()
	end
	St.Acc = St.Acc + dt
	local hz = (St.Quality == "Low") and K.LOW_HZ or K.UPDATE_HZ
	if St.Acc < 1 / hz then
		return
	end
	St.Acc = 0
	local t = St.Time
	local cueName, cueT = nil, nil
	if St.Cue then
		cueName, cueT = St.Cue.Name, t - St.Cue.T0
		if cueT > K.WON_TIME + 0.5 then
			St.Cue = nil
			cueName, cueT = nil, nil
		end
	end
	local beat = floor(t * K.BPM / 60)
	local drumHit = beat ~= St.LastBeat
	if drumHit then
		St.LastBeat = beat
		St.Beats = St.Beats + 1
	end
	local bell = 0
	for _, rec in pairs(St.Specs) do
		if rec.On then
			local pose = stepRec(rec, t, cueName, cueT)
			bell = pose.BellSwing
			-- the drum tap keeps time only while a ring fight is on (not between rounds or over the result card)
			if drumHit and rec.Drummer and St.Battle ~= nil and not St.Boss and cueName == nil then
				play(bodyPart(rec), "Drum", 0.12, 1)
			end
		end
	end
	for _, ex in pairs(St.Extras) do
		if ex.On and ex.Part.Parent then
			if ex.Kind == "Flags" then
				local gust = St.Boss and 1.8 or 1
				local a = K.FLAG_SWING * gust * (0.65 * sin(TWO_PI * t / 3.1) + 0.35 * sin(TWO_PI * t / 1.7 + 1))
				placePiece(ex, ex.Pivot * CFrame.Angles(a, 0, 0))
			else
				placePiece(ex, ex.Pivot * CFrame.Angles(bell, 0, bell * 0.3))
			end
			ex.Moving = true
		end
	end
end

function RingCrowdFx.Stats()
	local moving = 0
	for _, rec in pairs(St.Specs) do
		if rec.Moving then
			moving = moving + 1
		end
	end
	local sounds = 0
	for _, list in pairs(St.Sounds) do
		for _ in pairs(list) do
			sounds = sounds + 1
		end
	end
	return { Spectators = St.Count, Moving = moving, Writes = St.Writes, Beats = St.Beats,
		Cue = St.Cue and St.Cue.Name or nil, Boss = St.Boss, Quality = St.Quality, Sounds = sounds, Emitters = St.Emitters }
end

function RingCrowdFx.Stop()
	for _, c in ipairs(St.Conns) do
		c:Disconnect()
	end
	St.Conns = {}
	local models = {}
	for model in pairs(St.Specs) do
		models[#models + 1] = model
	end
	for _, model in ipairs(models) do
		local rec = St.Specs[model]
		if rec then
			rec.Moving = true -- force the rest write
		end
		forget(model)
	end
	for part, ex in pairs(St.Extras) do
		restPiece(ex)
		St.Extras[part] = nil
	end
	for _, list in pairs(St.Sounds) do
		for _, s in pairs(list) do
			s:Destroy()
		end
	end
	St.Sounds = {}
	St.Audio = nil
	St.Count = 0
	St.Emitters = 0
	St.Cue = nil
	St.Boss = false
	St.BossFade = 0
	St.Battle = nil
	St.Started = false
end

function RingCrowdFx.Init()
	if St.Started then
		return
	end
	St.Started = true
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceAddedSignal(K.TAG):Connect(track)
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceRemovedSignal(K.TAG):Connect(forget)
	for _, model in ipairs(CollectionService:GetTagged(K.TAG)) do
		track(model)
	end
	St.Conns[#St.Conns + 1] = RunService.Heartbeat:Connect(RingCrowdFx.Step)
	refresh()
	-- the battle flow (the same remote BattleController draws from; BattleState may arrive a little later)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
		local remote = folder and folder:WaitForChild("BattleState", 30)
		if not remote or not St.Started then
			return
		end
		St.Conns[#St.Conns + 1] = remote.OnClientEvent:Connect(function(kind, payload, battleId)
			pcall(RingCrowdFx.HandleState, kind, payload, battleId)
		end)
	end)
end

return RingCrowdFx
