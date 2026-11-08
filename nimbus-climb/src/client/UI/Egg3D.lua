-- Egg3D (client UI; egg-3d, the owner's pick 2026-11-08 "3D egg + 3D crack", spec
-- docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.14 "3D eggs"): the real Blender egg in a ViewportFrame for the
-- hatch cutscene's pedestal phases (EggStage: Rise, Crack) and the Shop's Secret hero egg (ShopEggs), and the crack that
-- splits it into its two Blender halves which fly apart. The model is the shelf's own dressed mesh: MeshLibrary.Assemble
-- of the same key, the way MeshLibrary.Dress dresses the Egg Guide's shelf eggs (no fork, no second loader).
--
--   Egg3D.KEYS[rarity] = { Whole = "egg_<r>", Top = "egg_<r>_top", Bot = "egg_<r>_bot" }   (literal keys: tools/mesh_keys.py)
--   Egg3D.Usable(rarity, opts) -> ok, reason   reason "low" (Low graphics), "missing" (the whole egg's key is not usable
--                                  here: no id, still loading, refused, a failed load), "limit" (the phone limit), "rarity"
--   Egg3D.New(parent, rarity, opts) -> view | nil, reason   (nil = draw today's 2D EggArt egg, exactly as before)
--       opts = { Phone = bool (the one-at-a-time limit), Name = "Egg3D", ZIndex, Spin = seconds a turn (nil = still),
--                Turn = start angle (degrees), View = egg heights the frame shows (default 2: the frame is 2.5 x 2 of the
--                parent, centred, room for the halves to fly) }
--       an Assemble that fails (a template gone, a part missing) returns nil, "failed"
--   view.Frame (the ViewportFrame), view.Rarity, view.Key, view.Model, view.Top / view.Bot (after Split), view.Dead
--   view:Spin(seconds | nil)      a slow turn (an endless Linear tween of a NumberValue; nil stops it where it is)
--   view:Settle(seconds)          the turn eases to a stop (Quad Out) over that long: the crack holds the egg still
--   view:Pose(rollDeg, bob)       the shake: a roll about the egg's middle (GUI-clockwise for > 0, as GuiObject.Rotation)
--                                 and a bob in studs; one PivotTo, no table / Instance made
--   view:CanSplit() -> bool       both halves usable here (their ids, loaded, High)
--   view:Split() -> bool          the whole egg out, the two halves in at its exact pose (they line up with it)
--   view:Fly(seconds) -> bool     the halves fly apart (a NumberValue tween, Quart Out): the cap up-left, tumbling to show
--                                 its hollow and fading out from half-way, the cup rocks and settles where it stood
--   view:Destroy()                everything (tweens, connections, the frame); also when the frame is destroyed
--   Egg3D.Watch(fn) -> connection fn(key) when a mesh key may have become usable here (MeshLibrary.Changed)
--   Egg3D.Live() -> number        views alive now; Egg3D.Limit(phone) -> 1 on a phone, 2 elsewhere (the Shop hero and a
--                                 cutscene egg); the x3 roll and the strip cells always draw 2D eggs
--   Egg3D._ML / Egg3D._High       tests only: a MeshLibrary stand-in { IsReady, Assemble } and a graphics answer
--
-- The camera: FieldOfView 20 from 8 degrees above, framing 2 x the egg's height (the frame is 2 egg heights tall), so the
-- 3-stud egg fills the same box the 2D egg did. Light per rarity (Ambient / LightColor / LightDirection from the upper
-- left, in front): soft and close to white for the low eggs, warm gold for Legendary, cool violet night for Secret.
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))

local UIFolder = script.Parent
local ClientFolder = UIFolder.Parent

local Egg3D = {}

