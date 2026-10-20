-- EvolutionFx (client): the evolution animation of a pet, played on this client only (its parts never exist on
-- the server, so nothing replicates). Used by the developer pet showcase (DevPetShow, "/evolve") and by the game's own
-- EVOLVE moment (CareController, Phase 4: two fresh PetBuilder clones in front of the player, with Confetti = true).
--
--   EvolutionFx.Play(fromModel, toModel, pose, opts) -> handle
--       fromModel  the pet as it is now: a PetBuilder model at rest (any stage), placed at `pose`
--       toModel    the evolved pet: a PetBuilder model at rest (parented to opts.Parent when it appears)
--       pose       CFrame of the pets' root (PrimaryPart) at rest: where both hover; LookVector = their facing
--       opts       { Parent = Instance for toModel and the effect parts (default workspace),
--                    Colors = { Color3, Color3 } (glow, sparks: PetBuilder.EvolutionColors),
--                    Stage = 1 | 2 (the stage reached; the second evolution is grander and longer),
--                    Ground = y of the floor under the pets (default: just under fromModel),
--                    Confetti = true (Phase 4, the game's EVOLVE moment: a burst of voxel confetti at the reveal),
--                    OnDone = function(toModel) (called once, after the animation or Stop) }
--       handle     { Done = false/true, Model = the pet on show (fromModel, then toModel), Stop = function() }
--                  Stop() ends it at once: fromModel destroyed, toModel at rest at `pose`, the effects gone.
--   EvolutionFx.Duration(stage) -> seconds the animation lasts
--   EvolutionFx.Count() -> evolutions playing right now
--   EvolutionFx.Arrive(pivot, opts) -> handle   (dungeon fixes, decision 3) an enemy's arrival: EFFECTS ONLY (no model
--       is touched): the evolution's rune ring on the ground, a light pillar, the white flash with a sparkle burst, the
--       shock ring and voxel sparks, about 1.2 s. pivot = CFrame of the arriving pet's centre.
--       opts { Parent (default workspace), Colors = { Color3, Color3 }, Height, Radius (studs of the pet), Ground (y of
--              the floor; default pivot.Y - Height / 2), Seconds (default 1.2), Quality "Low" | "High" (default
--              GraphicsQuality.Effective()), OnFlash = function() (once, at the flash: the caller pops its model in),
--              OnDone = function() (once, at the end or on Stop) }
--       handle { Done, Low, FlashAt (seconds after the start), T, Stop = function() (ends it at once, OnFlash still
--              runs once) }
--       Cheap: the parts live in pooled kits (one kit per arrival, reused; nothing is created after the first wave),
--       one BulkMoveTo per piece list per frame with reused buffers; at most ARRIVE_MAX full kits at once (more
--       arrivals at the same moment get the Low kit). Low = the flash + the shock ring only (13 parts, no light, no
--       particles).
--   EvolutionFx.ArriveStats() -> { Live, LiveLow, Pooled, Parts }   (tests)
--
-- The animation (stage 1 about 4.3 s, stage 2 about 5 s):
--   charge  the pet rises and spins faster and faster while it starts to glow (a Highlight), a ring of voxel runes
--           grows on the ground under it (two counter-rotating rings for the second evolution), glowing motes
--           spiral in and a pillar of light rises
--   burst   the pet shrinks into a white flash and the pillar flares
--   reveal  the evolved pet pops out of the flash (overshoot, then settles), spins down to face forward exactly
--           as it was, sinks back to its hover height; a shock ring races over the ground, voxel sparks burst out
--           and sparkles fly; the glow fades
-- Pets are moved and scaled by placing / resizing their parts from their rest offsets (workspace:BulkMoveTo), so
-- PetBuilder.Animate must not run on them meanwhile; at the end toModel is back at rest, ready for Animate.
-- One RenderStepped connection while anything plays; every effect part is anchored, CanCollide / CanTouch /
-- CanQuery off, CastShadow off. Plain Lua 5.1-compatible syntax only.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EvolutionFx = {}

local TAU = math.pi * 2
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.fromRGB(255, 255, 255)

local K = {
	CHARGE = { 2.0, 2.6 }, -- seconds of charging, per stage reached
	BURST = 0.38,
	REVEAL = 1.35,
	SETTLE = 0.6,
	RISE = 0.28, -- the pet rises this share of its height while charging
	SPIN = 4.5, -- turns per second at the end of the charge
	REVEAL_TURNS = 2, -- turns the evolved pet spins down through
	MIN_SCALE = 0.04,
	RUNES = { 20, 28 }, -- voxel runes in the ground ring
	MOTES = { 18, 28 },
	SPARKS = { 22, 34 },
	PILLAR = { 9, 12 }, -- pillar height in pet heights... capped below
	PILLAR_MAX = 60, -- studs
	CONFETTI = 26, -- voxel confetti bits (opts.Confetti)
	-- an enemy's arrival (EvolutionFx.Arrive): seconds, the flash moment (share of the time), piece counts, caps
	ARRIVE_SECONDS = 1.2,
	ARRIVE_FLASH = 0.35,
	ARRIVE_RUNES = 12,
	ARRIVE_SHOCK = 16,
	ARRIVE_SHOCK_LOW = 12,
	ARRIVE_SPARKS = 10,
	ARRIVE_SPARKLES = 22,
	ARRIVE_MAX = 6, -- full kits at once (a wave of 3-5 + an escort); more arrivals at once get the Low kit
	ARRIVE_MAX_LOW = 16, -- beyond this nothing is drawn (OnFlash runs at once)
	ARRIVE_POOL = 6, -- kits of each kind kept for reuse
	CONFETTI_COLORS = {
		Color3.fromRGB(255, 96, 120),
		Color3.fromRGB(255, 176, 64),
		Color3.fromRGB(255, 226, 90),
		Color3.fromRGB(110, 214, 120),
		Color3.fromRGB(96, 176, 255),
		Color3.fromRGB(186, 128, 255),
	},
}

