-- LobbyFxController (client, lobby shop 2026-11-07, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.12 / 5.9 /
-- 16.5; plan Task 25): ONE Heartbeat for all lobby motion. The server builds and tags; only this client moves anything.
--   * Config.Tags.Spin (NC_Spin) on a Model or a Part: turns about its built pivot's Y, one turn in SpinSeconds, and bobs
--     BobStuds * sin(2 pi t / BobSeconds) from the built pivot (absolute each frame, never accumulating). Users: the world
--     gem (8 s, 0.6 / 3 s), the summon portal's GlowRing (6 s), the egg row's seven shelf eggs under the WINGED PETS board
--     (14 s, 0.12 / 3.2 s: a slow display turntable).
--   * Config.Tags.Bob (NC_Bob) on a BillboardGui: StudsOffset.Y = its built value + the same bob (the trove's Join sign,
--     0.5 / 2.4 s); on a Model or a Part: the bob alone.
--   * Every JoinBillboard (the trove's Join sign, found through its NC_Bob tag) has Enabled = false while
--     LocalPlayer:GetAttribute(Config.Attr.TroveGroupDone) == true, true otherwise, a sign built after a rebuild included.
-- Rules: only targets within RANGE studs of the camera move (a moving one rests only past RANGE_OUT: no flicker at the
-- edge); Low graphics (GraphicsQuality.Effective(), the read PortalFxController uses) = nothing moves. A target that stops
-- (out of range, Low, untagged, parked outside the workspace) is put back exactly at its built pivot / offset. The turn starts
-- from the built pose each time a target starts moving; the bob carries a small phase per target (from its built spot), so
-- the shelf eggs do not bob in lockstep.
-- How a Model / Part moves: each of its BaseParts is written absolutely as pose * (its offset), offsets taken against the
-- built pivot for parts the server built (they replicate at their built place, also when they stream in late) and against
-- the pose of the moment for a part inside an ML_Mesh (MeshLibrary.Dress builds it on this client at the target's current
-- pivot). A Model without a PrimaryPart gets its WorldPivot written too, so GetPivot() (and a mesh dressed mid-turn) follows.
-- Cheap: one Heartbeat, a pass every REFRESH s picks the near targets and re-reads attributes and the quality, no table
-- or closure made per frame; targets are found by CollectionService tags (added / removed signals: streaming and
-- rebuilds), each record drops its own connections when its target goes.
--
--   LobbyFxController.Init()            idempotent (Main.client.lua starts it)
--   LobbyFxController.Step(dt)          one frame (the Heartbeat handler; tests call it by hand)
--   LobbyFxController.Moving() -> { inst... }  the targets moved on the last step (a copy)
--   LobbyFxController.K                 the tuning numbers
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LobbyFx = {}

local K = {
	RANGE = 150, -- studs from the camera: farther targets rest at their built pivot
	RANGE_OUT = 160, -- ... a moving target rests only past this
	REFRESH = 0.5, -- seconds between two passes (near targets, attributes, graphics quality, the Join signs)
	BOB_SECONDS = 3, -- a bob without BobSeconds
	JOIN = "JoinBillboard",
}
LobbyFx.K = K

local TAG = {
	Spin = (type(Config.Tags) == "table" and Config.Tags.Spin) or "NC_Spin",
	Bob = (type(Config.Tags) == "table" and Config.Tags.Bob) or "NC_Bob",
	Done = (type(Config.Attr) == "table" and Config.Attr.TroveGroupDone) or "TroveGroupDone",
	Mesh = "ML_Mesh",
}
local TWO_PI = math.pi * 2

local S = {
	Started = false,
	Recs = {}, -- [instance] = record
	Count = 0,
	Conns = {},
	Time = 0, -- accumulated Heartbeat time (deterministic in tests)
	RefreshAcc = 0,
	Low = false,
	Moving = {},
	Quality0 = nil, -- GraphicsQuality module (lazy; tests put a stub here)
}
LobbyFx._S = S

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function quality()
	if S.Quality0 == nil then
		S.Quality0 = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" and type(mod.Effective) == "function" then
				S.Quality0 = mod
			end
		end
	end
	if S.Quality0 then
		local ok, mode = pcall(S.Quality0.Effective)
		if ok and (mode == "Low" or mode == "High") then
			return mode
		end
	end
	return "High"
end

local function positive(inst, name)
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v > 0 and v == v then
		return v
	end
	return nil
end

-- where a target stands (the distance to the camera): a pose target's built pivot, a sign's adornee / parent
local function spotOf(rec)
	if not rec.Gui then
		return rec.Base.Position
	end
	local host = rec.Inst.Adornee or rec.Inst.Parent
	if host and host:IsA("BasePart") then
		return host.Position
	elseif host and host:IsA("Attachment") then
		return host.WorldPosition
	elseif host and host:IsA("Model") then
		return host:GetPivot().Position
	end
	return nil
end

-- a part joins a pose target: its offset against `from` (the built pivot, or the pose of the moment for a mesh part)
local function addPart(rec, part)
	if part:IsA("BasePart") then
		local from = part:FindFirstAncestor(TAG.Mesh) and rec.Cur or rec.Base
		rec.Parts[part] = from:Inverse() * part.CFrame
	end
end

-- writes a pose target at `pose` (its parts, and the WorldPivot of a Model without a PrimaryPart)
local function place(rec, pose)
	for part, rel in pairs(rec.Parts) do
		if part.Parent then
			part.CFrame = pose * rel
		end
	end
	if rec.Model and not rec.Inst.PrimaryPart then
		rec.Inst.WorldPivot = pose
	end
	rec.Cur = pose
end

-- back to the built pivot / offset (once)
local function rest(rec)
	if not rec.Moved then
		return
	end
	rec.Moved = false
	if rec.Gui then
		rec.Inst.StudsOffset = rec.Base
	else
		place(rec, rec.Base)
	end
end

local function joinDone()
	local lp = Players.LocalPlayer
	return lp ~= nil and lp:GetAttribute(TAG.Done) == true
end

local function applyJoin(rec, done)
	if rec.Join and rec.Inst.Enabled == done then
		rec.Inst.Enabled = not done
	end
end

local function applyJoins()
	local done = joinDone()
	for _, rec in pairs(S.Recs) do
		applyJoin(rec, done)
	end
end

-- re-reads a record's attributes (they may replicate after the tag) and which tags it has
local function readAttrs(rec)
	local inst = rec.Inst
	rec.Spin = (not rec.Gui and CollectionService:HasTag(inst, TAG.Spin)) and positive(inst, "SpinSeconds") or nil
	rec.Bob = positive(inst, "BobStuds") or 0
	rec.BobT = positive(inst, "BobSeconds") or K.BOB_SECONDS
end

local function untrack(inst)
	local rec = S.Recs[inst]
	if not rec then
		return
	end
	S.Recs[inst] = nil
	S.Count = S.Count - 1
	for _, c in ipairs(rec.Conns) do
		c:Disconnect()
	end
	if inst:IsDescendantOf(game) then
		rest(rec)
	end
end

-- any tagged instance in the game is recorded, but only one in the workspace ever moves: GraphicsQuality's Low parks
-- NC_Detail decor in ReplicatedStorage and puts it back on High without a tag signal, so a parked target keeps its
-- record (rested) and moves again once it is back
local function track(inst)
	if S.Recs[inst] or not inst:IsDescendantOf(game) then
		return
	end
	local rec = { Inst = inst, Conns = {}, Moved = false, Near = false, T0 = 0 }
	if inst:IsA("BillboardGui") then
		rec.Gui = true
		rec.Base = inst.StudsOffset
		rec.Join = inst.Name == K.JOIN
	elseif inst:IsA("BasePart") or inst:IsA("Model") then
		rec.Model = inst:IsA("Model")
		rec.Base = inst:GetPivot()
		rec.Cur = rec.Base
		rec.Parts = {}
		addPart(rec, inst)
		for _, d in ipairs(inst:GetDescendants()) do
			addPart(rec, d)
		end
		rec.Conns[1] = inst.DescendantAdded:Connect(function(d)
			addPart(rec, d)
		end)
		rec.Conns[2] = inst.DescendantRemoving:Connect(function(d)
			rec.Parts[d] = nil
		end)
	else
		return
	end
	local spot = spotOf(rec)
	-- a phase for the bob from the built spot (0..1 of a period), so neighbours do not bob in lockstep
	rec.Phase = spot and (math.sin(spot.X * 12.9898 + spot.Z * 78.233) * 43758.5453) % 1 or 0
	readAttrs(rec)
	S.Recs[inst] = rec
	S.Count = S.Count + 1
	applyJoin(rec, joinDone())
end

-- a tag went (or its instance left the game): keep it while it is in the game with one of the two tags
local function onRemoved(inst)
	if inst:IsDescendantOf(game) and (CollectionService:HasTag(inst, TAG.Spin) or CollectionService:HasTag(inst, TAG.Bob)) then
		return
	end
	untrack(inst)
end

----------------------------------------------------------------------
-- the loop
----------------------------------------------------------------------

-- picks the near targets, re-reads attributes and the quality, drops targets that left the game, re-applies the Join signs
local function refresh()
	S.Low = quality() == "Low"
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position
	for inst, rec in pairs(S.Recs) do
		if not inst:IsDescendantOf(game) then
			untrack(inst)
		else
			readAttrs(rec)
			local spot = inst:IsDescendantOf(Workspace) and spotOf(rec) or nil
			local near = false
			if eye and spot and not S.Low and (rec.Spin or rec.Bob > 0) then
				near = (spot - eye).Magnitude <= (rec.Near and K.RANGE_OUT or K.RANGE)
			end
			if near and not rec.Near then
				rec.T0 = S.Time -- the turn starts from the built pose
			elseif not near then
				rest(rec)
			end
			rec.Near = near
		end
	end
	applyJoins()
end

function LobbyFx.Step(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	S.Time = S.Time + dt
	S.RefreshAcc = S.RefreshAcc + dt
	if S.RefreshAcc >= K.REFRESH then
		S.RefreshAcc = 0
		refresh()
	end
	local moving = S.Moving
	for i = #moving, 1, -1 do
		moving[i] = nil
	end
	if S.Low then
		return
	end
	for inst, rec in pairs(S.Recs) do
		if rec.Near and inst.Parent then
			local t = S.Time - rec.T0
			local bob = rec.Bob > 0 and rec.Bob * math.sin(TWO_PI * (t / rec.BobT + rec.Phase)) or 0
			if rec.Gui then
				local b = rec.Base
				inst.StudsOffset = Vector3.new(b.X, b.Y + bob, b.Z)
			else
				local pose = rec.Base
				if rec.Spin then
					pose = pose * CFrame.Angles(0, TWO_PI * t / rec.Spin, 0)
				end
				place(rec, pose + Vector3.new(0, bob, 0))
			end
			rec.Moved = true
			moving[#moving + 1] = inst
		end
	end
end

function LobbyFx.Moving()
	local out = {}
	for i, inst in ipairs(S.Moving) do
		out[i] = inst
	end
	return out
end

function LobbyFx.Init()
	if S.Started then
		return
	end
	S.Started = true
	for _, tag in ipairs({ TAG.Spin, TAG.Bob }) do
		S.Conns[#S.Conns + 1] = CollectionService:GetInstanceAddedSignal(tag):Connect(track)
		S.Conns[#S.Conns + 1] = CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			track(inst)
		end
	end
	local lp = Players.LocalPlayer
	if lp then
		S.Conns[#S.Conns + 1] = lp:GetAttributeChangedSignal(TAG.Done):Connect(applyJoins)
	end
	S.Conns[#S.Conns + 1] = RunService.Heartbeat:Connect(LobbyFx.Step)
	refresh()
end

return LobbyFx