Egg3D.KEYS = {
	Common = { Whole = "egg_common", Top = "egg_common_top", Bot = "egg_common_bot" },
	Uncommon = { Whole = "egg_uncommon", Top = "egg_uncommon_top", Bot = "egg_uncommon_bot" },
	Rare = { Whole = "egg_rare", Top = "egg_rare_top", Bot = "egg_rare_bot" },
	Epic = { Whole = "egg_epic", Top = "egg_epic_top", Bot = "egg_epic_bot" },
	Legendary = { Whole = "egg_legendary", Top = "egg_legendary_top", Bot = "egg_legendary_bot" },
	Mythic = { Whole = "egg_mythic", Top = "egg_mythic_top", Bot = "egg_mythic_bot" },
	Secret = { Whole = "egg_secret", Top = "egg_secret_top", Bot = "egg_secret_bot" },
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local K = {
	EGG_H = 3, -- studs (the Blender egg: 2.2 x 3 x 2.2, pivot at the bottom centre)
	FOV = 20,
	PITCH = math.rad(8),
	WIDTH = 0.8, -- the 2D egg frame's width per height (EggArt): the frame is VIEW_EGGS / WIDTH of its width wide
	VIEW_EGGS = 2, -- egg heights the frame shows top to bottom (and parent heights it is tall): room for the halves
	-- the light per rarity: Ambient fills, LightColor from the upper left in front (it travels to -X, down, to +Z: onto the
	-- egg's -Z front)
	LIGHT = {
		Common = { rgb(176, 180, 194), rgb(255, 250, 240) },
		Uncommon = { rgb(170, 186, 176), rgb(255, 252, 236) },
		Rare = { rgb(168, 180, 202), rgb(240, 248, 255) },
		Epic = { rgb(178, 168, 200), rgb(255, 244, 255) },
		Legendary = { rgb(190, 176, 156), rgb(255, 236, 196) },
		Mythic = { rgb(196, 170, 186), rgb(255, 238, 246) },
		Secret = { rgb(132, 120, 176), rgb(214, 198, 255) },
	},
	LIGHT_AMOUNT = 0.55, -- LightColor is scaled by this (the vertex colours already carry their baked shading)
	DIR = Vector3.new(-0.55, -1, 0.7),
	-- the burst: the cap's flight (studs, radians) and the cup's rock. The flight is Quart Out, so u = 0.7 comes at about a
	-- quarter of the burst: the cap is seen solid on its way out and fades over the slow tail
	CAP = { X = 0.85, Y = 1.35, Z = -0.4, Roll = -0.62, Tumble = 0.55, FadeFrom = 0.7 },
	ROCK = 0.12,
}
Egg3D.Metrics = K

local LIVE = setmetatable({}, { __mode = "k" }) -- view -> true while alive
local GQ = nil

local function high()
	if Egg3D._High ~= nil then
		return Egg3D._High == true
	end
	if GQ == nil then
		GQ = false
		local module = ClientFolder:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				GQ = mod
			end
		end
	end
	if not GQ or type(GQ.Effective) ~= "function" then
		return true
	end
	local ok, mode = pcall(GQ.Effective)
	return not ok or mode ~= "Low"
end

local ML = nil
local function lib()
	if Egg3D._ML then
		return Egg3D._ML
	end
	if ML == nil then
		ML = false
		local module = Shared:FindFirstChild("MeshLibrary")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				ML = mod
			end
		end
	end
	return ML or nil
end

local function ready(key)
	local m = lib()
	if not m or type(m.IsReady) ~= "function" then
		return false
	end
	local ok, yes = pcall(m.IsReady, key)
	return ok and yes == true
end

-- the shelf's dressed mesh: the same Assemble call MeshLibrary.Dress makes, at the pivot (identity)
local function assemble(key, name)
	local m = lib()
	if not m or type(m.Assemble) ~= "function" then
		return nil
	end
	local ok, model = pcall(m.Assemble, { Name = name, Root = false, Parts = { { Key = key } } }, {}, { Scale = 1, At = CFrame.new() })
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	return nil
end

function Egg3D.Live()
	local n = 0
	for v in pairs(LIVE) do
		if not v.Dead then
			n = n + 1
		end
	end
	return n
end

-- fn(key) whenever a mesh key may have become usable / unusable here (MeshLibrary.Changed) -> connection | nil
function Egg3D.Watch(fn)
	local m = lib()
	local sig = m and m.Changed
	if type(sig) == "table" and type(sig.Connect) == "function" then
		local ok, conn = pcall(sig.Connect, sig, fn)
		return ok and conn or nil
	end
	return nil
end

function Egg3D.Limit(phone)
	return phone and 1 or 2
end

function Egg3D.Usable(rarity, opts)
	local keys = Egg3D.KEYS[rarity]
	if not keys then
		return false, "rarity"
	end
	if not high() then
		return false, "low"
	end
	if not ready(keys.Whole) then
		return false, "missing"
	end
	if Egg3D.Live() >= Egg3D.Limit(type(opts) == "table" and opts.Phone == true) then
		return false, "limit"
	end
	return true, nil
end

----------------------------------------------------------------------
-- the view
----------------------------------------------------------------------
local View = {}
View.__index = View

local CENTER = CFrame.new(0, K.EGG_H / 2, 0)
local CENTER_INV = CENTER:Inverse()

-- the whole egg's pose from the turn, the shake's roll and the bob (one CFrame chain: no table)
function View:_pose()
	local yaw = math.rad(self.Turn.Value)
	return CFrame.new(0, self.Bob, 0) * CENTER * CFrame.Angles(0, 0, self.Roll) * CFrame.Angles(0, yaw, 0) * CENTER_INV
end

function View:_apply()
	if self.Dead or self.IsSplit or not self.Model then
		return
	end
	self.Model:PivotTo(self:_pose())
end

function View:_track(tw)
	self.Tweens[tw] = true
	tw:Play()
	return tw
end

function View:_stopTurn()
	if self.TurnTw then
		pcall(function()
			self.TurnTw:Cancel()
		end)
		self.Tweens[self.TurnTw] = nil
		self.TurnTw = nil
	end
end

function View:Spin(seconds)
	if self.Dead then
		return
	end
	self:_stopTurn()
	seconds = tonumber(seconds)
	if not seconds or seconds <= 0 then
		return
	end
	local from = self.Turn.Value % 360
	self.Turn.Value = from
	self.TurnTw = self:_track(TweenService:Create(self.Turn, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Value = from + 360 }))
	self.TurnRate = 360 / seconds
end

function View:Settle(seconds)
	if self.Dead then
		return
	end
	local rate = self.TurnTw and self.TurnRate or 0
	self:_stopTurn()
	seconds = math.max(0.05, tonumber(seconds) or 0.5)
	if rate > 0 then
		-- Quad Out from the turn's speed: it covers half of speed x time and stops without a jolt
		self.TurnTw = self:_track(TweenService:Create(self.Turn, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = self.Turn.Value + rate * seconds / 2 }))
	end
	self.TurnRate = 0