local plays = {}
local arrivals = {} -- live EvolutionFx.Arrive plays
local kitPool = { High = {}, Low = {} } -- free arrival kits
local loopConn = nil
local onFrame -- (below)
local quality = nil -- client/GraphicsQuality (lazy; false = unavailable)

local function ensureLoop()
	if not loopConn then
		loopConn = RunService.RenderStepped:Connect(function(dt)
			onFrame(dt)
		end)
	end
end

local function maybeStopLoop()
	if #plays == 0 and #arrivals == 0 and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function easeIn(x)
	x = clamp01(x)
	return x * x * x
end

local function easeOut(x)
	x = clamp01(x)
	local y = 1 - x
	return 1 - y * y * y
end

-- overshoots to about 1.1 and settles at 1
local function easeOutBack(x)
	x = clamp01(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

local function lighten(c, t)
	return c:Lerp(WHITE, t)
end

-- a small deterministic "random" in [0, 1) per index
local function hash(i, salt)
	local h = math.sin(i * 12.9898 + (salt or 0) * 78.233) * 43758.5453
	return h - math.floor(h)
end

local function effectPart(play, name, shape, color, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.Neon
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Parent = play.Folder
	return p
end

-- The pet's parts, their rest offsets from the root and their sizes.
local function rigOf(model)
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local base = root.CFrame
	local rig = { Model = model, Root = root, Parts = {}, Pos = {}, Rot = {}, Size = {}, Scale = 1, Buf = {}, Posed = nil }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = base:ToObjectSpace(d.CFrame)
			local n = #rig.Parts + 1
			rig.Parts[n] = d
			rig.Pos[n] = rel.Position
			rig.Rot[n] = rel - rel.Position
			rig.Size[n] = d.Size
		end
	end
	return rig
end

-- Places the pet with its root at cf, scaled by s around the root.
local function poseRig(rig, cf, s)
	if not rig or not rig.Model.Parent then
		return
	end
	local resize = s ~= rig.Scale
	if not resize and rig.Posed == cf then
		return -- already there (the settle phase holds the pose): nothing to move this frame
	end
	local list = rig.Buf -- reused every frame: no table per frame
	for i, part in ipairs(rig.Parts) do
		if resize then
			part.Size = rig.Size[i] * s
		end
		list[i] = cf * CFrame.new(rig.Pos[i] * s) * rig.Rot[i]
	end
	rig.Scale = s
	rig.Posed = cf
	Workspace:BulkMoveTo(rig.Parts, list, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Height, radius (half the larger horizontal size) and the offset from the root down to the pet's lowest point.
local function measure(rig)
	local lo, hi = math.huge, -math.huge
	local rx = 0
	local base = rig.Root.CFrame
	for i, part in ipairs(rig.Parts) do
		if part.Transparency < 1 then
			local p = rig.Pos[i]
			local half = rig.Size[i].Magnitude / 2
			lo = math.min(lo, p.Y - half)
			hi = math.max(hi, p.Y + half)
			rx = math.max(rx, math.abs(p.X) + half, math.abs(p.Z) + half)
		end
	end
	if lo == math.huge then
		return 3, 2, -1.5, base
	end
	return hi - lo, rx, lo, base
end

----------------------------------------------------------------------
-- One play
----------------------------------------------------------------------
local function ringPose(play, i, n, radius, turn, lift)
	local a = i / n * TAU + turn
	local c = play.Pose
	local centre = Vector3.new(c.Position.X, play.Ground + (lift or 0.06), c.Position.Z)
	local pos = centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
	return CFrame.new(pos) * CFrame.Angles(0, -a, 0)
end

-- the sparkle burst emitter (Rate 0: Emit(n) only) on an attachment of `part`; also used by the arrival kits
local function newSparkles(part, c1, c2, R, u)
	local att = Instance.new("Attachment")
	att.Name = "EvolveSparkles"
	att.Parent = part
	local em = Instance.new("ParticleEmitter")
	em.Name = "EvolveSparkles"
	em.Texture = SPARKLE
	em.LightEmission = 1
	em.LightInfluence = 0
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.7, 1.4)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-180, 180)
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Parent = att
	local function tune(a, b, radius, unit)
		em.Color = ColorSequence.new(lighten(a, 0.3), lighten(b, 0.3))
		em.Speed = NumberRange.new(radius * 2.2, radius * 4.4)
		em.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, unit * 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	tune(c1, c2, R, u)
	return em, tune
end

local function buildEffects(play)
	local stage = play.Stage
	local c1, c2 = play.Colors[1], play.Colors[2]
	local R, H = play.Radius, play.Height
	local u = math.max(0.6, math.min(R, H) * 0.22) -- size unit of the voxel bits
	play.Unit = u
	-- glow on the pet
	local hl = Instance.new("Highlight")
	hl.Name = "EvolveGlow"
	hl.FillColor = lighten(c1, 0.35)
	hl.OutlineColor = lighten(c2, 0.5)
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Adornee = play.From.Model
	hl.Parent = play.Folder
	play.Glow = hl
	-- the rune ring(s) on the ground
	play.Runes = {}
	local rings = (stage == 2) and 2 or 1
	for r = 1, rings do
		local n = K.RUNES[stage] - (r - 1) * 8
		for i = 1, n do
			local col = ((i + r) % 2 == 0) and c1 or c2
			local part = effectPart(play, "EvolveRune", nil, col, Vector3.new(u * 0.55, u * 0.14, u * ((i % 3 == 0) and 1.5 or 0.9)))
			part.Transparency = 1
			play.Runes[#play.Runes + 1] = { Part = part, I = i, N = n, Ring = r }
		end
	end
	-- motes that spiral in
	play.Motes = {}
	for i = 1, K.MOTES[stage] do
		local part = effectPart(play, "EvolveMote", nil, (i % 2 == 0) and c1 or c2, Vector3.new(u * 0.4, u * 0.4, u * 0.4))
		part.Transparency = 1
		play.Motes[i] = { Part = part, A = hash(i, 1) * TAU, Y = 0.15 + hash(i, 2) * 1.05, Delay = hash(i, 3) * 0.35 }
	end
	-- the pillar of light (a cylinder's axis is its X axis: turned upright)
	local pillar = effectPart(play, "EvolvePillar", Enum.PartType.Cylinder, lighten(c1, 0.45), Vector3.new(0.1, R * 1.4, R * 1.4))
	pillar.Transparency = 1
	play.Pillar = pillar
	play.PillarHeight = math.min(K.PILLAR_MAX, H * K.PILLAR[stage])
	local light = Instance.new("PointLight")
	light.Name = "EvolveLight"
	light.Color = lighten(c1, 0.3)
	light.Range = math.min(40, R * 4 + 8)
	light.Brightness = 0
	light.Parent = pillar
	play.Light = light
	-- the flash
	local flash = effectPart(play, "EvolveFlash", Enum.PartType.Ball, WHITE, Vector3.new(0.2, 0.2, 0.2))
	flash.Transparency = 1
	play.Flash = flash
	-- sparkles (emitted in bursts)
	play.Emitter = newSparkles(flash, c1, c2, R, u)
	-- shock ring + sparks (shown at the reveal)
	play.Shock = {}
	for i = 1, 28 do
		local part = effectPart(play, "EvolveShock", nil, (i % 2 == 0) and lighten(c2, 0.2) or WHITE, Vector3.new(u * 0.5, u * 0.18, u * 1.4))
		part.Transparency = 1
		play.Shock[i] = part
	end
	play.Sparks = {}
	for i = 1, K.SPARKS[stage] do
		local part = effectPart(play, "EvolveSpark", nil, (i % 3 == 0) and WHITE or ((i % 2 == 0) and c1 or c2), Vector3.new(u * 0.45, u * 0.45, u * 0.45))
		part.Transparency = 1
		local a = hash(i, 5) * TAU
		local speed = R * (2.4 + hash(i, 6) * 2.2)
		play.Sparks[i] = {
			Part = part,
			V = Vector3.new(math.cos(a) * speed, R * (2.2 + hash(i, 7) * 2.6), math.sin(a) * speed),
			Spin = Vector3.new(hash(i, 8) * 9, hash(i, 9) * 9, hash(i, 10) * 9),
		}
	end
	-- confetti (Phase 4's EVOLVE moment): flat voxel bits that pop up from the pet and flutter down
	play.Confetti = {}
	if play.ConfettiOn then
		for i = 1, K.CONFETTI do
			local col = K.CONFETTI_COLORS[(i - 1) % #K.CONFETTI_COLORS + 1]
			local part = effectPart(play, "EvolveConfetti", nil, col, Vector3.new(u * 0.5, u * 0.08, u * 0.32))
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 1
			local a = hash(i, 13) * TAU
			local speed = R * (0.8 + hash(i, 14) * 1.6)
			play.Confetti[i] = {
				Part = part,
				V = Vector3.new(math.cos(a) * speed, R * (3 + hash(i, 15) * 2.4), math.sin(a) * speed),
				Spin = Vector3.new(4 + hash(i, 16) * 8, hash(i, 17) * 6, 3 + hash(i, 18) * 8),
				Phase = hash(i, 19) * TAU,
			}
		end
	end
end

local function cleanup(play)
	if play.Folder then
		pcall(function()
			play.Folder:Destroy()
		end)
		play.Folder = nil
	end
end

local function finish(play)
	if play.Handle.Done then
		return
	end
	play.Handle.Done = true
	-- fromModel goes, toModel rests exactly at the pose (scale 1)
	if play.From and play.From.Model then
		pcall(function()
			play.From.Model:Destroy()
		end)
	end
	if play.To and play.To.Model then
		if not play.To.Model.Parent then
			play.To.Model.Parent = play.Parent
		end
		poseRig(play.To, play.Pose, 1)
	end
	play.Handle.Model = play.To and play.To.Model or nil
	cleanup(play)
	for i = #plays, 1, -1 do
		if plays[i] == play then
			table.remove(plays, i)
		end
	end
	maybeStopLoop()
	if type(play.OnDone) == "function" and play.To then
		local ok, err = pcall(play.OnDone, play.To.Model)
		if not ok then
			warn("[EvolutionFx] OnDone failed: " .. tostring(err))
		end
	end
end

local function step(play, dt)
	play.T = play.T + dt
	local t = play.T
	local c, b, r, s = play.Charge, K.BURST, K.REVEAL, K.SETTLE
	local pose, H, R, u = play.Pose, play.Height, play.Radius, play.Unit
	local rise = H * K.RISE
	local runeTurn = t * 0.9
	-- the rune rings: grow while charging, stay through the reveal, fade while settling
	local ringP = smooth(t / (c * 0.6))
	local ringFade = clamp01((t - (c + b + r)) / s)
	local runeList, cfs = {}, {}
	for _, rune in ipairs(play.Runes) do
		local radius = R * (0.45 + 0.75 * ringP) * ((rune.Ring == 2) and 0.68 or 1)
		local turn = (rune.Ring == 2) and -runeTurn * 1.4 or runeTurn
		runeList[#runeList + 1] = rune.Part
		cfs[#cfs + 1] = ringPose(play, rune.I, rune.N, radius, turn, (rune.Ring == 2) and 0.1 or 0.06)
		rune.Part.Transparency = 1 - ringP * 0.9 * (1 - ringFade)
	end
	if #runeList > 0 then
		Workspace:BulkMoveTo(runeList, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local centre = pose.Position + Vector3.new(0, rise * smooth(t / c), 0)
	if t < c then
		-- charge: rise, spin up, shake a little, glow; motes spiral in; the pillar rises
		local p = t / c
		play.Yaw = play.Yaw + dt * TAU * K.SPIN * p * p
		local shake = H * 0.015 * p * p
		local jx = (hash(math.floor(t * 30), 11) - 0.5) * shake
		local jz = (hash(math.floor(t * 30), 12) - 0.5) * shake
		poseRig(play.From, pose * CFrame.new(jx, rise * smooth(p), jz) * CFrame.Angles(0, play.Yaw, 0), 1)
		play.Glow.FillTransparency = 1 - 0.78 * smooth(p)
		play.Glow.OutlineTransparency = 1 - smooth(p * 1.4)
		local moteList, moteCfs = {}, {}
		for i, m in ipairs(play.Motes) do
			local q = clamp01((p - m.Delay) / (1 - m.Delay))
			local radius = R * 1.9 * (1 - easeIn(q)) + R * 0.1
			local a = m.A + q * TAU * 1.6
			local y = pose.Position.Y - H * 0.4 + H * m.Y * (1 - q * 0.5) + rise * smooth(p)
			moteList[i] = m.Part
			moteCfs[i] = CFrame.new(centre.X + math.cos(a) * radius, y, centre.Z + math.sin(a) * radius) * CFrame.Angles(t * 3 + i, t * 2, 0)
			m.Part.Transparency = (q > 0 and q < 0.98) and 0.05 or 1
		end
		Workspace:BulkMoveTo(moteList, moteCfs, Enum.BulkMoveMode.FireCFrameChanged)
		local ph = play.PillarHeight * smooth(p * 1.3)
		local w = R * (0.9 + 0.3 * p)
		play.Pillar.Size = Vector3.new(math.max(0.1, ph), w, w)
		play.Pillar.CFrame = CFrame.new(centre.X, play.Ground + ph / 2, centre.Z) * CFrame.Angles(0, 0, math.pi / 2)
		play.Pillar.Transparency = 1 - 0.38 * smooth(p * 1.5)
		play.Light.Brightness = 3 * p
	elseif t < c + b then
		-- burst: the pet shrinks into a white flash; the pillar flares
		if not play.BurstStarted then
			play.BurstStarted = true
			for _, m in ipairs(play.Motes) do
				m.Part.Transparency = 1
			end
		end
		local p = (t - c) / b
		play.Yaw = play.Yaw + dt * TAU * K.SPIN
		poseRig(play.From, pose * CFrame.new(0, rise, 0) * CFrame.Angles(0, play.Yaw, 0), math.max(K.MIN_SCALE, 1 - easeIn(p)))
		local fs = (R * 0.4 + R * 1.3 * easeOut(p)) * 2
		play.Flash.Size = Vector3.new(fs, fs, fs)
		play.Flash.CFrame = CFrame.new(centre)
		play.Flash.Transparency = 0.2 + 0.2 * p
		local w = R * (1.2 + 1.2 * easeOut(p))
		play.Pillar.Size = Vector3.new(play.PillarHeight, w, w)
		play.Pillar.Transparency = 0.55 + 0.45 * p
		play.Light.Brightness = 3 + 3 * p
	elseif t < c + b + r then
		-- reveal: swap the pets once, then the evolved pet pops out, spins down to face forward and sinks back
		if not play.Swapped then
			play.Swapped = true
			pcall(function()
				play.From.Model.Parent = nil
			end)
			play.To.Model.Parent = play.Parent
			play.Glow.Adornee = play.To.Model
			play.Glow.FillColor = WHITE
			play.Glow.FillTransparency = 0
			play.Glow.OutlineTransparency = 0
			play.Handle.Model = play.To.Model
			play.Pillar.Transparency = 1
			play.Emitter:Emit(play.Stage == 2 and 70 or 45)
			play.SparkT0 = t
		end
		local p = (t - c - b) / r
		local yaw = TAU * K.REVEAL_TURNS * easeOut(p)
		local scale = K.MIN_SCALE + (1 - K.MIN_SCALE) * easeOutBack(math.min(1, p * 1.25))
		poseRig(play.To, pose * CFrame.new(0, rise * (1 - smooth(p)), 0) * CFrame.Angles(0, yaw, 0), math.max(K.MIN_SCALE, scale))
		play.Glow.FillTransparency = smooth(p)
		play.Glow.OutlineTransparency = smooth(p * 0.8)
		local fs = R * 1.7 * 2 * (1 + 0.35 * p)
		play.Flash.Size = Vector3.new(fs, fs, fs)
		play.Flash.Transparency = 0.4 + 0.6 * smooth(p * 3)
		play.Light.Brightness = 6 * (1 - p)
	else
		-- settle: hold the pose while the effects fade, then finish
		poseRig(play.To, pose, 1)
		play.Glow.FillTransparency = 1
		play.Glow.OutlineTransparency = 1
		play.Flash.Transparency = 1
		play.Light.Brightness = 0
		if t >= c + b + r + s then
			finish(play)
			return
		end
	end
	-- the shock ring and the sparks (from the swap on)
	if play.SparkT0 then
		local q = t - play.SparkT0
		local shockP = clamp01(q / 0.85)
		local list, list2 = {}, {}
		for i, part in ipairs(play.Shock) do
			list[i] = part
			list2[i] = ringPose(play, i, #play.Shock, R * (0.8 + 2.4 * easeOut(shockP)), 0, 0.12)
			part.Transparency = (shockP < 1) and (0.1 + 0.9 * shockP) or 1
		end
		Workspace:BulkMoveTo(list, list2, Enum.BulkMoveMode.FireCFrameChanged)
		local sl, sc = {}, {}
		local base = pose.Position + Vector3.new(0, rise * 0.5, 0)
		for i, sp in ipairs(play.Sparks) do
			local pos = base + sp.V * q + Vector3.new(0, -0.5 * 26 * q * q, 0)
			if pos.Y < play.Ground + u * 0.2 then
				pos = Vector3.new(pos.X, play.Ground + u * 0.2, pos.Z)
			end
			sl[i] = sp.Part
			sc[i] = CFrame.new(pos) * CFrame.Angles(sp.Spin.X * q, sp.Spin.Y * q, sp.Spin.Z * q)
			sp.Part.Transparency = clamp01(q / 1.2)
		end
		Workspace:BulkMoveTo(sl, sc, Enum.BulkMoveMode.FireCFrameChanged)
		if #play.Confetti > 0 then
			-- up fast, then a slow flutter down (drag), fading out near the end of the settle
			local cl, cc = {}, {}
			local top = pose.Position + Vector3.new(0, H * 0.6, 0)
			local fade = clamp01((q - 1.3) / 0.6)
			for i, cf in ipairs(play.Confetti) do
				local k = 1 - math.exp(-2.2 * q)
				local drift = cf.V * (k / 2.2)
				local fall = 2.4 * math.max(0, q - 0.35) ^ 1.5
				local sway = math.sin(q * 6 + cf.Phase) * u * 0.6
				local pos = top + Vector3.new(drift.X + sway, drift.Y - fall * R, drift.Z)
				if pos.Y < play.Ground + u * 0.1 then
					pos = Vector3.new(pos.X, play.Ground + u * 0.1, pos.Z)
				end
				cl[i] = cf.Part
				cc[i] = CFrame.new(pos) * CFrame.Angles(cf.Spin.X * q, cf.Spin.Y * q, cf.Spin.Z * q)
				cf.Part.Transparency = fade
			end
			Workspace:BulkMoveTo(cl, cc, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	play.Handle.T = t
end

----------------------------------------------------------------------
-- An enemy's arrival (EvolutionFx.Arrive): pooled kits of effect parts, effects only
----------------------------------------------------------------------
local function kitPart(folder, name, shape)
	local p = effectPart({ Folder = folder }, name, shape, WHITE, Vector3.new(0.2, 0.2, 0.2))
	p.Transparency = 1
	return p
end

local function kitCount(kit)
	local n = #kit.Shock + #kit.Runes + #kit.Sparks + 1
	if kit.Pillar then
		n = n + 1
	end
	return n
end

-- one kit: Low = the flash + the shock ring; High adds the rune ring, the pillar (+ light), the sparkles, the sparks
local function newKit(low)
	local folder = Instance.new("Folder")
	folder.Name = "ArriveFx"
	local kit = { Low = low, Folder = folder, Runes = {}, Shock = {}, Sparks = {}, SparkV = {}, SparkSpin = {}, BufP = {}, BufC = {} }
	kit.Flash = kitPart(folder, "ArriveFlash", Enum.PartType.Ball)
	for i = 1, low and K.ARRIVE_SHOCK_LOW or K.ARRIVE_SHOCK do
		kit.Shock[i] = kitPart(folder, "ArriveShock")
	end
	if not low then
		for i = 1, K.ARRIVE_RUNES do
			kit.Runes[i] = kitPart(folder, "ArriveRune")
		end
		kit.Pillar = kitPart(folder, "ArrivePillar", Enum.PartType.Cylinder)
		local light = Instance.new("PointLight")
		light.Name = "ArriveLight"
		light.Brightness = 0
		light.Parent = kit.Pillar
		kit.Light = light
		kit.Emitter, kit.Tune = newSparkles(kit.Flash, WHITE, WHITE, 2, 0.6)
		for i = 1, K.ARRIVE_SPARKS do
			kit.Sparks[i] = kitPart(folder, "ArriveSpark")
		end
	end
	return kit
end

-- the kit's parts sized and coloured for this arrival (once per play, never per frame)
local function dressKit(kit, play)
	local c1, c2, R, u = play.Colors[1], play.Colors[2], play.Radius, play.Unit
	kit.Flash.Size = Vector3.new(0.2, 0.2, 0.2)
	kit.Flash.Color = WHITE
	for i, part in ipairs(kit.Shock) do
		part.Size = Vector3.new(u * 0.5, u * 0.18, u * 1.3)
		part.Color = (i % 2 == 0) and lighten(c2, 0.2) or WHITE
	end
	for i, part in ipairs(kit.Runes) do
		part.Size = Vector3.new(u * 0.55, u * 0.14, u * ((i % 3 == 0) and 1.5 or 0.9))
		part.Color = (i % 2 == 0) and c1 or c2
	end
	if kit.Pillar then
		kit.Pillar.Color = lighten(c1, 0.45)
		kit.Light.Color = lighten(c1, 0.3)
		kit.Light.Range = math.min(32, R * 4 + 8)
		kit.Light.Brightness = 0
		kit.Tune(c1, c2, R, u)
	end
	for i, part in ipairs(kit.Sparks) do
		part.Size = Vector3.new(u * 0.45, u * 0.45, u * 0.45)
		part.Color = (i % 3 == 0) and WHITE or ((i % 2 == 0) and c1 or c2)
		local a = hash(i, 5) * TAU + play.Salt
		local speed = R * (2.0 + hash(i, 6) * 1.8)
		kit.SparkV[i] = Vector3.new(math.cos(a) * speed, R * (2 + hash(i, 7) * 2.2), math.sin(a) * speed)
		kit.SparkSpin[i] = Vector3.new(hash(i, 8) * 9, hash(i, 9) * 9, hash(i, 10) * 9)
	end
end

local function hideKit(kit)
	kit.Flash.Transparency = 1
	for _, list in ipairs({ kit.Shock, kit.Runes, kit.Sparks }) do
		for _, part in ipairs(list) do
			part.Transparency = 1
		end
	end
	if kit.Pillar then
		kit.Pillar.Transparency = 1
		kit.Light.Brightness = 0
	end
end

local function takeKit(low, parent)
	local pool = kitPool[low and "Low" or "High"]
	while #pool > 0 do
		local kit = table.remove(pool)
		if pcall(function()
			kit.Folder.Parent = parent
		end) then
			return kit
		end
	end
	local kit = newKit(low)
	kit.Folder.Parent = parent
	return kit
end

local function giveKit(kit)
	hideKit(kit)
	local pool = kitPool[kit.Low and "Low" or "High"]
	if #pool < K.ARRIVE_POOL then
		pcall(function()
			kit.Folder.Parent = nil
		end)
		pool[#pool + 1] = kit
	else
		pcall(function()
			kit.Folder:Destroy()
		end)
	end
end

local function arriveFlash(play)
	if play.Flashed then
		return
	end
	play.Flashed = true
	play.Handle.Flashed = true
	if play.Kit and play.Kit.Emitter then
		play.Kit.Emitter:Emit(K.ARRIVE_SPARKLES)
	end
	if type(play.OnFlash) == "function" then
		local ok, err = pcall(play.OnFlash)
		if not ok then
			warn("[EvolutionFx] OnFlash failed: " .. tostring(err))
		end
	end
end

local function arriveFinish(play)
	if play.Handle.Done then
		return
	end
	arriveFlash(play) -- (a Stop before the flash still shows the pet)
	play.Handle.Done = true
	if play.Kit then
		giveKit(play.Kit)
		play.Kit = nil
	end
	for i = #arrivals, 1, -1 do
		if arrivals[i] == play then
			table.remove(arrivals, i)
		end
	end
	maybeStopLoop()
	if type(play.OnDone) == "function" then
		local ok, err = pcall(play.OnDone)
		if not ok then
			warn("[EvolutionFx] OnDone failed: " .. tostring(err))
		end
	end
end

-- per frame: one arrival (reused buffers: no table per frame)
local function arriveStep(play, dt)
	play.T = play.T + dt
	local t, D, F = play.T, play.Dur, play.FlashAt
	local kit = play.Kit
	local R, u = play.Radius, play.Unit
	local centre = play.Pose.Position
	local bp, bc = kit.BufP, kit.BufC
	if t >= F then
		arriveFlash(play)
	end
	-- the rune ring: grows and turns, fades out at the end
	local n = #kit.Runes
	if n > 0 then
		local grow = smooth(t / (0.3 * D))
		local fade = clamp01((t - 0.65 * D) / (0.35 * D))
		local alpha = 1 - (1 - fade) * 0.9 * smooth(t / (0.25 * D))
		for i, part in ipairs(kit.Runes) do
			bp[i] = part
			bc[i] = ringPose(play, i, n, R * (0.5 + 0.8 * grow), t * 1.6, 0.06)
			part.Transparency = alpha
		end
		for i = n + 1, #bp do
			bp[i], bc[i] = nil, nil
		end
		Workspace:BulkMoveTo(bp, bc, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- the pillar rises until the flash, flares, then fades
	local pillar = kit.Pillar
	if pillar then
		local rise = easeOut(clamp01((t - 0.04 * D) / (F - 0.04 * D)))
		local after = clamp01((t - F) / (0.3 * D))
		local h = math.max(0.1, play.PillarHeight * rise)
		local w = R * (0.9 + 0.6 * after)
		pillar.Size = Vector3.new(h, w, w)
		pillar.CFrame = CFrame.new(centre.X, play.Ground + h / 2, centre.Z) * CFrame.Angles(0, 0, math.pi / 2)
		pillar.Transparency = (t < F) and (1 - 0.45 * rise) or (0.55 + 0.45 * after)
		kit.Light.Brightness = (t < F) and (4 * rise) or (4 * (1 - after))
	end
	-- the white flash
	local fp = (t - (F - 0.06 * D)) / (0.32 * D)
	if fp > 0 and fp < 1 then
		local fs = (R * 0.5 + R * 2.1 * easeOut(fp)) * 2
		kit.Flash.Size = Vector3.new(fs, fs, fs)
		kit.Flash.CFrame = CFrame.new(centre)
		kit.Flash.Transparency = 0.12 + 0.88 * smooth(fp)
	else
		kit.Flash.Transparency = 1
	end
	-- the shock ring and the sparks (from the flash on)
	if t >= F then
		local q = t - F
		local sp = clamp01(q / (0.45 * D))
		local m = #kit.Shock
		for i, part in ipairs(kit.Shock) do
			bp[i] = part
			bc[i] = ringPose(play, i, m, R * (0.6 + 2.6 * easeOut(sp)), 0, 0.12)
			part.Transparency = (sp < 1) and (0.1 + 0.9 * sp) or 1
		end
		for i = m + 1, #bp do
			bp[i], bc[i] = nil, nil
		end
		Workspace:BulkMoveTo(bp, bc, Enum.BulkMoveMode.FireCFrameChanged)
		local k = #kit.Sparks
		if k > 0 then
			local fade = clamp01(q / (D - F))
			for i, part in ipairs(kit.Sparks) do
				local pos = centre + kit.SparkV[i] * q + Vector3.new(0, -13 * q * q, 0)
				if pos.Y < play.Ground + u * 0.2 then
					pos = Vector3.new(pos.X, play.Ground + u * 0.2, pos.Z)
				end
				local spin = kit.SparkSpin[i]
				bp[i] = part
				bc[i] = CFrame.new(pos) * CFrame.Angles(spin.X * q, spin.Y * q, spin.Z * q)
				part.Transparency = fade
			end
			for i = k + 1, #bp do
				bp[i], bc[i] = nil, nil
			end
			Workspace:BulkMoveTo(bp, bc, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	play.Handle.T = t
	if t >= D then
		arriveFinish(play)
	end
end

local function wantLow(opts)
	if opts.Quality == "Low" or opts.Quality == "High" then
		return opts.Quality == "Low"
	end
	if quality == nil then
		quality = false
		local client = script.Parent and script.Parent.Parent
		local mod = client and client:FindFirstChild("GraphicsQuality")
		if mod then
			local ok, result = pcall(require, mod)
			if ok and type(result) == "table" and type(result.Effective) == "function" then
				quality = result
			end
		end
	end
	if quality then
		local ok, mode = pcall(quality.Effective)
		return ok and mode == "Low"
	end
	return false
end

function EvolutionFx.Arrive(pivot, opts)
	opts = type(opts) == "table" and opts or {}
	local D = (type(opts.Seconds) == "number" and opts.Seconds > 0.2) and math.min(opts.Seconds, 4) or K.ARRIVE_SECONDS
	local handle = { Done = false, Flashed = false, Low = false, FlashAt = D * K.ARRIVE_FLASH, T = 0 }
	local play = { Handle = handle, OnFlash = opts.OnFlash, OnDone = opts.OnDone }
	handle.Stop = function()
		pcall(arriveFinish, play)
	end
	if typeof(pivot) ~= "CFrame" then
		handle.Stop()
		return handle
	end
	local high, low = 0, 0
	for _, a in ipairs(arrivals) do
		if a.Low then
			low = low + 1
		else
			high = high + 1
		end
	end
	local isLow = wantLow(opts) or high >= K.ARRIVE_MAX
	if isLow and low >= K.ARRIVE_MAX_LOW then
		handle.Stop() -- too many at once: no effect, the pet just appears
		return handle
	end
	local colors = type(opts.Colors) == "table" and opts.Colors or {}
	local H = (type(opts.Height) == "number" and opts.Height > 0) and opts.Height or 3.5
	local R = (type(opts.Radius) == "number" and opts.Radius > 0) and opts.Radius or 1.8
	play.Low = isLow
	play.Pose = pivot
	play.Dur = D
	play.FlashAt = handle.FlashAt
	play.Height = math.max(1, H)
	play.Radius = math.max(0.8, R)
	play.Unit = math.max(0.5, math.min(play.Radius, play.Height) * 0.22)
	play.Ground = (type(opts.Ground) == "number") and opts.Ground or (pivot.Position.Y - play.Height / 2)
	play.PillarHeight = math.min(28, play.Height * 6)
	play.Colors = {
		typeof(colors[1]) == "Color3" and colors[1] or Color3.fromRGB(255, 214, 90),
		typeof(colors[2]) == "Color3" and colors[2] or Color3.fromRGB(120, 200, 255),
	}
	play.Salt = (#arrivals + 1) * 0.37 + (pivot.Position.X + pivot.Position.Z) * 0.01
	play.T = 0
	handle.Low = isLow
	local parent = (typeof(opts.Parent) == "Instance") and opts.Parent or Workspace
	play.Kit = takeKit(isLow, parent)
	dressKit(play.Kit, play)
	arrivals[#arrivals + 1] = play
	ensureLoop()
	return handle
end

function EvolutionFx.ArriveStats()
	local out = { Live = 0, LiveLow = 0, Pooled = #kitPool.High + #kitPool.Low, Parts = 0 }
	for _, a in ipairs(arrivals) do
		if a.Low then
			out.LiveLow = out.LiveLow + 1
		else
			out.Live = out.Live + 1
		end
		if a.Kit then
			out.Parts = out.Parts + kitCount(a.Kit)
		end
	end
	return out
end

onFrame = function(dt)
	dt = math.min(dt, 0.1)
	for i = #plays, 1, -1 do
		local play = plays[i]
		if play then
			local ok, err = pcall(step, play, dt)
			if not ok then
				warn("[EvolutionFx] " .. tostring(err))
				pcall(finish, play)
			end
		end
	end
	for i = #arrivals, 1, -1 do
		local play = arrivals[i]
		if play then
			local ok, err = pcall(arriveStep, play, dt)
			if not ok then
				warn("[EvolutionFx] arrive: " .. tostring(err))
				pcall(arriveFinish, play)
			end
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function EvolutionFx.Duration(stage)
	return K.CHARGE[(stage == 2) and 2 or 1] + K.BURST + K.REVEAL + K.SETTLE
end

function EvolutionFx.Count()
	return #plays
end

function EvolutionFx.Play(fromModel, toModel, pose, opts)
	opts = type(opts) == "table" and opts or {}
	local handle = { Done = false, Model = fromModel, T = 0 }
	local from = (typeof(fromModel) == "Instance") and rigOf(fromModel) or nil
	local to = (typeof(toModel) == "Instance") and rigOf(toModel) or nil
	if not (from and to) or typeof(pose) ~= "CFrame" then
		warn("[EvolutionFx] Play needs two PetBuilder models and a CFrame")
		handle.Done = true
		handle.Stop = function() end
		return handle
	end
	local stage = (opts.Stage == 2) and 2 or 1
	local colors = type(opts.Colors) == "table" and opts.Colors or {}
	local parent = (typeof(opts.Parent) == "Instance") and opts.Parent or Workspace
	local height, radius, low = measure(to)
	local play = {
		Handle = handle,
		From = from,
		To = to,
		Pose = pose,
		Stage = stage,
		Colors = {
			typeof(colors[1]) == "Color3" and colors[1] or Color3.fromRGB(255, 214, 90),
			typeof(colors[2]) == "Color3" and colors[2] or Color3.fromRGB(120, 200, 255),
		},
		Parent = parent,
		Charge = K.CHARGE[stage],
		Height = math.max(1, height),
		Radius = math.max(0.8, radius),
		Ground = (type(opts.Ground) == "number") and opts.Ground or (pose.Position.Y + low - 0.5),
		OnDone = opts.OnDone,
		ConfettiOn = opts.Confetti == true,
		T = 0,
		Yaw = 0,
	}
	local folder = Instance.new("Folder")
	folder.Name = "EvolutionFx"
	folder.Parent = parent
	play.Folder = folder
	toModel.Parent = nil
	poseRig(from, pose, 1)
	buildEffects(play)
	handle.Stop = function()
		pcall(finish, play)
	end
	plays[#plays + 1] = play
	ensureLoop()
	return handle
end

return EvolutionFx
