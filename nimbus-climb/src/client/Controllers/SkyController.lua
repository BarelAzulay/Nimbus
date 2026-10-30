-- SkyController (client): the living sky on this client (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md,
-- plan docs/superpowers/plans/2026-10-30-living-sky.md Task 5). The server publishes the clock and the raid event as
-- Workspace attributes (server/Services/SkyService, Config.Sky.Attr); every Config.Sky.Cycle.Refresh (2) s this turns
-- them into the moment's look with shared/SkyCycle (+ shared/SkyFaces for the painted skybox) and moves the BASE of
-- client/LightingStack with a Cycle.Tween (2) s tween, so the Dungeon / GfxLow / AttackFxDim presets keep winning on
-- top. No per-frame code (one task.wait loop), no remote traffic.
--
--   * no SkyEpoch attribute (an older server, tests): inert, the boot sky stays, nothing below runs
--   * the first apply after Start is instant (seconds 0): a late joiner never sees the boot afternoon fade away
--   * a refresh is skipped while LightingStack.Busy() (a Dungeon / AttackFxDim fade runs: never restarted); the next
--     refresh after it applies
--   * the clock: ClockTime is set at once (LightingStack.SetBase's instant set) when it changes segment (a phase start,
--     a raid sky's mid-blend, the Night -> Dawn wrap) by more than Config.Sky.ClockJump h; inside a phase it tweens
--   * the raid sky: SkyEvent (a boss id with a RaidThemes sky) blends in over Cycle.EventBlend (3) s from SkyEventAt
--     (a late joiner mid-raid is on the raid sky at once) and back out over 3 s once SkyEvent is "" again
--   * the battle lift (Config.Sky.Lift): in an outdoor pet battle (Config.Attr.InBattle "B...") under a dark look
--     (Night, the eclipse raid) LightingStack.Push("SkyLift") over 1.5 s, popped over 1.5 s after the fight / at dawn
--   * the lamps (Config.Sky.Lamps): the lobby's LampGlass / LanternLight / StallLight / DomeGlow PointLights glow
--     x1.6 under a dark look; written on a look change only (a lamp streamed in later waits for the next change)
--   * the fireflies (Config.Sky.Fireflies): at Night on High graphics a few emitters round the lobby trees (one local
--     folder, capped); none on Low (GraphicsQuality.Effective()) or by day
--   * Low graphics: GraphicsQuality.Recap after each applied refresh (the GfxLow cloud cap follows the sky)
-- The "look" = the raid boss id from its eventBlend 0.5, else the next phase from the phase's Blend 0.5, else the phase
-- (the same moments the skybox swaps).
--
--   SkyController.Init() / Start()   idempotent: the loop, the attribute signals, a first (instant) refresh
--   SkyController.Stop()             tests: the loop ends, signals dropped, lift popped, lamps back, fireflies gone
--   SkyController.Refresh(now)       one step (tests drive it); now = server time (default Workspace:GetServerTimeNow())
--   SkyController.State() -> { Phase, Next, Look, Theme, Event, EventBlend, Lift, Lamps, Fireflies, Applies, Skipped,
--                              Loops, Running }   (Lamps / Fireflies = how many lights raised / emitters on)
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SkyCycle = require(Shared:WaitForChild("SkyCycle"))
local SkyFaces = require(Shared:WaitForChild("SkyFaces"))
local LightingStack = require(Client:WaitForChild("LightingStack"))

local SkyController = {}

local St = {
	Running = false,
	Gen = 0, -- the loop generation (Stop / Start: an older loop ends on its next wake)
	Loops = 0, -- loops alive (one at most)
	Thread = nil, -- the loop's thread (Stop cancels it)
	First = true, -- the next applied refresh is instant
	Conns = {},
	Phase = nil,
	Next = nil,
	Look = nil,
	Theme = nil,
	Event = nil,
	EventBlend = 0,
	LastEvent = nil, -- the raid sky blending out after SkyEvent went ""
	Seg = nil, -- the clock segment applied last (a phase name or a raid boss id)
	Clock = nil, -- the ClockTime applied last
	Lift = false,
	LampLook = nil, -- the look the lamps were written for
	LampBase = setmetatable({}, { __mode = "k" }), -- [PointLight] = its own Brightness (while raised)
	Lamps = 0,
	Fireflies = 0,
	FireflyFolder = nil,
	Applies = 0,
	Skipped = 0,
	GQ = nil, -- client/GraphicsQuality (lazy); false = unavailable
}
SkyController._St = St

local function cfg()
	return Config.Sky
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function graphics()
	if St.GQ == nil then
		local module = Client:FindFirstChild("GraphicsQuality")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		St.GQ = (ok and type(result) == "table") and result or false
	end
	return St.GQ or nil
end

local function lowGraphics()
	local GQ = graphics()
	if GQ and type(GQ.Effective) == "function" then
		local ok, mode = pcall(GQ.Effective)
		return ok and mode == "Low"
	end
	return false
end

-- the raid sky now: boss id (or nil) and its blend 0..1 (SkyEventAt-based, the same on every client)
local function eventNow(now)
	local sky = cfg()
	local id = Workspace:GetAttribute(sky.Attr.Event)
	local at = Workspace:GetAttribute(sky.Attr.EventAt)
	local x = 1
	if finite(at) then
		x = math.max(0, math.min(1, (now - at) / math.max(0.01, sky.Cycle.EventBlend)))
	end
	if type(id) == "string" and sky.RaidThemes[id] and sky.Looks[id] then
		St.LastEvent = id
		return id, x
	end
	if St.LastEvent then
		local back = 1 - x
		if back > 0 then
			return St.LastEvent, back
		end
		St.LastEvent = nil
	end
	return nil, 0
end

----------------------------------------------------------------------
-- The battle lift
----------------------------------------------------------------------

local function outdoorBattle()
	local player = Players.LocalPlayer
	local value = player and player:GetAttribute(Config.Attr.InBattle)
	local prefix = cfg().Lift.Prefix
	return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function setLift()
	local L = cfg().Lift
	local want = St.Running and St.Look ~= nil and L.Looks[St.Look] == true and outdoorBattle()
	if want and not St.Lift then
		St.Lift = true
		pcall(LightingStack.Push, L.Id, L.Preset, L.Seconds)
	elseif not want and St.Lift then
		St.Lift = false
		pcall(LightingStack.Pop, L.Id, L.Seconds)
	end
end

----------------------------------------------------------------------
-- Lamps
----------------------------------------------------------------------

local function restoreLamps()
	for light, brightness in pairs(St.LampBase) do
		pcall(function()
			light.Brightness = brightness
		end)
	end
	St.LampBase = setmetatable({}, { __mode = "k" })
	St.Lamps = 0
end

local function raiseLamps()
	local C = cfg().Lamps
	local root = Workspace:FindFirstChild(C.Root)
	if not root then
		return
	end
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("PointLight") and d.Parent and C.Names[d.Parent.Name] then
			if St.LampBase[d] == nil then
				St.LampBase[d] = d.Brightness
			end
			d.Brightness = St.LampBase[d] * C.Night
			n = n + 1
		end
	end
	St.Lamps = n
end

local function setLamps()
	local look = St.Running and St.Look or nil
	if look == St.LampLook then
		return
	end
	St.LampLook = look
	restoreLamps()
	if look and cfg().Lamps.Looks[look] then
		raiseLamps()
	end
end

----------------------------------------------------------------------
-- Fireflies
----------------------------------------------------------------------

local function clearFireflies()
	if St.FireflyFolder then
		pcall(function()
			St.FireflyFolder:Destroy()
		end)
	end
	St.FireflyFolder = nil
	St.Fireflies = 0
end

-- the lobby's trees (a "...Tree" model not inside another "...Tree"), sorted so every client picks the same ones
local function trees(root)
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Name:sub(-4) == "Tree" and not (d.Parent and d.Parent.Name:sub(-4) == "Tree") then
			local ok, pivot = pcall(function()
				return d:GetPivot()
			end)
			if ok and pivot then
				list[#list + 1] = { Model = d, Pos = pivot.Position }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.Pos.X ~= b.Pos.X then
			return a.Pos.X < b.Pos.X
		end
		return a.Pos.Z < b.Pos.Z
	end)
	return list
end

local function buildFireflies()
	local F = cfg().Fireflies
	local root = Workspace:FindFirstChild(F.Root)
	if not root then
		return
	end
	local list = trees(root)
	if #list == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = F.Folder
	local n = 0
	for i = 1, math.min(F.Max, #list) do
		local host = Instance.new("Part")
		host.Name = "Fireflies"
		host.Anchored = true
		host.CanCollide = false
		host.CanTouch = false
		host.CanQuery = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(F.Spread, F.Height * 0.6, F.Spread)
		host.CFrame = CFrame.new(list[i].Pos + Vector3.new(0, F.Height, 0))
		local e = Instance.new("ParticleEmitter") -- the default sparkle texture
		e.Rate = F.Rate
		e.Lifetime = NumberRange.new(F.Lifetime[1], F.Lifetime[2])
		e.Speed = NumberRange.new(F.Speed[1], F.Speed[2])
		e.SpreadAngle = Vector2.new(180, 180)
		e.Color = ColorSequence.new(F.Color)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, F.Size),
			NumberSequenceKeypoint.new(0.8, F.Size),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.15),
			NumberSequenceKeypoint.new(0.75, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Drag = 0.6
		e.Acceleration = Vector3.new(0, 0.05, 0)
		e.Parent = host
		host.Parent = folder
		n = n + 1
	end
	folder.Parent = Workspace
	St.FireflyFolder = folder
	St.Fireflies = n
end

local function setFireflies()
	local look = St.Running and St.Look or nil
	local want = look ~= nil and cfg().Fireflies.Looks[look] == true and not lowGraphics()
	if want and not (St.FireflyFolder and St.FireflyFolder.Parent) then
		clearFireflies()
		buildFireflies()
	elseif not want and St.FireflyFolder then
		clearFireflies()
	end
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------

-- everything this controller adds goes away (no clock, Stop); the base stays where the sky left it
local function settle()
	St.Phase, St.Next, St.Look, St.Theme, St.Event, St.EventBlend = nil, nil, nil, nil, nil, 0
	setLift()
	setLamps()
	setFireflies()
end

function SkyController.Refresh(now)
	local sky = cfg()
	local A = sky.Attr
	local epoch = Workspace:GetAttribute(A.Epoch)
	if not finite(epoch) then
		settle()
		return SkyController.State()
	end
	now = finite(now) and now or Workspace:GetServerTimeNow()
	local at = SkyCycle.At(now, epoch, Workspace:GetAttribute(A.Speed), Workspace:GetAttribute(A.Offset))
	local event, eventBlend = eventNow(now)
	local preset, theme = SkyCycle.Preset(at, event, eventBlend, SkyFaces.For)
	local raid = event ~= nil and eventBlend >= 0.5
	St.Phase, St.Next, St.Theme, St.Event, St.EventBlend = at.Phase, at.Next, theme, event, eventBlend
	St.Look = raid and event or (at.Blend >= 0.5 and at.Next or at.Phase)

	if LightingStack.Busy() then
		St.Skipped = St.Skipped + 1
	else
		local seconds = St.First and 0 or sky.Cycle.Tween
		local clock = preset.Lighting.ClockTime
		local seg = raid and event or at.Phase
		local instant = nil
		if not St.First and seg ~= St.Seg and finite(clock) and finite(St.Clock) and math.abs(clock - St.Clock) > sky.ClockJump then
			instant = { Lighting = { ClockTime = true } }
		end
		LightingStack.SetBase(preset, seconds, instant)
		St.First = false
		St.Seg, St.Clock = seg, clock
		St.Applies = St.Applies + 1
		local GQ = graphics()
		if GQ and type(GQ.Recap) == "function" then
			pcall(GQ.Recap, seconds)
		end
	end
	setLift()
	setLamps()
	setFireflies()
	return SkyController.State()
end

function SkyController.State()
	return {
		Phase = St.Phase,
		Next = St.Next,
		Look = St.Look,
		Theme = St.Theme,
		Event = St.Event,
		EventBlend = St.EventBlend,
		Lift = St.Lift,
		Lamps = St.Lamps,
		Fireflies = St.Fireflies,
		Applies = St.Applies,
		Skipped = St.Skipped,
		Loops = St.Loops,
		Running = St.Running,
	}
end

local function safeRefresh()
	local ok, err = pcall(SkyController.Refresh)
	if not ok then
		warn("[SkyController] refresh failed: " .. tostring(err))
	end
end

function SkyController.Start()
	if St.Running then
		return
	end
	St.Running = true
	St.First = true
	St.Gen = St.Gen + 1
	local gen = St.Gen
	local A = cfg().Attr
	-- a dev jump / speed change or a raid start shows at the next moment, not up to 2 s later
	for _, key in ipairs({ A.Epoch, A.Speed, A.Offset, A.Event, A.EventAt }) do
		St.Conns[#St.Conns + 1] = Workspace:GetAttributeChangedSignal(key):Connect(function()
			task.defer(function()
				if St.Running and St.Gen == gen then
					safeRefresh()
				end
			end)
		end)
	end
	local player = Players.LocalPlayer
	if player then
		St.Conns[#St.Conns + 1] = player:GetAttributeChangedSignal(Config.Attr.InBattle):Connect(function()
			if St.Running and St.Gen == gen then
				pcall(setLift)
			end
		end)
	end
	safeRefresh()
	St.Loops = St.Loops + 1
	St.Thread = task.spawn(function()
		while true do
			task.wait(cfg().Cycle.Refresh)
			if not St.Running or St.Gen ~= gen then
				break
			end
			safeRefresh()
		end
		if St.Gen == gen then
			St.Loops = St.Loops - 1
			St.Thread = nil
		end
	end)
end

SkyController.Init = SkyController.Start

function SkyController.Stop()
	if not St.Running then
		return
	end
	St.Running = false
	St.Gen = St.Gen + 1
	if St.Thread then
		pcall(task.cancel, St.Thread)
		St.Thread = nil
		St.Loops = St.Loops - 1
	end
	for _, c in ipairs(St.Conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	St.Conns = {}
	settle()
	St.Seg, St.Clock, St.LastEvent = nil, nil, nil
end

return SkyController
