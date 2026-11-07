-- HatchFx (client UI; lobby-shop Task 26, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.5 "Where the VFX
-- show" and 16.4): the GUI sparkles, pooled. A pool owns at most n spark frames (made only when first needed, reused
-- after) and one Heartbeat that runs only while a spark lives; nothing else in the egg VFX runs per frame.
--
--   HatchFx.Pool(parent, n) -> pool   a holder Frame "Sparks" over the parent (n defaults to 16)
--     pool:Burst(at, rarity, count) -> spawned   sparks flying out of `at` (a Vector2 in the parent's px) and fading in
--       0.55-0.9 s; never more than n live at once; halved on Low graphics
--     pool:Ambient(target, rarity [, count, mode])   sparkles round a GuiObject (an egg): Rare 3, Legendary 4, Mythic 6
--       drifting up and fading (mode "Drift"), Secret 2 orbiting star sparks ("Orbit"); none below Rare (Epic: 3) and
--       none on Low. They last until the target is destroyed, SetRunning(false) or Destroy
--     pool:SetRunning(on)   off: every spark back in the pool, the Heartbeat off (the ambient waits); on: it resumes
--     pool:Live() -> the sparks alive now;  pool:Destroy()   the frames and the Heartbeat gone
--   HatchFx.Stars(parent, n) -> { Frame, Destroy }   a Frame "Stars" with n small stars, each twinkling (an endless,
--     offset alpha tween); Destroy stops the tweens and removes the frame
--   HatchFx.Stats() -> { Live, Pooled, Tweens, Heartbeats }   (tests) every pool's live sparks and frames, the star
--     tweens playing, the pools whose Heartbeat is connected
--
-- Positions: the holder's local px are the screen px divided by the UIScale(s) above it (UIScale shrinks the design
-- canvas on a phone). Plain Lua 5.1-compatible syntax only.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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
}
HatchFx.Metrics = K

-- every pool (weak keys) and every star tween playing (weak keys)
local R = { Pools = setmetatable({}, { __mode = "k" }), Stars = setmetatable({}, { __mode = "k" }), GQ = nil, Rng = Random.new(26) }

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

function Pool:_frame()
	local f = table.remove(self.Free)
	if f then
		return f
	end
	if self.Made >= self.N or not self.Holder then
		return nil
	end
	self.Made = self.Made + 1
	f = Instance.new("Frame")
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
	local f = self:_frame()
	if not f then
		return false
	end
	rec.F = f
	rec.Age = 0
	f.BackgroundColor3 = rec.Color
	f.Size = UDim2.fromOffset(rec.Px, rec.Px)
	f.BackgroundTransparency = 1
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
		self.Free[#self.Free + 1] = rec.F
	end
end

-- connects the Heartbeat when something should run, drops it when nothing does
function Pool:_sync()
	local want = self.Running and self.Holder ~= nil and (#self.List > 0 or (next(self.Amb) ~= nil and high()))
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
					f.BackgroundTransparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(self.T * 5 + rec.Phase))
				else
					local k = rec.Age / rec.Life
					f.Position = UDim2.fromOffset(cx + (rec.Ox + rec.Vx * rec.Age) * h, cy + (rec.Oy - K.DRIFT_RISE * rec.Age) * h)
					local fade = (k < 0.25) and (k / 0.25) or ((k > 0.65) and ((1 - k) / 0.35) or 1)
					f.BackgroundTransparency = 1 - 0.85 * math.max(0, fade)
				end
			end
		elseif not gone then
			-- a burst spark: out, slowing, falling a little, fading
			rec.Vx = rec.Vx * math.max(0, 1 - K.DRAG * dt)
			rec.Vy = rec.Vy * math.max(0, 1 - K.DRAG * dt) + K.FALL * dt
			rec.X, rec.Y = rec.X + rec.Vx * dt, rec.Y + rec.Vy * dt
			f.Position = UDim2.fromOffset(rec.X, rec.Y)
			f.BackgroundTransparency = 0.1 + 0.9 * (rec.Age / rec.Life)
		end
		if gone then
			self:_free(i)
		end
	end
	self:_sync()
end

function Pool:Burst(at, rarity, count)
	if not self.Holder or not self.Running then
		return 0
	end
	count = math.max(0, math.floor(tonumber(count) or 0))
	if not high() then
		count = math.floor(count / 2)
	end
	local spawned = 0
	for i = 1, count do
		local ang = R.Rng:NextNumber() * 2 * math.pi
		local speed = between(K.BURST_SPEED)
		local rec = {
			Color = colorOf(rarity, i),
			X = at.X,
			Y = at.Y,
			Vx = math.cos(ang) * speed,
			Vy = math.sin(ang) * speed,
			Px = 6 + math.floor(R.Rng:NextNumber() * 5),
			Life = between(K.BURST_LIFE),
		}
		if not self:_spawn(rec) then
			break
		end
		spawned = spawned + 1
	end
	self:_sync()
	return spawned
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

function HatchFx.Pool(parent, n, z)
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
	return { Live = live, Pooled = pooled, Tweens = tweens, Heartbeats = beats }
end

return HatchFx
