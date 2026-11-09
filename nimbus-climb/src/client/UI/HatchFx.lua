-- HatchFx (client UI; lobby-shop Tasks 26 / 27, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.5 "Where the
-- VFX show" and 16.4 "VFX and budget"): the egg cutscene's effects, all GUI frames, tweens and one pooled spark system,
-- plus the one Lighting effect of the cutscene. A pool owns at most n spark frames (made only when first needed, reused
-- after) and one Heartbeat that runs only while a spark lives, unless its owner drives it (Drive: the egg stage steps
-- it from its own phase Heartbeat, so the cutscene has exactly one); nothing else here runs per frame.
--
--   HatchFx.Pool(parent, n [, z, opts]) -> pool   a holder Frame "Sparks" over the parent (n defaults to 16); opts.Image
--     (roll-look review round 1: the hatch_sparkle "rbxassetid://" id, spec 16.15 "Fallbacks"): the sparks are ImageLabels
--     tinted their colour (1.6 x the square's size, unturned) instead of 45-degree squares; the confetti stays squares;
--     never more than n objects of both kinds
--     pool:Burst(at, rarity, count [, opts]) -> spawned   sparks flying out of `at` (a Vector2 in the parent's px) and
--       fading in 0.55-0.9 s (opts.Life / opts.Speed / opts.Px ranges override: the shakes' small pops); never more
--       than n live at once; halved on Low graphics
--     pool:Confetti(n, rarity) -> spawned   n squares falling from the holder's top for 1.5 s, turning and swaying (the
--       Mythic / Secret reveal); halved on Low graphics; frames named "Confetti" while they fall
--     pool:Ambient(target, rarity [, count, mode])   sparkles round a GuiObject (an egg): Rare 3, Legendary 4, Mythic 6
--       drifting up and fading (mode "Drift"), Secret 2 orbiting star sparks ("Orbit"); none below Rare (Epic: 3) and
--       none on Low. They last until the target is destroyed, SetRunning(false) or Destroy
--     pool:SetRunning(on)   off: every spark back in the pool, the Heartbeat off (the ambient waits); on: it resumes
--     pool:Drive()   the owner calls pool:Step(dt) from its own Heartbeat; the pool never connects one
--     pool:Live() -> the sparks alive now;  pool:Destroy()   the frames and the Heartbeat gone
--   HatchFx.Rays(parent, rarity [, opts]) -> rays   a CanvasGroup "Rays" of 16 thin wedges (8 bars through the centre,
--     clear in the middle; opts.Image, the hatch_rays id: one ImageLabel "Fan" in their box, tinted, instead):
--     rays:Place(x, y, d), rays:Flash(alpha, seconds) (fade in, then rest at `alpha`), rays:Recolor(rarity),
--     rays:Spin(on) (an endless Rotation tween, 12 s a turn; still on Low), rays:Hide(), rays:Destroy()
--   HatchFx.Shock(parent, rarity [, opts]) -> shock   a round Frame "Shock" with a 6 px UIStroke: shock:Play(x, y, d,
--     seconds, color) grows it 0 -> d while its stroke fades, then hides it; shock:Hide(), shock:Destroy()
--   HatchFx.Cracks(egg, rarity, step) -> Frame "Cracks" on the egg: 6 thin rotated glowing frames (Seg1..5 of the
--     zigzag, step 1, 3 or 5 of them shown, and a Branch at 5) in shares of the egg, so they follow its size, shakes and
--     scale
--   HatchFx.Leaks(egg, rarity, step) -> Frame "Leaks" on the egg: up to 5 tapered beams of light (Leak1..5) from the
--     crack's corners, as many and as long as the step
--   HatchFx.CloudRing(parent, color [, opts]) -> ring   (the owner's pick: Gemini's cloud ring) a CanvasGroup
--     "CloudRing" of 10 round cloud puffs with a UIScale "Swell": ring:Place(x, y, d), ring:Show(seconds), ring:Spin(on)
--     (an endless Rotation tween, 24 s a turn; still on Low), ring:Pulse(color, seconds) (tinted the rarity colour at
--     once, swells sharply to 1.45 and fades: the burst), ring:Tint(color, seconds) (roll-look, spec 16.15: Gemini's shake
--     tweak, GroupColor3 tweened half way from its pale tint to `color`; 0 s at once; the burst's Pulse ends it),
--     ring:Hide(), ring:Destroy()
--   HatchFx.Stars(parent, n) -> { Frame, Destroy }   a Frame "Stars" with n small stars, each twinkling (an endless,
--     offset alpha tween); Destroy stops the tweens and removes the frame
--   HatchFx.Dim(on [, seconds]) -> effects   High graphics only: on = the client-only Lighting.NimbusHatchBlur
--     (BlurEffect, ours by name, 0 -> 14) and the cool tint pushed as the LightingStack preset "Hatch" (Brightness
--     -0.08, Saturation -0.25 against LightingStack.Value without "Hatch"; no ColorCorrectionEffect of our own: the
--     LightingStack is the only client writer of Lighting); off = the blur destroyed and the preset popped. -> how many
--     of the two are on now
--   HatchFx.Stats() -> { Live, Pooled, Tweens, Heartbeats, Effects }   (tests) every pool's live sparks and frames, the
--     tweens playing that HatchFx made (stars, rays, rings, shocks, the blur), the pools whose Heartbeat is connected
--     and the Lighting effects on (Dim)
--   opts.Track (Rays / Shock / CloudRing): a weak-keyed table that also gets every tween the handle plays (the egg
--     stage counts and cancels them with its own)
--
-- Positions: the holder's local px are the screen px divided by the UIScale(s) above it (UIScale shrinks the design
-- canvas on a phone). Plain Lua 5.1-compatible syntax only.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local HatchFx = {}

local K = {
	N = 16,
	BURST_LIFE = { 0.55, 0.9 },
	BURST_SPEED = { 140, 260 }, -- px / s
	DRAG = 2.4, -- the burst's speed falls by this share a second
	FALL = 70, -- px / s / s
	DRIFT_LIFE = { 1.6, 2.4 },
	DRIFT_RISE = 0.12, -- egg heights a second
	DRIFT_GAP = 0.3, -- s between two ambient spawns
	ORBIT_PERIOD = 4,
	AMBIENT = { Rare = { 3, "Drift" }, Epic = { 3, "Drift" }, Legendary = { 4, "Drift" }, Mythic = { 6, "Drift" }, Secret = { 2, "Orbit" } },
	COLORS = {
		Common = { Color3.fromRGB(255, 255, 255) },
		Uncommon = { Color3.fromRGB(214, 255, 190) },
		Rare = { Color3.fromRGB(170, 214, 255) },
		Epic = { Color3.fromRGB(255, 226, 140), Color3.fromRGB(232, 204, 255) },
		Legendary = { Color3.fromRGB(255, 222, 110), Color3.fromRGB(255, 244, 200) },
		Mythic = { Color3.fromRGB(255, 200, 230), Color3.fromRGB(200, 240, 255), Color3.fromRGB(222, 202, 255), Color3.fromRGB(200, 255, 232) },
		Secret = { Color3.fromRGB(255, 248, 220), Color3.fromRGB(196, 170, 255) },
	},
	CONFETTI_LIFE = 1.5,
	CONFETTI_FALL = { 150, 260 }, -- px / s
	CONFETTI = {
		Mythic = { Color3.fromRGB(255, 176, 214), Color3.fromRGB(170, 232, 255), Color3.fromRGB(214, 190, 255), Color3.fromRGB(176, 255, 220), Color3.fromRGB(255, 236, 160) },
		Secret = { Color3.fromRGB(180, 150, 255), Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 248, 230), Color3.fromRGB(120, 92, 220) },
	},
	RAY_TURN = 12, -- s a turn
	RING_TURN = 24,
	RING_PUFFS = 10,
	RING_R = 0.4, -- (roll-look) the puffs' circle, a share of the ring's size (inside the CanvasGroup: it clips); their
	-- sizes (big, small) and transparencies
	RING_PUFF = { 0.14, 0.095 },
	RING_PUFF_A = { 0.55, 0.66 },
	RING_REST = 0.2, -- the ring's transparency at rest
	RING_TINT = Color3.fromRGB(226, 234, 255),
	SWELL = 1.45,
	BLUR = 14,
	TINT = { Brightness = -0.08, Saturation = -0.25 },
	-- the crack's zigzag (shares of the egg's width / height, the pitch's points) and which segments each step shows
	ZIG = { { 0.12, 0.58 }, { 0.24, 0.66 }, { 0.34, 0.55 }, { 0.45, 0.67 }, { 0.55, 0.56 }, { 0.66, 0.66 }, { 0.76, 0.55 }, { 0.88, 0.62 } },
	SEGS = { [1] = { 4 }, [3] = { 3, 4, 5 }, [5] = { 2, 3, 4, 5, 6 } },
	BRANCH = { 0.45, 0.67, 0.42, 0.8 },
	CRACK_W = 0.028, -- a segment's thickness, a share of the egg's height
}
HatchFx.Metrics = K

-- every pool (weak keys), every tween HatchFx plays (weak keys: the stars, the handles' tweens) and the Dim state
local R = {
	Pools = setmetatable({}, { __mode = "k" }), Stars = setmetatable({}, { __mode = "k" }), GQ = nil, Rng = Random.new(26),
	Blur = nil, BlurTween = nil, Pushed = false, LS = nil,
}

local function high()
	if R.GQ == nil then
		R.GQ = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				R.GQ = mod
			end
		end
	end
	if not R.GQ then
		return true
	end
	local ok, mode = pcall(R.GQ.Effective)
	return not ok or mode ~= "Low"
end

local function between(range)
	return range[1] + (range[2] - range[1]) * R.Rng:NextNumber()
end

-- one tween HatchFx plays: counted by Stats (and by opts.Track's owner)
local function play(inst, info, goals, track)
	local tw = TweenService:Create(inst, info, goals)
	R.Stars[tw] = true
	if type(track) == "table" then
		track[tw] = true
	end
	tw:Play()
	return tw
end

local function cancel(tw)
	if tw then
		pcall(function()
			tw:Cancel()
		end)
		R.Stars[tw] = nil
	end
end

local function lighter(color, k)
	return color:Lerp(Color3.new(1, 1, 1), k)
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function colorOf(rarity, i)
	local list = K.COLORS[rarity] or K.COLORS.Common
	return list[((i or 1) - 1) % #list + 1]
end

-- the product of the UIScale(s) on the holder's ancestors (1 when none)
local function scaleOf(inst)
	local s, cur = 1, inst
	while cur and cur:IsA("GuiBase2d") do
		local ui = cur:FindFirstChildOfClass("UIScale")
		if ui then
			s = s * ui.Scale
		end
		cur = cur.Parent
	end
	return (s > 0) and s or 1
end

local Pool = {}
Pool.__index = Pool

-- a spark object: a 45-degree square Frame, or (img: the pool's hatch_sparkle image, roll-look review round 1) an
-- ImageLabel tinted the spark colour. Never more than N of both kinds: when the pool is full a spare of the other kind
-- makes room (the confetti stays paper squares after a burst of image sparks)
function Pool:_frame(img)
	local f = table.remove(img and self.FreeImg or self.Free)
	if f then
		return f
	end
	if not self.Holder then
		return nil
	end
	if self.Made >= self.N then
		local spare = table.remove(img and self.Free or self.FreeImg)
		if not spare then
			return nil
		end
		spare:Destroy()
		self.Made = self.Made - 1
	end
	self.Made = self.Made + 1
	if img then
		f = Instance.new("ImageLabel")
		f.Image = self.Image
		f.BackgroundTransparency = 1
		f.ImageTransparency = 1
	else
		f = Instance.new("Frame")
	end
	f.Name = "Spark"
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = 45
	f.ZIndex = self.Z
	f.Visible = false
	f.Parent = self.Holder
	return f
end

function Pool:_spawn(rec)
	local img = self.Image ~= nil and rec.Name ~= "Confetti"
	local f = self:_frame(img)
	if not f then
		return false
	end
	rec.F = f
	rec.Age = 0
	-- the property the fade writes each frame (rec.AP), set once here: no class test per frame
	rec.AP = img and "ImageTransparency" or "BackgroundTransparency"
	f.Name = rec.Name or "Spark"
	f.Rotation = rec.Rot or (img and 0 or 45)
	if img then
		f.ImageColor3 = rec.Color
	else
		f.BackgroundColor3 = rec.Color
	end
	-- (an image sparkle is drawn inside its box: a little larger than the square it replaces)
	local k = img and 1.6 or 1
	f.Size = UDim2.fromOffset(rec.Px * k, (rec.Py or rec.Px) * k)
	f[rec.AP] = 1
	f.Position = UDim2.fromOffset(rec.X, rec.Y)
	f.Visible = true
	self.List[#self.List + 1] = rec
	return true
end

function Pool:_free(i)
	local rec = self.List[i]
	self.List[i] = self.List[#self.List]
	self.List[#self.List] = nil
	if rec.Amb then
		rec.Amb.Live = rec.Amb.Live - 1
	end
	if rec.F and rec.F.Parent then
		rec.F.Visible = false
		rec.F.Name = "Spark"
		local list = (rec.AP == "ImageTransparency") and self.FreeImg or self.Free
		list[#list + 1] = rec.F
	end
end

-- connects the Heartbeat when something should run, drops it when nothing does (never for a driven pool)
function Pool:_sync()
	local want = not self.Manual and self.Running and self.Holder ~= nil and (#self.List > 0 or (next(self.Amb) ~= nil and high()))
	if want and not self.Conn then
		self.Conn = RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	elseif not want and self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
end

-- a target's centre and height in the holder's px
function Pool:_where(target, scale)
	local hp = self.Holder.AbsolutePosition
	local p, s = target.AbsolutePosition, target.AbsoluteSize
	return (p.X + s.X / 2 - hp.X) / scale, (p.Y + s.Y / 2 - hp.Y) / scale, s.Y / scale
end

function Pool:_step(dt)
	if not self.Holder or not self.Holder.Parent then
		self:Destroy()
		return
	end
	self.T = self.T + dt
	local hi = high()
	local scale = scaleOf(self.Holder)
	-- the ambient: top each target's sparkles up (one every DRIFT_GAP; the orbit sparks all at once)
	if hi then
		for target, a in pairs(self.Amb) do
			if a.Live < a.Count and self.T >= a.Next and target.Parent then
				local cx, cy, h = self:_where(target, scale)
				a.Next = self.T + ((a.Mode == "Orbit") and 0 or K.DRIFT_GAP)
				a.N = a.N + 1
				local rec = { Amb = a, Target = target, Color = colorOf(a.Rarity, a.N), Mode = a.Mode, X = cx, Y = cy }
				if a.Mode == "Orbit" then
					rec.Phase = (a.N - 1) * (2 * math.pi / a.Count)
					rec.Px = math.clamp(math.floor(h * 0.07 + 0.5), 5, 14)
					rec.Life = math.huge
				else
					local ang = R.Rng:NextNumber() * 2 * math.pi
					local u = 0.75 + 0.25 * R.Rng:NextNumber()
					rec.Ox, rec.Oy = math.cos(ang) * 0.55 * u, math.sin(ang) * 0.62 * u -- in egg heights from the centre
					rec.Vx = (R.Rng:NextNumber() - 0.5) * 0.1
					rec.Px = math.clamp(math.floor(h * (0.045 + 0.025 * R.Rng:NextNumber()) + 0.5), 4, 12)
					rec.Life = between(K.DRIFT_LIFE)
				end
				if self:_spawn(rec) then
					a.Live = a.Live + 1
				end
			end
		end
	end
	-- every live spark
	for i = #self.List, 1, -1 do
		local rec = self.List[i]
		rec.Age = rec.Age + dt
		local f = rec.F
		local gone = rec.Age >= rec.Life or not f or not f.Parent
		if rec.Amb and not gone then
			local target = rec.Target
			gone = not hi or not target.Parent or not self.Amb[target] -- Low graphics: the ambient sparks go at once
			if not gone then
				local cx, cy, h = self:_where(target, scale)
				if rec.Mode == "Orbit" then
					local th = rec.Phase + self.T * 2 * math.pi / K.ORBIT_PERIOD
					f.Position = UDim2.fromOffset(cx + math.cos(th) * 0.6 * h, cy + math.sin(th) * 0.66 * h)
					f[rec.AP] = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(self.T * 5 + rec.Phase))
				else
					local k = rec.Age / rec.Life
					f.Position = UDim2.fromOffset(cx + (rec.Ox + rec.Vx * rec.Age) * h, cy + (rec.Oy - K.DRIFT_RISE * rec.Age) * h)
					local fade = (k < 0.25) and (k / 0.25) or ((k > 0.65) and ((1 - k) / 0.35) or 1)
					f[rec.AP] = 1 - 0.85 * math.max(0, fade)
				end
			end
		elseif not gone and rec.Name == "Confetti" then
			-- confetti: falling, swaying, turning; it fades over its last 0.35 s
			rec.Vy = rec.Vy + K.FALL * 0.5 * dt
			rec.X = rec.X + (rec.Vx + math.sin(rec.Age * rec.Sway + rec.Phase) * 40) * dt
			rec.Y = rec.Y + rec.Vy * dt
			rec.Rot = rec.Rot + rec.Spin * dt
			f.Position = UDim2.fromOffset(rec.X, rec.Y)
			f.Rotation = rec.Rot
			local left = rec.Life - rec.Age
			f[rec.AP] = (left < 0.35) and (1 - left / 0.35 * 0.9) or 0.1
		elseif not gone then
			-- a burst spark: out, slowing, falling a little, fading
			rec.Vx = rec.Vx * math.max(0, 1 - K.DRAG * dt)
			rec.Vy = rec.Vy * math.max(0, 1 - K.DRAG * dt) + K.FALL * dt
			rec.X, rec.Y = rec.X + rec.Vx * dt, rec.Y + rec.Vy * dt
			f.Position = UDim2.fromOffset(rec.X, rec.Y)
			f[rec.AP] = 0.1 + 0.9 * (rec.Age / rec.Life)
		end
		if gone then
			self:_free(i)
		end
	end
	self:_sync()
end

function Pool:Burst(at, rarity, count, opts)
	if not self.Holder or not self.Running then
		return 0
	end
	opts = type(opts) == "table" and opts or {}
	count = math.max(0, math.floor(tonumber(count) or 0))
	if not high() then
		count = math.floor(count / 2)
	end
	local px = opts.Px or { 6, 10 }
	local spawned = 0
	for i = 1, count do
		local ang = R.Rng:NextNumber() * 2 * math.pi
		local speed = between(opts.Speed or K.BURST_SPEED)
		local rec = {
			Color = colorOf(rarity, i),
			X = at.X,
			Y = at.Y,
			Vx = math.cos(ang) * speed,
			Vy = math.sin(ang) * speed,
			Px = math.floor(between(px) + 0.5),
			Life = between(opts.Life or K.BURST_LIFE),
		}
		if not self:_spawn(rec) then
			break
		end
		spawned = spawned + 1
	end
	self:_sync()
	return spawned
end

-- confetti from the holder's top edge, across its width (Mythic / Secret)
function Pool:Confetti(n, rarity)
	if not self.Holder or not self.Running then
		return 0
	end
	n = math.max(0, math.floor(tonumber(n) or 0))
	if not high() then
		n = math.floor(n / 2)
	end
	local scale = scaleOf(self.Holder)
	local w = self.Holder.AbsoluteSize.X / scale
	local list = K.CONFETTI[rarity] or K.COLORS[rarity] or K.COLORS.Common
	local spawned = 0
	for i = 1, n do
		local size = 8 + math.floor(R.Rng:NextNumber() * 6)
		local rec = {
			Name = "Confetti",
			Color = list[(i - 1) % #list + 1],
			X = w * (0.06 + 0.88 * ((i * 0.618034) % 1)),
			Y = -12 - R.Rng:NextNumber() * 60,
			Vx = (R.Rng:NextNumber() - 0.5) * 40,
			Vy = between(K.CONFETTI_FALL),
			Px = size,
			Py = math.floor(size * 0.6 + 0.5),
			Rot = R.Rng:NextNumber() * 360,
			Spin = (R.Rng:NextNumber() - 0.5) * 540,
			Sway = 2 + R.Rng:NextNumber() * 3,
			Phase = R.Rng:NextNumber() * 6.28,
			Life = K.CONFETTI_LIFE,
		}
		if not self:_spawn(rec) then
			break
		end
		spawned = spawned + 1
	end
	self:_sync()
	return spawned
end

-- the owner steps this pool from its own Heartbeat (Step); the pool never connects one
function Pool:Drive()
	self.Manual = true
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
end

function Pool:Step(dt)
	if self.Holder and self.Running and (#self.List > 0 or next(self.Amb) ~= nil) then
		self:_step(dt)
	end
end

function Pool:Ambient(target, rarity, count, mode)
	local def = K.AMBIENT[rarity]
	if not self.Holder or typeof(target) ~= "Instance" or not def then
		return
	end
	local old = self.Amb[target]
	if old and old.Conn then
		old.Conn:Disconnect()
	end
	local a = { Rarity = rarity, Count = count or def[1], Mode = mode or def[2], Live = 0, Next = self.T, N = 0 }
	a.Conn = target.Destroying:Connect(function()
		self:StopAmbient(target)
	end)
	self.Amb[target] = a
	self:_sync()
end

-- the target's sparkles back in the pool and its ambient forgotten
function Pool:StopAmbient(target)
	local a = self.Amb[target]
	if not a then
		return
	end
	self.Amb[target] = nil
	if a.Conn then
		a.Conn:Disconnect()
	end
	for i = #self.List, 1, -1 do
		if self.List[i].Amb == a then
			self:_free(i)
		end
	end
	self:_sync()
end

function Pool:SetRunning(on)
	on = on and true or false
	if not on then
		for i = #self.List, 1, -1 do
			self:_free(i)
		end
		for _, a in pairs(self.Amb) do
			a.Live, a.Next = 0, 0
		end
	else
		for _, a in pairs(self.Amb) do
			a.Next = self.T
		end
	end
	self.Running = on
	self:_sync()
end

function Pool:Live()
	return #self.List
end

function Pool:Destroy()
	for target in pairs(self.Amb) do
		local a = self.Amb[target]
		if a.Conn then
			a.Conn:Disconnect()
		end
	end
	self.Amb = {}
	self.List = {}
	self.Free = {}
	self.FreeImg = {}
	self.Running = false
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	if self.Holder then
		self.Holder:Destroy()
		self.Holder = nil
	end
	R.Pools[self] = nil
end

function HatchFx.Pool(parent, n, z, opts)
	opts = type(opts) == "table" and opts or {}
	local holder = Instance.new("Frame")
	holder.Name = "Sparks"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z or 20
	holder.Parent = parent
	local pool = setmetatable({
		Holder = holder,
		N = math.max(1, math.floor(tonumber(n) or K.N)),
		Z = z or 20,
		Made = 0,
		Free = {},
		FreeImg = {},
		Image = type(opts.Image) == "string" and opts.Image or nil,
		List = {},
		Amb = {},
		Running = true,
		T = 0,
		Conn = nil,
	}, Pool)
	R.Pools[pool] = true
	return pool
end

-- n small stars over the parent (deterministic spots), each twinkling on its own offset loop
function HatchFx.Stars(parent, n)
	local holder = Instance.new("Frame")
	holder.Name = "Stars"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent
	local tweens = {}
	n = math.max(0, math.floor(tonumber(n) or 0))
	for i = 1, n do
		local s = Instance.new("Frame")
		s.Name = "Star" .. i
		s.BorderSizePixel = 0
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Rotation = 45
		s.BackgroundColor3 = Color3.fromRGB(255, 248, 220)
		s.BackgroundTransparency = 0.2
		-- golden-ratio spots: spread without a pattern the eye picks up
		local x, y = (i * 0.618034) % 1, (i * 0.381966 + 0.13) % 1
		s.Position = UDim2.fromScale(0.04 + 0.92 * x, 0.06 + 0.88 * y)
		local px = 3 + (i % 3) * 2
		s.Size = UDim2.fromOffset(px, px)
		s.Parent = holder
		local info = TweenInfo.new(0.8 + (i % 5) * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i * 0.37) % 1.5)
		local tw = TweenService:Create(s, info, { BackgroundTransparency = 0.85 })
		R.Stars[tw] = true
		tweens[#tweens + 1] = tw
		tw:Play()
	end
	local function destroy()
		for _, tw in ipairs(tweens) do
			tw:Cancel()
			R.Stars[tw] = nil
		end
		tweens = {}
		holder:Destroy()
	end
	holder.Destroying:Connect(function()
		for _, tw in ipairs(tweens) do
			tw:Cancel()
			R.Stars[tw] = nil
		end
	end)
	return { Frame = holder, Destroy = destroy }
end

----------------------------------------------------------------------------------------------------
-- the burst's rays, the shock ring, the cloud ring (handles); the cracks and leaks on an egg
----------------------------------------------------------------------------------------------------
-- an object a handle places by its centre and diameter (in the parent's px)
local function placeAt(o, x, y, d)
	o.Position = UDim2.fromOffset(x, y)
	o.Size = UDim2.fromOffset(math.max(0, d), math.max(0, d))
end

local Handle = {}
Handle.__index = Handle

function Handle:Place(x, y, d)
	if self.Frame and self.Frame.Parent then
		placeAt(self.Frame, x, y, d)
	end
end

function Handle:_play(key, inst, info, goals)
	cancel(self.Tw[key])
	self.Tw[key] = (inst and inst.Parent) and play(inst, info, goals, self.Track) or nil
	return self.Tw[key]
end

function Handle:Spin(on)
	if on and high() and self.Frame and self.Frame.Parent then
		if not (self.Tw.Spin and self.Tw.Spin.PlaybackState == Enum.PlaybackState.Playing) then
			self.Frame.Rotation = self.Frame.Rotation % 360
			local from = self.Frame.Rotation
			self:_play("Spin", self.Frame, TweenInfo.new(self.Turn, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = from + 360 })
		end
	else
		cancel(self.Tw.Spin)
		self.Tw.Spin = nil
	end
end

function Handle:Hide()
	for key, tw in pairs(self.Tw) do
		cancel(tw)
		self.Tw[key] = nil
	end
	if self.Frame and self.Frame.Parent then
		self.Frame.Visible = false
	end
end

function Handle:Destroy()
	self:Hide()
	if self.Frame then
		self.Frame:Destroy()
		self.Frame = nil
	end
end

local function handle(frame, turn, opts)
	return setmetatable({ Frame = frame, Tw = {}, Turn = turn or 12, Track = type(opts) == "table" and opts.Track or nil }, Handle)
end

-- the light colour of a rarity's effects (Legendary and up: gold)
local function rayColor(rarity)
	local gold = { Legendary = true, Mythic = true, Secret = true }
	if gold[rarity] then
		return Color3.fromRGB(255, 214, 120)
	end
	-- the tier's own pale tone (the last spark colour: Epic's lilac, not its gold trim)
	local list = K.COLORS[rarity] or K.COLORS.Common
	return lighter(list[#list], 0.1)
end

function HatchFx.Rays(parent, rarity, opts)
	opts = type(opts) == "table" and opts or {}
	local holder = new("CanvasGroup", {
		Name = "Rays", BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), GroupTransparency = 1,
		Visible = false, ZIndex = opts.ZIndex or 1,
	}, parent)
	local color = rayColor(rarity)
	if type(opts.Image) == "string" then
		-- (roll-look review round 1, spec 16.15 "Fallbacks") the hatch_rays fan: one ImageLabel in the wedges' box, tinted
		new("ImageLabel", {
			Name = "Fan", Image = opts.Image, ImageColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = holder.ZIndex,
		}, holder)
	else
		-- each bar is two opposite rays: clear at the centre (the egg / pet reads through), bright mid-way, gone at the ends
		local fade = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.16, 0.55), NumberSequenceKeypoint.new(0.36, 0.2),
			NumberSequenceKeypoint.new(0.47, 1), NumberSequenceKeypoint.new(0.53, 1), NumberSequenceKeypoint.new(0.64, 0.2),
			NumberSequenceKeypoint.new(0.84, 0.55), NumberSequenceKeypoint.new(1, 1),
		})
		for i = 1, 8 do
			local bar = new("Frame", {
				Name = "Ray" .. i, BorderSizePixel = 0, BackgroundColor3 = color, BackgroundTransparency = 0, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, (i % 2 == 0) and 0.022 or 0.034), Rotation = (i - 1) * 22.5,
				ZIndex = holder.ZIndex,
			}, holder)
			new("UIGradient", { Name = "Fade", Transparency = fade }, bar)
		end
	end
	local h = handle(holder, K.RAY_TURN, opts)
	function h:Flash(alpha, seconds)
		local f = self.Frame
		if not f or not f.Parent then
			return
		end
		f.Visible = true
		f.GroupTransparency = math.min(f.GroupTransparency, 1)
		self:_play("Fade", f, TweenInfo.new(math.max(0.01, seconds or 0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = alpha or 0.35 })
	end
	function h:Recolor(r)
		local c = rayColor(r)
		for _, bar in ipairs(self.Frame and self.Frame:GetChildren() or {}) do
			if bar:IsA("ImageLabel") then
				bar.ImageColor3 = c
			elseif bar:IsA("Frame") then
				bar.BackgroundColor3 = c
			end
		end
	end
	return h
end

function HatchFx.Shock(parent, rarity, opts)
	opts = type(opts) == "table" and opts or {}
	local ring = new("Frame", {
		Name = "Shock", BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = opts.ZIndex or 3,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local stroke = new("UIStroke", { Color = lighter(colorOf(rarity, 1), 0.1), Thickness = 6, Transparency = 0 }, ring)
	local h = handle(ring, 12, opts)
	h.Stroke = stroke
	h.Token = 0
	function h:Play(x, y, d, seconds, color)
		local f = self.Frame
		if not f or not f.Parent then
			return
		end
		self.Token = self.Token + 1
		local mine = self.Token
		seconds = math.max(0.05, seconds or 0.35)
		placeAt(f, x, y, 0)
		f.Visible = true
		self.Stroke.Color = color or self.Stroke.Color
		self.Stroke.Transparency = 0
		local out = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self:_play("Grow", f, out, { Size = UDim2.fromOffset(d, d) })
		self:_play("Fade", self.Stroke, out, { Transparency = 1 })
		task.delay(seconds, function()
			if self.Token == mine and self.Frame and self.Frame.Parent then
				self.Frame.Visible = false
			end
		end)
	end
	return h
end

function HatchFx.CloudRing(parent, color, opts)
	opts = type(opts) == "table" and opts or {}
	local ring = new("CanvasGroup", {
		Name = "CloudRing", BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), GroupTransparency = 1,
		GroupColor3 = K.RING_TINT, Visible = false, ZIndex = opts.ZIndex or 1,
	}, parent)
	local swell = new("UIScale", { Name = "Swell", Scale = 1 }, ring)
	-- the puffs: white (GroupColor3 tints them), on a circle RING_R of the ring's size out, big and small in turn and see-
	-- through (roll-look, spec 16.15: the pitch mock's cloudRing, a halo of soft cloud bubbles round the egg rather than
	-- big blobs behind it), a little uneven so it reads as cloud, not a gear
	for i = 1, K.RING_PUFFS do
		local a = (i - 1) / K.RING_PUFFS * 2 * math.pi
		local big = i % 2 == 1
		local s = (big and K.RING_PUFF[1] or K.RING_PUFF[2]) * (1 + 0.12 * ((i * 0.618034) % 1))
		local r = K.RING_R + 0.015 * (((i + 3) * 0.381966) % 1)
		local puff = new("Frame", {
			Name = "Puff" .. i, BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = big and K.RING_PUFF_A[1] or K.RING_PUFF_A[2],
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r), Size = UDim2.fromScale(s, s),
			ZIndex = ring.ZIndex,
		}, ring)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, puff)
	end
	local h = handle(ring, K.RING_TURN, opts)
	h.Swell = swell
	h.Color = color
	function h:Show(seconds)
		local f = self.Frame
		if not f or not f.Parent then
			return
		end
		f.Visible = true
		self.Swell.Scale = 1
		f.GroupColor3 = K.RING_TINT:Lerp(self.Color or K.RING_TINT, 0.12)
		self:_play("Fade", f, TweenInfo.new(math.max(0.01, seconds or 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = K.RING_REST })
	end
	function h:Pulse(c, seconds)
		local f = self.Frame
		if not f or not f.Parent then
			return
		end
		seconds = math.max(0.05, seconds or 0.35)
		cancel(self.Tw.Tint)
		self.Tw.Tint = nil
		f.Visible = true
		f.GroupColor3 = c or self.Color or K.RING_TINT
		f.GroupTransparency = 0
		self:_play("Swell", self.Swell, TweenInfo.new(math.min(0.2, seconds), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = K.SWELL })
		self:_play("Fade", f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
	end
	-- (roll-look, spec 16.15) Gemini's shake tweak: the ring turns half way to the rarity colour
	function h:Tint(c, seconds)
		local f = self.Frame
		if not f or not f.Parent then
			return
		end
		local goal = K.RING_TINT:Lerp(c or self.Color or K.RING_TINT, 0.5)
		if seconds and seconds > 0 then
			self:_play("Tint", f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupColor3 = goal })
		else
			cancel(self.Tw.Tint)
			self.Tw.Tint = nil
			f.GroupColor3 = goal
		end
	end
	return h
end

-- a thin glowing segment from (x1, y1) to (x2, y2), shares of the egg (the egg is 0.8 x as wide as it is tall)
local function segment(parent, name, x1, y1, x2, y2, color, z, k)
	local dx, dy = (x2 - x1), (y2 - y1) / 0.8 -- in egg widths
	local len = math.sqrt(dx * dx + dy * dy)
	local seg = new("Frame", {
		Name = name, BorderSizePixel = 0, BackgroundColor3 = color, BackgroundTransparency = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2), Size = UDim2.fromScale(len + (k or K.CRACK_W), k or K.CRACK_W),
		Rotation = math.deg(math.atan2(dy, dx)), Visible = false, ZIndex = z,
	}, parent)
	return seg
end

local function eggLayer(egg, name, z)
	local holder = egg:FindFirstChild(name)
	if not holder then
		holder = new("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z }, egg)
	end
	return holder
end

function HatchFx.Cracks(egg, rarity, step)
	if typeof(egg) ~= "Instance" then
		return nil
	end
	local z = egg.ZIndex + 8
	local holder = egg:FindFirstChild("Cracks")
	if not holder then
		holder = eggLayer(egg, "Cracks", z)
		local glow = lighter(colorOf(rarity, 1), 0.35)
		-- a white core with the rarity's light on both edges
		local across = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.7) })
		local core = ColorSequence.new({ ColorSequenceKeypoint.new(0, glow), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, glow) })
		for i = 1, 5 do
			local a, b = K.ZIG[i + 1], K.ZIG[i + 2]
			local seg = segment(holder, "Seg" .. i, a[1], a[2], b[1], b[2], Color3.new(1, 1, 1), z)
			new("UIGradient", { Name = "Glow", Rotation = 90, Transparency = across, Color = core }, seg)
		end
		local br = K.BRANCH
		local seg = segment(holder, "Branch", br[1], br[2], br[3], br[4], Color3.new(1, 1, 1), z, K.CRACK_W * 0.8)
		new("UIGradient", { Name = "Glow", Rotation = 90, Transparency = across, Color = core }, seg)
	end
	step = math.max(0, math.floor(tonumber(step) or 0))
	local show = {}
	for _, i in ipairs(K.SEGS[step >= 5 and 5 or (step >= 3 and 3 or (step >= 1 and 1 or 0))] or {}) do
		show[i - 1] = true -- (K.SEGS names zigzag segments 2..6; Seg1..5 are segments 2..6)
	end
	for i = 1, 5 do
		local seg = holder:FindFirstChild("Seg" .. i)
		if seg then
			seg.Visible = show[i] == true
		end
	end
	local branch = holder:FindFirstChild("Branch")
	if branch then
		branch.Visible = step >= 5
	end
	holder:SetAttribute("Step", step)
	return holder
end

function HatchFx.Leaks(egg, rarity, step)
	if typeof(egg) ~= "Instance" then
		return nil
	end
	local z = egg.ZIndex + 7
	local holder = egg:FindFirstChild("Leaks")
	if not holder then
		holder = eggLayer(egg, "Leaks", z)
		local glow = lighter(colorOf(rarity, 1), 0.45)
		for i = 1, 5 do
			local beam = new("Frame", {
				Name = "Leak" .. i, BorderSizePixel = 0, BackgroundColor3 = glow, BackgroundTransparency = 0.15, AnchorPoint = Vector2.new(0.5, 0.5),
				Visible = false, ZIndex = z,
			}, holder)
			new("UIGradient", { Name = "Taper", Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, beam)
		end
	end
	step = math.max(0, math.floor(tonumber(step) or 0))
	local n = math.min(5, step)
	local len = 0.08 + 0.035 * step -- egg heights
	for i = 1, 5 do
		local beam = holder:FindFirstChild("Leak" .. i)
		if beam then
			local p = K.ZIG[i + 2]
			beam.Visible = i <= n
			if i <= n then
				-- up from a high corner, down from a low one, fanned a little
				local up = p[2] < 0.61
				local ang = (up and -90 or 90) + ((i % 3) - 1) * 22
				local rad = math.rad(ang)
				-- the centre half-way out (x in egg widths: a height is 1 / 0.8 widths); local +X points outward, so the
				-- taper (clear at X = 1) fades toward the tip
				beam.Position = UDim2.fromScale(p[1] + math.cos(rad) * len / 0.8 / 2, p[2] + math.sin(rad) * len / 2)
				beam.Size = UDim2.fromScale(len / 0.8, 0.05)
				beam.Rotation = ang
			end
		end
	end
	holder:SetAttribute("Step", step)
	return holder
end

----------------------------------------------------------------------------------------------------
-- the world dim: the one Lighting effect and the "Hatch" LightingStack preset (High only)
----------------------------------------------------------------------------------------------------
local function lightingStack()
	if R.LS == nil then
		R.LS = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("LightingStack")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				R.LS = mod
			end
		end
	end
	return R.LS or nil
end

local function effectsOn()
	local n = 0
	if R.Blur and R.Blur.Parent then
		n = n + 1
	end
	if R.Pushed then
		n = n + 1
	end
	return n
end

function HatchFx.Dim(on, seconds)
	seconds = math.max(0.01, tonumber(seconds) or 0.35)
	local ls = lightingStack()
	if on and high() then
		if not (R.Blur and R.Blur.Parent) then
			local old = Lighting:FindFirstChild("NimbusHatchBlur")
			if old and old:IsA("BlurEffect") then
				old:Destroy()
			end
			R.Blur = new("BlurEffect", { Name = "NimbusHatchBlur", Size = 0 }, Lighting)
		end
		cancel(R.BlurTween)
		R.BlurTween = play(R.Blur, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = K.BLUR })
		if ls and not R.Pushed then
			-- the tint against the look under it (LightingStack presets set absolute values)
			local b = ls.Value("ColorCorrection", "Brightness", "Hatch")
			local s = ls.Value("ColorCorrection", "Saturation", "Hatch")
			if type(b) == "number" and type(s) == "number" then
				local ok = pcall(ls.Push, "Hatch", { ColorCorrection = { Brightness = b + K.TINT.Brightness, Saturation = s + K.TINT.Saturation } }, seconds)
				R.Pushed = ok
			end
		end
	elseif not on then
		cancel(R.BlurTween)
		R.BlurTween = nil
		if R.Blur then
			R.Blur:Destroy()
			R.Blur = nil
		end
		if R.Pushed and ls then
			pcall(ls.Pop, "Hatch", seconds)
		end
		R.Pushed = false
	end
	return effectsOn()
end

function HatchFx.Stats()
	local live, pooled, beats, tweens = 0, 0, 0, 0
	for pool in pairs(R.Pools) do
		live = live + #pool.List
		pooled = pooled + pool.Made
		if pool.Conn then
			beats = beats + 1
		end
	end
	for tw in pairs(R.Stars) do
		if tw.PlaybackState == Enum.PlaybackState.Playing then
			tweens = tweens + 1
		end
	end
	return { Live = live, Pooled = pooled, Tweens = tweens, Heartbeats = beats, Effects = effectsOn() }
end

return HatchFx
