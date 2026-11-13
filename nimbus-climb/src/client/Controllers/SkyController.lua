-- SkyController (client): the living sky on this client (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md,
-- plan docs/superpowers/plans/2026-10-30-living-sky.md Task 5). The server publishes the clock and the raid event as
-- Workspace attributes (server/Services/SkyService, Config.Sky.Attr); every Config.Sky.Cycle.Refresh (2) s this turns
-- them into the moment's look with shared/SkyCycle (+ shared/SkyFaces for the painted skybox) and moves the BASE of
-- client/LightingStack with a Cycle.Tween (2) s tween, so the Dungeon / GfxLow / AttackFxDim presets keep winning on
-- top. No per-frame code (one task.wait loop), no remote traffic. While a raid sky blends in or out the refresh runs
-- every Config.Sky.Transitions.Raid.Step (0.5) s with 0.5 s tweens instead (kit-b S1: the haze bridge around its skybox
-- swap is seen as a smooth rise, not 1-2 samples), and while a phase blends on a dev /sky speed above 1 (S1 review);
-- the loop wakes at most every Step s, counts the real seconds waited and refreshes when its step is due.
--
--   * no SkyEpoch attribute (an older server, tests): inert, the boot sky stays, nothing below runs
--   * the first apply after Start is instant (seconds 0): a late joiner never sees the boot afternoon fade away
--   * a refresh is skipped while LightingStack.Busy() (a Dungeon / AttackFxDim fade runs: never restarted); the next
--     refresh after it applies
--   * the clock: it tweens forward in the 2 s steps (SkyCycle's cycle clock only moves forward round the dial, the
--     Sunset -> Night and Night -> Dawn changes included). Set at once (LightingStack.SetBase's instant set) only
--     (a) when it passes midnight (23.9 -> 0.1: a tween would run back through the day; 24 h = 0 h, so invisible) and
--     (b) on a segment change (a raid sky's mid-blend, in or out) by more than Config.Sky.ClockJump h
--   * the raid sky: SkyEvent (a boss id with a RaidThemes sky) blends in over Transitions.Raid.In (8) s from SkyEventAt
--     (a late joiner mid-raid is on the raid sky at once) and back out over Raid.Out (6) s once SkyEvent is "" again. Each new
--     SkyEventAt starts a transition FROM what showed at that moment (St.From = { Id, Blend }): back-to-back raids
--     (SkyEvent storm_titan -> lava_golem, no clear) blend raid sky to raid sky (the skybox swap at the midpoint),
--     never back through the cycle look; a raid that ends half blended in leaves from where it was
--   * the local raid sky (SetLocalEvent, a fight in a side pocket): for this client alone it takes the place of the SkyEvent /
--     SkyEventAt attributes, with the same blend in and out; taken off, the attributes are back in charge (from that moment).
--     Both refresh at once (task.defer), not on the next loop tick (sky audit F3)
--   * the battle lift (Config.Sky.Lift): in an outdoor pet battle (Config.Attr.InBattle "B...") under a dark look
--     (Night, the eclipse raid) LightingStack.Push("SkyLift") over 1.5 s, popped over 1.5 s after the fight / at dawn
--   * the lamps (Config.Sky.Lamps): the lobby's LampGlass / LanternLight / StallLight / DomeGlow / TroveGlow PointLights
--     glow x1.4 under a dark look and dim to x0.35 under every other (bug batch 6: they burned at full strength all day),
--     never over 1.5; written on a look change, on a lamp that arrives under the lobby later, and on a lobby root that
--     arrives or is replaced later (the next refresh, same look); each lamp's own value is kept on the light (attribute
--     Lamps.BaseAttr, never a Lua-only weak cache: a lost base made the written value the next one); no clock / Stop =
--     their own value
--   * the fireflies (Config.Sky.Fireflies): at Night on High graphics a few emitters round the lobby trees (one local
--     folder, capped); none on Low (GraphicsQuality.Effective()) or by day
--   * Low graphics: GraphicsQuality.Recap after each applied refresh (the GfxLow cloud cap follows the sky, updated in
--     place and carried by the next refresh: it never cancels or re-eases these linear base tweens)
--   * the preload (kit-b S2, sky audit F4; client/SkyTransition): the next theme's six faces are fetched once per blend
--     window, at its first refresh inside it (about 37 s before the swap at blend 0.5), and the four raid themes once
--     the menu's PLAY fires (UiGate.Played; at once when Start comes after PLAY), once per Start
-- The "look" = the raid boss id from its eventBlend 0.5, else the next phase from the phase's Blend 0.5, else the phase
-- (the same moments the skybox swaps).
--
--   SkyController.Init() / Start()   idempotent: the loop, the attribute signals, a first (instant) refresh
--   SkyController.Stop()             tests: the loop ends, signals dropped, lift popped, lamps back, fireflies gone
--   SkyController.Refresh(now)       one step (tests drive it); now = server time (default Workspace:GetServerTimeNow())
--   SkyController.SetLocalEvent(bossId|nil) -> ok   the local raid sky on (a boss with a raid sky; anything else is refused) / off
--   SkyController.State() -> { Phase, Next, Look, Theme, Event, EventBlend, EventFrom, Local, Lift, Lamps, Fireflies, Applies,
--                              Skipped, Loops, Running }   (Lamps / Fireflies = how many lamps written / emitters on;
--                              EventFrom = the raid sky Event blends from on a back-to-back change, else nil;
--                              Local = the boss of the local raid sky, else nil)
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
local SkyTransition = require(Client:WaitForChild("SkyTransition"))

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
	EvSeen = false, -- the raid transition below has been read from the attributes once
	EvAt = nil, -- the SkyEventAt the current raid transition started at
	EvId = nil, -- the raid sky it goes to (nil = back to the cycle)
	From = nil, -- { Id, Blend }: the raid sky showing when it started (nil = the plain cycle)
	EventFrom = nil, -- the raid sky blending out under the new one (State)
	Local = nil, -- { Id, At }: the local raid sky (SetLocalEvent) in place of the attributes
	LocalOut = nil, -- { At, Attr }: it was taken off At, while SkyEventAt said Attr: the blend out runs from At until SkyEventAt moves
	Seg = nil, -- the clock segment applied last (a phase name or a raid boss id)
	Clock = nil, -- the ClockTime applied last
	Lift = false,
	LampLook = nil, -- the look the lamps were written for (each lamp's own Brightness: attribute Config.Sky.Lamps.BaseAttr)
	LampRoot = nil, -- the lobby root written and watched for lamps that arrive later ...
	LampConn = nil, -- ... and its DescendantAdded connection (dropped with the clock / on Stop)
	Lamps = 0,
	Fireflies = 0,
	FireflyFolder = nil,
	Applies = 0,
	Skipped = 0,
	Step = nil, -- the refresh step the last refresh chose (Cycle.Refresh, or Raid.Step while a raid sky blends)
	Waited = 0, -- real seconds the loop has waited since the last refresh (task.wait's return)
	GQ = nil, -- client/GraphicsQuality (lazy); false = unavailable
	Gate = nil, -- client/UiGate (lazy; tests put their own here); false = unavailable
	Preloaded = nil, -- the blend window ("<phase>><next>") whose next theme was preloaded; nil outside a window
	RaidsPreloaded = false, -- the four raid themes were preloaded since Start
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

local function uiGate()
	if St.Gate == nil then
		local module = Client:FindFirstChild("UiGate")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		St.Gate = (ok and type(result) == "table") and result or false
	end
	return St.Gate or nil
end

local function lowGraphics()
	local GQ = graphics()
	if GQ and type(GQ.Effective) == "function" then
		local ok, mode = pcall(GQ.Effective)
		return ok and mode == "Low"
	end
	return false
end

local function raidId(id)
	local sky = cfg()
	if type(id) == "string" and sky.RaidThemes[id] and sky.Looks[id] then
		return id
	end
	return nil
end

-- the current raid transition's length: Raid.In toward a raid sky (from the cycle or another raid), Raid.Out back
local function raidSeconds()
	local R = cfg().Transitions.Raid
	return St.EvId and R.In or R.Out
end

-- what the current raid transition shows at server time t: id, blend, fromId, fromBlend (SkyCycle.Preset's event args)
local function shownAt(t)
	local x = 1
	if finite(St.EvAt) then
		x = math.max(0, math.min(1, (t - St.EvAt) / math.max(0.01, raidSeconds())))
	end
	local from = St.From
	if St.EvId then
		if from and from.Id ~= St.EvId and x < 1 then
			return St.EvId, x, from.Id, from.Blend -- raid to raid
		end
		local b0 = from and from.Blend or 0 -- the same raid sky again: on from where it was
		return St.EvId, b0 + (1 - b0) * x, nil, 0
	end
	if from then
		local back = from.Blend * (1 - x)
		if back > 0 then
			return from.Id, back, nil, 0
		end
	end
	return nil, 0, nil, 0
end

-- the raid sky now (SkyEventAt-based, the same on every client that saw the change; a late joiner starts plain):
-- id (or nil), its blend 0..1, and the raid sky it blends from (fromId, fromBlend) on a back-to-back change
local function eventNow(now)
	local sky = cfg()
	local id = raidId(Workspace:GetAttribute(sky.Attr.Event))
	local at = Workspace:GetAttribute(sky.Attr.EventAt)
	if not finite(at) then
		at = nil
	end
	if St.Local then
		id, at = raidId(St.Local.Id), St.Local.At
	elseif St.LocalOut then
		if at == St.LocalOut.Attr then
			at = St.LocalOut.At
		else
			St.LocalOut = nil
		end
	end
	if St.EvSeen and at ~= St.EvAt then
		-- a new transition starts from what the old one shows at its moment (one { Id, Blend }: a raid-to-raid blend
		-- still running hands over its dominant sky)
		local oldId, oldBlend, oldFrom, oldFromBlend = shownAt(at or now)
		if oldFrom and oldBlend < 0.5 then
			St.From = { Id = oldFrom, Blend = oldFromBlend }
		elseif oldId and oldBlend > 0 then
			St.From = { Id = oldId, Blend = oldBlend }
		else
			St.From = nil
		end
	end
	St.EvSeen, St.EvAt, St.EvId = true, at, id
	local shownId, blend, fromId, fromBlend = shownAt(now)
	if not shownId or (St.EvId and blend >= 1) then
		St.From = nil -- the transition is over: nothing left to blend from
	end
	return shownId, blend, fromId, fromBlend
end

local function resetEvent()
	St.EvSeen, St.EvAt, St.EvId, St.From, St.EventFrom = false, nil, nil, nil, nil
end

-- the refresh step and tween at server time now (after eventNow): Raid.Step / Raid.Step while a raid transition is
-- still running (something to blend, inside its In / Out s), else Cycle.Refresh / Cycle.Tween. Also Raid.Step while a
-- phase blends (at.Blend > 0) on a sped-up clock (the dev /sky speed, SkySpeed > 1; kit-b S1 review): at speed 10 a
-- 2 s step is 20 loop s against the 30 loop s haze bridge, so the faces could swap in clear air. The whole 75 s blend
-- (not only the bridge) so the last 2 s step before it can never jump past the bridge's start; at speed 1 (play) the
-- 2 s step is 2 loop s and stays
local function cadence(now, at)
	local sky = cfg()
	local step = sky.Transitions.Raid.Step
	if St.EvSeen and finite(St.EvAt) and (St.EvId ~= nil or St.From ~= nil) and now - St.EvAt < raidSeconds() then
		return step, step
	end
	local speed = Workspace:GetAttribute(sky.Attr.Speed)
	if finite(speed) and speed > 1 and type(at) == "table" and finite(at.Blend) and at.Blend > 0 then
		return step, step
	end
	return sky.Cycle.Refresh, sky.Cycle.Tween
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
	local attr = cfg().Lamps.BaseAttr
	local root = St.LampRoot
	if St.LampConn then
		St.LampConn:Disconnect()
	end
	St.LampConn, St.LampRoot = nil, nil
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			local base = d:IsA("PointLight") and d:GetAttribute(attr)
			if finite(base) then
				pcall(function()
					d.Brightness = base
					d:SetAttribute(attr, nil)
				end)
			end
		end
	end
	St.Lamps = 0
end

-- one lamp under the look in St.LampLook: its own value x Night (a dark look) or x Day, never over Max. The own value
-- is kept on the light (BaseAttr) the first time, so it never becomes a written one (no x0.35 on x0.35)
local function writeLamp(d)
	local C = cfg().Lamps
	if not (d:IsA("PointLight") and d.Parent and C.Names[d.Parent.Name]) then
		return false
	end
	local base = d:GetAttribute(C.BaseAttr)
	if not finite(base) then
		base = d.Brightness
		d:SetAttribute(C.BaseAttr, base)
	end
	local k = C.Looks[St.LampLook] and C.Night or C.Day
	d.Brightness = math.min(base * k, C.Max)
	return true
end

local function writeLamps()
	local root = Workspace:FindFirstChild(cfg().Lamps.Root)
	if not root then
		return
	end
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if writeLamp(d) then
			n = n + 1
		end
	end
	St.Lamps = n
	-- a lamp that replicates in later takes the look at once (by day its built value is the bright one)
	if St.LampRoot ~= root then
		if St.LampConn then
			St.LampConn:Disconnect()
		end
		St.LampRoot = root
		St.LampConn = root.DescendantAdded:Connect(function(d)
			if St.LampLook and writeLamp(d) then
				St.Lamps = St.Lamps + 1
			end
		end)
	end
end

-- written on a look change; under the same look only while the lobby root is missing or was replaced (a lobby that
-- replicates after the first refresh, a LobbyBuilder.Build), never again over the same root
local function setLamps()
	local look = St.Running and St.Look or nil
	if look == St.LampLook and (look == nil or (St.LampRoot and St.LampRoot.Parent)) then
		return
	end
	St.LampLook = look
	if look then
		writeLamps()
	else
		restoreLamps()
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
-- Preload (kit-b S2)
----------------------------------------------------------------------

-- the next theme once per blend window (at = SkyCycle.At); a refresh outside every window clears the mark
local function preloadNext(at)
	if not (finite(at.Blend) and at.Blend > 0) then
		St.Preloaded = nil
		return
	end
	local key = tostring(at.Phase) .. ">" .. tostring(at.Next)
	if St.Preloaded ~= key then
		St.Preloaded = key
		pcall(SkyTransition.Preload, cfg().Themes[at.Next])
	end
end

-- the four raid themes (sorted by boss id: every client fetches them in the same order), once per Start
local function preloadRaids()
	if St.RaidsPreloaded or not St.Running then
		return
	end
	St.RaidsPreloaded = true
	local ids = {}
	for bossId in pairs(cfg().RaidThemes) do
		ids[#ids + 1] = bossId
	end
	table.sort(ids)
	for _, bossId in ipairs(ids) do
		pcall(SkyTransition.Preload, cfg().RaidThemes[bossId])
	end
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------

-- everything this controller adds goes away (no clock, Stop); the base stays where the sky left it
local function settle()
	St.Phase, St.Next, St.Look, St.Theme, St.Event, St.EventBlend = nil, nil, nil, nil, nil, 0
	resetEvent()
	setLift()
	setLamps()
	setFireflies()
end

function SkyController.Refresh(now)
	local sky = cfg()
	local A = sky.Attr
	local epoch = Workspace:GetAttribute(A.Epoch)
	St.Waited = 0
	if not finite(epoch) then
		St.Step = sky.Cycle.Refresh
		settle()
		return SkyController.State()
	end
	now = finite(now) and now or Workspace:GetServerTimeNow()
	local at = SkyCycle.At(now, epoch, Workspace:GetAttribute(A.Speed), Workspace:GetAttribute(A.Offset))
	preloadNext(at)
	local event, eventBlend, fromId, fromBlend = eventNow(now)
	local step, tween = cadence(now, at)
	St.Step = step
	local preset, theme = SkyCycle.Preset(at, event, eventBlend, SkyFaces.For, fromId, fromBlend)
	-- the raid sky in charge (the same moments SkyCycle switches the clock and the skybox): the new raid from its
	-- blend 0.5, else the one it blends from while that is at 0.5 or more
	local raid = nil
	if event ~= nil and eventBlend >= 0.5 then
		raid = event
	elseif fromId ~= nil and fromBlend >= 0.5 then
		raid = fromId
	end
	St.Phase, St.Next, St.Theme, St.Event, St.EventBlend, St.EventFrom = at.Phase, at.Next, theme, event, eventBlend, fromId
	St.Look = raid or (at.Blend >= 0.5 and at.Next or at.Phase)

	if LightingStack.Busy() then
		St.Skipped = St.Skipped + 1
	else
		local seconds = St.First and 0 or tween
		local clock = preset.Lighting.ClockTime
		local seg = raid or at.Phase
		local instant = nil
		if not St.First and finite(clock) and finite(St.Clock) then
			local jump = seg ~= St.Seg and math.abs(SkyCycle.ClockDelta(St.Clock, clock)) > sky.ClockJump
			local midnight = clock < St.Clock and SkyCycle.ClockDelta(St.Clock, clock) > 0 -- forward past 24 -> 0
			if jump or midnight then
				instant = { Lighting = { ClockTime = true } }
			end
		end
		LightingStack.SetBase(preset, seconds, instant)
		St.First = false
		St.Seg, St.Clock = seg, clock
		St.Applies = St.Applies + 1
		local GQ = graphics()
		if GQ and type(GQ.Recap) == "function" then
			pcall(GQ.Recap) -- in place: the cap rides the next SetBase, never a re-push over these tweens
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
		EventFrom = St.EventFrom,
		Local = St.Local and St.Local.Id or nil,
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
	-- the raid skies after PLAY (a raid becomes possible), at once when PLAY came first
	St.RaidsPreloaded = false
	local gate = uiGate()
	if gate and type(gate.HasPlayed) == "function" and gate.HasPlayed() then
		preloadRaids()
	elseif gate and type(gate.Played) == "table" and type(gate.Played.Connect) == "function" then
		St.Conns[#St.Conns + 1] = gate.Played:Connect(function()
			if St.Running and St.Gen == gen then
				preloadRaids()
			end
		end)
	end
	safeRefresh()
	St.Loops = St.Loops + 1
	St.Thread = task.spawn(function()
		while true do
			-- wake at most every Raid.Step s (cheap), never past the due step; refresh when the step the last refresh
			-- chose is due, so a raid that starts mid-step goes onto the fast cadence at once. St.Waited counts the
			-- REAL seconds task.wait returns (each wait runs up to a frame late: four nominal 0.5 s ticks drifted the
			-- 2 s step to 2.13 s, a pause in the 2 s linear tweens); the last wait is only what is left, so a refresh
			-- is at most one frame late, as with one task.wait(2)
			local step = St.Step or cfg().Cycle.Refresh
			local dt = task.wait(math.max(0, math.min(cfg().Transitions.Raid.Step, step - St.Waited)))
			if not St.Running or St.Gen ~= gen then
				break
			end
			St.Waited = St.Waited + (tonumber(dt) or 0)
			if St.Waited >= step - 1e-6 then
				St.Waited = 0
				safeRefresh()
			end
		end
		if St.Gen == gen then
			St.Loops = St.Loops - 1
			St.Thread = nil
		end
	end)
end

SkyController.Init = SkyController.Start

-- a refresh right after this frame (a running controller only), like the attribute signals' (sky audit F3: the pocket
-- fight's sky used to wait for the next loop tick, and could open on the swap itself)
local function refreshSoon()
	if not St.Running then
		return
	end
	local gen = St.Gen
	task.defer(function()
		if St.Running and St.Gen == gen then
			safeRefresh()
		end
	end)
end

function SkyController.SetLocalEvent(bossId)
	if bossId == nil then
		if St.Local then
			St.LocalOut = { At = Workspace:GetServerTimeNow(), Attr = Workspace:GetAttribute(cfg().Attr.EventAt) }
			St.Local = nil
			refreshSoon()
		end
		return true
	end
	if not raidId(bossId) then
		return false
	end
	if not (St.Local and St.Local.Id == bossId) then
		St.Local = { Id = bossId, At = Workspace:GetServerTimeNow() }
		refreshSoon()
	end
	St.LocalOut = nil
	return true
end

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
	St.Seg, St.Clock = nil, nil
	resetEvent()
	St.Local, St.LocalOut = nil, nil
end

return SkyController