end

function View:Pose(rollDeg, bob)
	if self.Dead or self.IsSplit then
		return
	end
	self.Roll = math.rad(tonumber(rollDeg) or 0)
	self.Bob = tonumber(bob) or 0
	self:_apply()
end

function View:CanSplit()
	return not self.Dead and high() and ready(self.Keys.Top) and ready(self.Keys.Bot)
end

function View:Split()
	if self.Dead or self.IsSplit or not self:CanSplit() then
		return false
	end
	local top = assemble(self.Keys.Top, "EggTop")
	local bot = assemble(self.Keys.Bot, "EggBot")
	if not (top and bot) then
		if top then
			top:Destroy()
		end
		if bot then
			bot:Destroy()
		end
		return false
	end
	self:_stopTurn()
	local at = self:_pose()
	self.SplitAt = at
	-- the cap turns about its own middle (its box centre at the pivot, before it is placed), in the frame's space (the
	-- screen's axes: the egg may have turned), so it always flies up-left and shows its hollow to the camera
	local okBox, cf = pcall(function()
		return (top:GetBoundingBox())
	end)
	local mid = (okBox and typeof(cf) == "CFrame") and cf.Position or Vector3.new(0, 2.3, 0)
	local p = at * mid
	self.CapMid = CFrame.new(p)
	self.CapMidInv = CFrame.new(-p)
	top:PivotTo(at)
	bot:PivotTo(at)
	top.Parent = self.Frame
	bot.Parent = self.Frame
	self.CapParts = {}
	for _, d in ipairs(top:GetDescendants()) do
		if d:IsA("BasePart") then
			self.CapParts[#self.CapParts + 1] = { d, d.Transparency }
		end
	end
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
	self.Top, self.Bot = top, bot
	self.IsSplit = true
	self.Frame:SetAttribute("Split", true)
	return true
end

-- one step of the flight (u 0 -> 1, already eased)
function View:_fly()
	if self.Dead or not self.Top then
		return
	end
	local u = self.FlyU.Value
	local c = K.CAP
	local at = self.SplitAt
	self.Top:PivotTo(CFrame.new(c.X * u, c.Y * u, c.Z * u) * self.CapMid * CFrame.Angles(0, 0, c.Roll * u) * CFrame.Angles(c.Tumble * u, 0, 0) * self.CapMidInv * at)
	local fade = u > c.FadeFrom and (u - c.FadeFrom) / (1 - c.FadeFrom) or 0
	for _, pt in ipairs(self.CapParts) do
		pt[1].Transparency = pt[2] + (1 - pt[2]) * fade
	end
	-- the cup rocks on its foot and settles (a damped wobble about the pivot)
	self.Bot:PivotTo(at * CFrame.Angles(0, 0, K.ROCK * math.sin(u * math.pi * 3) * (1 - u)))
end

function View:Fly(seconds)
	if self.Dead or not self.IsSplit or self.FlyTw then
		return false
	end
	self.FlyU.Value = 0
	self.FlyTw = self:_track(TweenService:Create(self.FlyU, TweenInfo.new(math.max(0.05, tonumber(seconds) or 0.35), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = 1 }))
	self.Frame:SetAttribute("Flying", true)
	return true
end

function View:Destroy()
	if self.Dead then
		return
	end
	self.Dead = true
	LIVE[self] = nil
	for tw in pairs(self.Tweens) do
		pcall(function()
			tw:Cancel()
		end)
	end
	self.Tweens = {}
	for _, c in ipairs(self.Conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	self.Conns = {}
	self.CapParts = {}
	local f = self.Frame
	self.Model, self.Top, self.Bot = nil, nil, nil
	if f and f.Parent then
		f:Destroy()
	end
end

function Egg3D.New(parent, rarity, opts)
	opts = type(opts) == "table" and opts or {}
	local ok, reason = Egg3D.Usable(rarity, opts)
	if not ok then
		return nil, reason
	end
	local keys = Egg3D.KEYS[rarity]
	local model = assemble(keys.Whole, "Egg")
	if not model then
		return nil, "failed"
	end
	local light = K.LIGHT[rarity] or K.LIGHT.Common
	local lc = light[2]
	-- the frame shows `view` egg heights top to bottom and is that many parent heights tall (as wide in the 0.8-wide 2D
	-- egg's measure), so the 3-stud egg always fills the parent's height
	local viewEggs = math.max(1, tonumber(opts.View) or K.VIEW_EGGS)
	local frame = Util.Create("ViewportFrame", {
		Name = opts.Name or "Egg3D",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(viewEggs / K.WIDTH, viewEggs),
		ZIndex = opts.ZIndex or 1,
		Ambient = light[1],
		LightColor = Color3.new(lc.R * K.LIGHT_AMOUNT, lc.G * K.LIGHT_AMOUNT, lc.B * K.LIGHT_AMOUNT),
		LightDirection = K.DIR,
	})
	frame:SetAttribute("Rarity", rarity)
	frame:SetAttribute("Key", keys.Whole)
	local cam = Util.Create("Camera", { Name = "Camera", FieldOfView = K.FOV, Parent = frame })
	local dist = (K.EGG_H * viewEggs / 2) / math.tan(math.rad(K.FOV) / 2)
	local look = Vector3.new(0, K.EGG_H / 2, 0)
	cam.CFrame = CFrame.lookAt(look + Vector3.new(0, math.sin(K.PITCH) * dist, -math.cos(K.PITCH) * dist), look)
	frame.CurrentCamera = cam
	local turn = Util.Create("NumberValue", { Name = "Turn", Value = tonumber(opts.Turn) or 0, Parent = frame })
	local flyU = Util.Create("NumberValue", { Name = "Fly", Value = 0, Parent = frame })
	local view = setmetatable({
		Frame = frame, Camera = cam, Model = model, Rarity = rarity, Key = keys.Whole, Keys = keys,
		Turn = turn, FlyU = flyU, Roll = 0, Bob = 0, TurnRate = 0, Tweens = {}, Conns = {}, CapParts = {},
		IsSplit = false, Dead = false,
	}, View)
	view.Conns[1] = turn.Changed:Connect(function()
		view:_apply()
	end)
	view.Conns[2] = flyU.Changed:Connect(function()
		view:_fly()
	end)
	view.Conns[3] = frame.Destroying:Connect(function()
		view:Destroy()
	end)
	model.Parent = frame
	view:_apply()
	LIVE[view] = true
	frame.Parent = parent
	if opts.Spin then
		view:Spin(opts.Spin)
	end
	return view, nil
end

return Egg3D
