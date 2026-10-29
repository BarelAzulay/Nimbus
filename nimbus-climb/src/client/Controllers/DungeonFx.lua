-- DungeonFx (client, bug #5 "dungeon rooms"): the dungeon's small motion that Beams and emitters cannot do.
--   * the Weatherworks' weather astrolabe (the boss room's chair, style b): three brass gimbal rings round a captured
--     storm cloud turn slowly. Each ring is one anchored Part tagged "NC_DungeonSpin" (DungeonBuilder, attributes
--     SpinSpeed in rad/s and SpinIndex); this client turns it about its own local Y from its rest frame. Once
--     dungeon_b_ring is uploaded the Blender mesh is welded to the ring Part (ML_Weld, unanchored, client-side) and
--     simply rides it. Here on this client only: the server's Parts never move.
-- Cheap: ONE Heartbeat connection, updates at UPDATE_HZ, only rings within RANGE studs of the camera turn, and a ring
-- goes back to rest out of range, on Low graphics or on Stop(). Streaming-safe: rings are found by tag as they arrive
-- and forgotten when they leave. No sound here (the audio branch reads the CollectionService tags).
--
--   DungeonFx.Init()            idempotent (Main.client.lua starts it)
--   DungeonFx.Stop()            disconnects everything, every ring back at rest
--   DungeonFx.Step(dt)          one Heartbeat step (tests drive it)
--   DungeonFx.Angle(t, speed, index) -> number   a ring's turn at time t (pure; tests)
--   DungeonFx.Stats() -> { Rings, Moving, Writes, Time, Quality }
--   DungeonFx.K                 the tuning numbers
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DungeonFx = {}

local K = {
	SPIN_TAG = "NC_DungeonSpin",
	RANGE = 160, -- studs from the camera: farther rings rest
	UPDATE_HZ = 30,
	REFRESH = 0.5, -- seconds between quality / range passes
	DEFAULT_SPEED = 0.4, -- rad/s when a ring carries no SpinSpeed
}
DungeonFx.K = K

local St = {
	Started = false,
	Rings = {}, -- [part] = { Part, Rest, Speed, Index, Moving }
	Count = 0,
	Conns = {},
	Time = 0,
	Acc = 0,
	RefreshAcc = 0,
	Quality = "High",
	Quality0 = nil,
	Writes = 0,
}
DungeonFx._St = St

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

-- a ring's turn (radians) at time t: its own speed, each ring started a third of a turn apart
function DungeonFx.Angle(t, speed, index)
	return (t * (speed or K.DEFAULT_SPEED)) + ((index or 1) - 1) * (math.pi * 2 / 3)
end

local function rest(rec)
	if rec.Moving and rec.Part.Parent then
		rec.Part.CFrame = rec.Rest
		St.Writes = St.Writes + 1
	end
	rec.Moving = false
end

local function add(part)
	if not part:IsA("BasePart") or St.Rings[part] then
		return
	end
	St.Rings[part] = {
		Part = part,
		Rest = part.CFrame,
		Speed = tonumber(part:GetAttribute("SpinSpeed")) or K.DEFAULT_SPEED,
		Index = tonumber(part:GetAttribute("SpinIndex")) or 1,
		Moving = false,
	}
	St.Count = St.Count + 1
end

local function remove(part)
	local rec = St.Rings[part]
	if rec then
		St.Rings[part] = nil
		St.Count = St.Count - 1
	end
end

local function cameraPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

function DungeonFx.Step(dt)
	dt = tonumber(dt) or 0
	St.Time = St.Time + dt
	St.RefreshAcc = St.RefreshAcc + dt
	if St.RefreshAcc >= K.REFRESH then
		St.RefreshAcc = 0
		St.Quality = quality()
		local from = cameraPos()
		for part, rec in pairs(St.Rings) do
			if not part.Parent then
				remove(part)
			else
				local near = St.Quality ~= "Low" and from ~= nil and (rec.Rest.Position - from).Magnitude <= K.RANGE
				if near then
					rec.Moving = true
				else
					rest(rec)
				end
			end
		end
	end
	St.Acc = St.Acc + dt
	if St.Acc < 1 / K.UPDATE_HZ then
		return
	end
	St.Acc = 0
	for part, rec in pairs(St.Rings) do
		if rec.Moving and part.Parent then
			part.CFrame = rec.Rest * CFrame.Angles(0, DungeonFx.Angle(St.Time, rec.Speed, rec.Index), 0)
			St.Writes = St.Writes + 1
		end
	end
end

function DungeonFx.Stats()
	local moving = 0
	for _, rec in pairs(St.Rings) do
		if rec.Moving then
			moving = moving + 1
		end
	end
	return { Rings = St.Count, Moving = moving, Writes = St.Writes, Time = St.Time, Quality = St.Quality }
end

function DungeonFx.Init()
	if St.Started then
		return
	end
	St.Started = true
	for _, part in ipairs(CollectionService:GetTagged(K.SPIN_TAG)) do
		add(part)
	end
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceAddedSignal(K.SPIN_TAG):Connect(add)
	St.Conns[#St.Conns + 1] = CollectionService:GetInstanceRemovedSignal(K.SPIN_TAG):Connect(function(part)
		local rec = St.Rings[part]
		if rec then
			rest(rec)
		end
		remove(part)
	end)
	St.RefreshAcc = K.REFRESH -- the first step decides range / quality at once
	St.Conns[#St.Conns + 1] = RunService.Heartbeat:Connect(function(dt)
		DungeonFx.Step(dt)
	end)
end

function DungeonFx.Stop()
	for _, c in ipairs(St.Conns) do
		c:Disconnect()
	end
	St.Conns = {}
	for _, rec in pairs(St.Rings) do
		rest(rec)
	end
	St.Rings = {}
	St.Count = 0
	St.Started = false
end

return DungeonFx
