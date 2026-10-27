-- FountainFx (client, bug #13 "Sky-Oasis Steps"): the lobby fountain's small life that Beams and emitters cannot do.
-- The water itself animates on its own (LobbyBuilder buildFountain: Beams with TextureSpeed for the falls, emitters for
-- the splashes, ripple rings, mist and the spring's bubbles). This controller only:
--   * floats the paper boat: a slow drift round its rest point, a bob on the water, a little yaw and roll. The boat is
--     one anchored root Part tagged "OasisBoat" with its anchored parts under it (the sail: every lobby part stays
--     Anchored, so nothing can fall or be pushed). Each tick writes the root and every anchored BasePart under it at
--     its stored rest offset (two CFrame writes for the Part boat); once prop_oasis_boat is uploaded the Blender mesh
--     is welded to the root (ML_Weld, unanchored, client-side) and simply rides it. Here on this client only;
--   * plays the fountain's water loop when Config.Audio.Ambient.Fountain holds a sound id (empty = silent, today).
-- Cheap: ONE Heartbeat connection, updates at UPDATE_HZ, only boats within RANGE studs of the camera move, and a boat
-- returns to its rest CFrame when it goes out of range, on Low graphics or on Stop(). Streaming-safe: boats are found by
-- tag as they arrive and forgotten when they leave.
--
--   FountainFx.Init()            idempotent (Main.client.lua starts it)
--   FountainFx.Stop()            disconnects everything, every boat back at rest
--   FountainFx.Step(dt)          one Heartbeat step (tests drive it)
--   FountainFx.Offset(t, phase) -> CFrame   the boat's offset from rest at time t (pure; tests)
--   FountainFx.Stats() -> { Boats, Moving, Writes, Time, Quality, Sound }
--   FountainFx.K                 the tuning numbers
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FountainFx = {}

local K = {
	BOAT_TAG = "OasisBoat",
	FALLS_TAG = "OasisFalls",
	RANGE = 140, -- studs from the camera: farther boats rest
	UPDATE_HZ = 30,
	REFRESH = 0.5, -- seconds between quality / range passes
	DRIFT = 0.45, -- studs: the radius of the slow circle the boat drifts on
	DRIFT_PERIOD = 18, -- seconds per circle
	BOB = 0.06, -- studs up / down
	BOB_PERIOD = 2.4,
	YAW = 0.14, -- radians of slow swing
	ROLL = 0.05, -- radians of rocking
	SOUND_VOLUME = 0.45, -- x the player's Sfx setting
	SOUND_RANGE = 70,
}
FountainFx.K = K

local TWO_PI = math.pi * 2

local St = {
	Started = false,
	Boats = {}, -- [part] = { Part, Rest, Phase, Moving }
	Count = 0,
	Conns = {},
	Time = 0,
	Acc = 0,
	RefreshAcc = 0,
	Quality = "High",
	Quality0 = nil,
	Writes = 0,
	Sound = nil,
}
FountainFx._St = St

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

-- The boat's offset from its rest frame at time t (a slow circle, a bob, a swing and a rock; `phase` 0..1 spreads boats).
function FountainFx.Offset(t, phase)
	phase = phase or 0
	local a = TWO_PI * (t / K.DRIFT_PERIOD + phase)
	local b = TWO_PI * (t / K.BOB_PERIOD + phase * 3)
	return CFrame.new(math.cos(a) * K.DRIFT, math.sin(b) * K.BOB, math.sin(a) * K.DRIFT)
		* CFrame.Angles(math.sin(b + 1.1) * K.ROLL, math.sin(a * 2) * K.YAW, 0)
end

-- the anchored parts under the root (the sail) and their offsets from its rest frame. A part not yet seen has never
-- been moved by this client, so its CFrame is its rest. Unanchored ones (the ML_Weld mesh) ride the root by weld.
local function collectKids(rec)
	for _, d in ipairs(rec.Part:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored and not rec.Seen[d] then
			rec.Seen[d] = true
			rec.Kids[#rec.Kids + 1] = { Part = d, Offset = rec.Rest:ToObjectSpace(d.CFrame) }
		end
	end
end

local function place(rec, cf)
	rec.Part.CFrame = cf
	St.Writes = St.Writes + 1
	for _, k in ipairs(rec.Kids) do
		if k.Part.Parent then
			k.Part.CFrame = cf * k.Offset
			St.Writes = St.Writes + 1
		end
	end
end

local function rest(rec)
	if rec.Moving and rec.Part.Parent then
		place(rec, rec.Rest)
	end
	rec.Moving = false
end

local function track(part)
	if not part:IsA("BasePart") or St.Boats[part] then
		return
	end
	local rec = { Part = part, Rest = part.CFrame, Phase = (St.Count * 0.37) % 1, Moving = false, Kids = {}, Seen = {} }
	collectKids(rec)
	St.Boats[part] = rec
	St.Count = St.Count + 1
end

local function forget(part)
	local rec = St.Boats[part]
	if rec then
		rest(rec)
		St.Boats[part] = nil
		St.Count = St.Count - 1
	end
end

local function soundId()
	local ok, Config = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
	end)
	local audio = ok and type(Config) == "table" and Config.Audio
	local ambient = type(audio) == "table" and audio.Ambient
	local id = type(ambient) == "table" and ambient.Fountain
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- the water loop on the falls' anchor (only when an id is configured)
local function attachSound(anchor)
	if St.Sound or not anchor:IsA("BasePart") then
		return
	end
	local id = soundId()
	if not id then
		return
	end
	local volume = K.SOUND_VOLUME
	local okSettings, ClientSettings = pcall(function()
		return require(script.Parent.Parent:WaitForChild("ClientSettings", 5))
	end)
	if okSettings and type(ClientSettings) == "table" and type(ClientSettings.Get) == "function" then
		local v = tonumber(ClientSettings.Get("Sfx"))
		if v then
			volume = volume * math.max(0, math.min(1, v / 10))
		end
	end
	local s = Instance.new("Sound")
	s.Name = "FountainWater"
	s.SoundId = id
	s.Looped = true
	s.Volume = volume
	s.RollOffMaxDistance = K.SOUND_RANGE
	s.RollOffMinDistance = 10
	s.Parent = anchor
	pcall(function()
		s:Play()
	end)
	St.Sound = s
end

local function refresh()
	St.Quality = quality()
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for _, rec in pairs(St.Boats) do
		local near = camPos == nil or (rec.Rest.Position - camPos).Magnitude <= K.RANGE
		local on = near and St.Quality ~= "Low" and rec.Part.Parent ~= nil
		if not on then
			rest(rec)
		elseif not rec.Moving then
			collectKids(rec) -- parts that streamed in late (picked up while the boat is at rest)
		end
		rec.On = on
	end
end

function FountainFx.Step(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	St.Time = St.Time + dt
	St.RefreshAcc = St.RefreshAcc + dt
	if St.RefreshAcc >= K.REFRESH then
		St.RefreshAcc = 0
		refresh()
	end
	St.Acc = St.Acc + dt
	if St.Acc < 1 / K.UPDATE_HZ then
		return
	end
	St.Acc = 0
	for _, rec in pairs(St.Boats) do
		if rec.On and rec.Part.Parent then
			place(rec, rec.Rest * FountainFx.Offset(St.Time, rec.Phase))
			rec.Moving = true
		end
	end
end

function FountainFx.Stats()
	local moving = 0
	for _, rec in pairs(St.Boats) do
		if rec.Moving then
			moving = moving + 1
		end
	end
	return { Boats = St.Count, Moving = moving, Writes = St.Writes, Time = St.Time, Quality = St.Quality,
		Sound = St.Sound ~= nil }
end

function FountainFx.Stop()
	for _, c in ipairs(St.Conns) do
		c:Disconnect()
	end
	St.Conns = {}
	local parts = {}
	for part in pairs(St.Boats) do
		parts[#parts + 1] = part
	end
	for _, part in ipairs(parts) do
		forget(part)
	end
	if St.Sound then
		St.Sound:Destroy()
		St.Sound = nil
	end
	St.Started = false
end

function FountainFx.Init()
	if St.Started then
		return
	end
	St.Started = true
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceAddedSignal(K.BOAT_TAG):Connect(track)
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceRemovedSignal(K.BOAT_TAG):Connect(forget)
	for _, part in ipairs(CollectionService:GetTagged(K.BOAT_TAG)) do
		track(part)
	end
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceAddedSignal(K.FALLS_TAG):Connect(attachSound)
	for _, anchor in ipairs(CollectionService:GetTagged(K.FALLS_TAG)) do
		attachSound(anchor)
	end
	St.Conns[#St.Conns + 1] = RunService.Heartbeat:Connect(FountainFx.Step)
	refresh()
end

return FountainFx
