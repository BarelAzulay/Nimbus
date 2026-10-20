--[[
	PetFx (Phase 6): the effects of evolved pets - element particles, a soft glow light and a Neon pulse on the aura.
	Effects are not models (no Parts, no meshes of their own): they live on an invisible Attachment of the pet's Body
	root, so they work for both the Part-built pets and the Blender mesh pets. Contract: ARCHITECTURE_V3.md "## Phase 6"
	6.0.4, 6.1 A6 and 6.4. Plain Lua 5.1-compatible syntax only.

	PetFx.Apply(model, look, stage, opts) -> the PetFx Attachment | nil
		model  a pet Model with an invisible `Body` root (PetBuilder.Build, MeshLibrary.Assemble)
		look   PetBuilder's look ({ Id, Base, Species, Hybrid, ... }); look.Element (optional) wins over the catalog
		stage  1 / 2 = first / second evolution (0 or less does nothing and clears old effects)
		opts   { Detail = "High" | "Low", Scale = 1, NoFx = true (skip), Viewport = true (skip unless Fx = true),
		         Fx = true (force effects in a viewport), Element = "Flame" (override) }
		Builds Body.PetFx (an Attachment at the root; Attachments only work as children of a BasePart, so the effect
		holder IS the attachment) with:
		  * FxMain   the element's ParticleEmitter (default sprite only: shapes from Size / Squash / Transparency /
		             LightEmission curves; embers, snow, sparks, petals, bubbles, gem glints, star motes, wisps)
		  * FxAura   stage 2 only: a shell of twinkling glints in the pet's own Glow / GlowB colours, locked to the pet
		  * FxLight  a soft PointLight (stage 1: brightness 0.6, range 6; stage 2: 1.0, range 8; x Scale)
		Stage 2 also flags the Neon `Aura*` parts PB_Pulse so PetBuilder.Animate breathes them (no new loop here).
		Budgets: total emitter Rate <= 12 (stage 2, High), <= 4 on Low detail (Low = half the rates first).
		Every emitter carries the CollectionService tag "PetFx" (the client's GraphicsQuality Low turns them off).
		Calling Apply again replaces the old effects (idempotent); a Clone carries them (Animate needs nothing new).
	PetFx.Clear(model)              removes Body.PetFx and the pulse flags PetFx added
	PetFx.SetQuality("Low"|"High")  client: Low = light only (every tagged emitter off, also later ones and the
	                                server-built pets that stream in), High = back on. Before the first call the client
	                                follows Roblox's own graphics slider (1-3 = Low, like GraphicsQuality "Auto") and
	                                then the game's Graphics setting (GraphicsQuality + ClientSettings, hooked lazily).
	PetFx.Quality() -> "Low" | "High"
	PetFx.Spec(element, stage, detail) -> { Main = {...}, Aura = {...} | nil, Light = {...}, Rate = total }  (tests)
	PetFx.ElementOf(look) -> element name
	PetFx.TAG, PetFx.Elements (the 8 element recipes)
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local PetFx = {}

local TAG = "PetFx"
local FX_NAME = "PetFx"
local PULSE_FLAG = "PFX_Pulse"
local RATE_CAP = { High = 12, Low = 4 }
local PULSE_MAX = { High = 32, Low = 12 }
local LIGHT = {
	[1] = { Brightness = 0.6, Range = 6 },
	[2] = { Brightness = 1.0, Range = 8 },
}
local STAGE2_WIDE = 1.3 -- stage 2 spreads wider
local STAGE2_SIZE = 1.15 -- and slightly bigger
local AURA_RATE = 5

PetFx.TAG = TAG

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

----------------------------------------------------------------------
-- The element recipes (sizes / speeds at Scale 1; Color = {t, r, g, b}, Size / Transparency / Squash = {t, v})
----------------------------------------------------------------------
local E = {}
-- Flame: little embers that leap out of the pet and float upward, yellow -> orange -> red, fading as they shrink
E.Flame = {
	Rate = 6, Lifetime = { 0.9, 1.5 }, Speed = { 1.4, 2.4 }, Spread = { 70, 70 }, Drag = 2.2,
	Accel = { 0, 2.6, 0 }, Rot = { 0, 360 }, RotSpeed = { -120, 120 }, Light = 1, Brightness = 1.6,
	Color = { { 0, 255, 246, 170 }, { 0.35, 255, 170, 60 }, { 1, 255, 84, 40 } },
	Size = { { 0, 0.05 }, { 0.15, 0.3 }, { 0.6, 0.2 }, { 1, 0 } },
	Transparency = { { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } },
	Squash = { { 0, 0.6 }, { 1, 0.2 } },
	LightColor = rgb(255, 170, 90),
}
-- Frost: soft snowflakes puffed up and drifting slowly down, white with an icy blue edge, turning gently
E.Frost = {
	Rate = 5, Lifetime = { 2.0, 2.8 }, Speed = { 1.6, 2.4 }, Spread = { 80, 80 }, Drag = 2.4,
	Accel = { 0.15, -0.9, 0 }, Rot = { 0, 360 }, RotSpeed = { -50, 50 }, Light = 0.7, Brightness = 1.4,
	Color = { { 0, 255, 255, 255 }, { 0.5, 214, 246, 255 }, { 1, 160, 220, 255 } },
	Size = { { 0, 0 }, { 0.12, 0.26 }, { 0.85, 0.22 }, { 1, 0 } },
	Transparency = { { 0, 0.15 }, { 0.8, 0.25 }, { 1, 1 } },
	LightColor = rgb(190, 236, 255),
}
-- Storm: quick electric sparks that crackle outward as short streaks, white-blue -> violet
E.Storm = {
	Rate = 7, Lifetime = { 0.25, 0.45 }, Speed = { 4.5, 6.5 }, Spread = { 180, 180 }, Drag = 6,
	Accel = { 0, 0, 0 }, Rot = { 0, 0 }, RotSpeed = { 0, 0 }, Light = 1, Brightness = 2,
	Color = { { 0, 236, 248, 255 }, { 0.5, 130, 180, 255 }, { 1, 178, 120, 255 } },
	Size = { { 0, 0.26 }, { 0.6, 0.18 }, { 1, 0 } },
	Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	Squash = { { 0, 1.6 }, { 1, 0.8 } },
	Orientation = "VelocityParallel",
	LightColor = rgb(150, 176, 255),
}
-- Nature: little leaves that tumble out and sail down sideways, fresh green -> spring lime
E.Nature = {
	Rate = 5, Lifetime = { 1.8, 2.6 }, Speed = { 1.8, 2.6 }, Spread = { 75, 75 }, Drag = 2.0,
	Accel = { 0.6, -0.7, 0.2 }, Rot = { 0, 360 }, RotSpeed = { -160, 160 }, Light = 0.35, Brightness = 1.3, Influence = 0.4,
	Color = { { 0, 150, 236, 110 }, { 0.6, 120, 214, 90 }, { 1, 214, 244, 130 } },
	Size = { { 0, 0 }, { 0.1, 0.3 }, { 0.85, 0.26 }, { 1, 0 } },
	Transparency = { { 0, 0 }, { 0.85, 0.1 }, { 1, 1 } },
	Squash = { { 0, -0.55 }, { 1, -0.55 } },
	LightColor = rgb(176, 255, 150),
}
-- Water: shiny bubbles that bob upward and swell before they pop, aqua -> sky blue
E.Water = {
	Rate = 5, Lifetime = { 1.6, 2.3 }, Speed = { 1.2, 2.0 }, Spread = { 90, 90 }, Drag = 2.2,
	Accel = { 0, 1.5, 0 }, Rot = { 0, 360 }, RotSpeed = { -40, 40 }, Light = 0.6, Brightness = 1.4,
	Color = { { 0, 200, 250, 255 }, { 0.6, 110, 206, 255 }, { 1, 160, 236, 255 } },
	Size = { { 0, 0.06 }, { 0.75, 0.32 }, { 0.92, 0.38 }, { 1, 0 } },
	Transparency = { { 0, 0.35 }, { 0.75, 0.2 }, { 0.92, 0 }, { 1, 1 } },
	LightColor = rgb(130, 210, 255),
}
-- Earth: golden gem glints kicked up like crystal dust that twinkle and fall back, amber -> mint crystal
E.Earth = {
	Rate = 5, Lifetime = { 1.2, 1.7 }, Speed = { 2.6, 3.4 }, Spread = { 45, 45 }, Drag = 1.2,
	Accel = { 0, -3.2, 0 }, Rot = { 0, 0 }, RotSpeed = { 0, 0 }, Light = 0.8, Brightness = 1.6,
	Color = { { 0, 255, 226, 140 }, { 0.5, 255, 190, 96 }, { 1, 170, 240, 200 } },
	Size = { { 0, 0 }, { 0.15, 0.3 }, { 0.35, 0.12 }, { 0.55, 0.28 }, { 0.8, 0.1 }, { 1, 0 } },
	Transparency = { { 0, 0 }, { 0.85, 0.1 }, { 1, 1 } },
	LightColor = rgb(255, 210, 140),
}
-- Celestial: twinkling star motes that drift around the pet and rise, white-gold
E.Celestial = {
	Rate = 6, Lifetime = { 1.6, 2.4 }, Speed = { 2.2, 3.0 }, Spread = { 180, 180 }, Drag = 2.6,
	Accel = { 0, 0.5, 0 }, Rot = { 0, 0 }, RotSpeed = { 0, 0 }, Light = 1, Brightness = 1.8,
	Color = { { 0, 255, 255, 236 }, { 0.5, 255, 232, 150 }, { 1, 255, 206, 120 } },
	Size = { { 0, 0 }, { 0.15, 0.32 }, { 0.3, 0.14 }, { 0.5, 0.3 }, { 0.7, 0.12 }, { 0.85, 0.26 }, { 1, 0 } },
	Transparency = { { 0, 0 }, { 0.85, 0.05 }, { 1, 1 } },
	LightColor = rgb(255, 236, 170),
}
-- Shadow: soft violet wisps that curl upward and stretch thin, violet -> magenta
E.Shadow = {
	Rate = 5, Lifetime = { 1.5, 2.1 }, Speed = { 0.8, 1.4 }, Spread = { 90, 90 }, Drag = 1.5,
	Accel = { 0, 1.4, 0 }, Rot = { -15, 15 }, RotSpeed = { -30, 30 }, Light = 0.5, Brightness = 1.5,
	Color = { { 0, 150, 96, 230 }, { 0.5, 186, 110, 255 }, { 1, 236, 120, 214 } },
	Size = { { 0, 0.1 }, { 0.5, 0.38 }, { 1, 0.2 } },
	Transparency = { { 0, 1 }, { 0.2, 0.35 }, { 0.7, 0.45 }, { 1, 1 } },
	Squash = { { 0, 0.4 }, { 1, 1.4 } },
	LightColor = rgb(196, 140, 255),
}
PetFx.Elements = E

-- the second evolution's aura: a shell of glints around the pet in its Glow / GlowB colours that twinkle and turn
local AURA = {
	Lifetime = { 1.4, 2.0 }, Speed = { 3.2, 4.0 }, Spread = { 180, 180 }, Drag = 2.2,
	Accel = { 0, 0.4, 0 }, Rot = { 0, 360 }, RotSpeed = { -90, 90 }, Light = 1, Brightness = 1.8, Locked = true,
	Size = { { 0, 0 }, { 0.2, 0.36 }, { 0.4, 0.18 }, { 0.6, 0.34 }, { 0.8, 0.16 }, { 1, 0 } },
	Transparency = { { 0, 0 }, { 0.8, 0.05 }, { 1, 1 } },
}

local ORDER = { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }
local SPECIES_ELEMENT = {
	Cat = "Celestial", Dog = "Earth", Fox = "Flame", Bunny = "Nature", Bear = "Earth", Panda = "Nature",
	Dragon = "Flame", Owl = "Shadow", Slime = "Water", Unicorn = "Celestial", Phoenix = "Flame", Frog = "Nature",
	Penguin = "Frost", Axolotl = "Water", Stormfang = "Storm",
}

----------------------------------------------------------------------
-- Element and colours
----------------------------------------------------------------------
local catalog = nil -- PetCatalog, required lazily (false when missing)
local function getCatalog()
	if catalog == nil then
		catalog = false
		local ok, mod = pcall(function()
			local inst = script.Parent:FindFirstChild("PetCatalog")
			return inst and require(inst) or nil
		end)
		if ok and type(mod) == "table" and type(mod.Get) == "function" then
			catalog = mod
		end
	end
	return catalog or nil
end

local function knownElement(e)
	return type(e) == "string" and E[e] ~= nil
end

local function catalogElement(id)
	local cat = getCatalog()
	if not cat or type(id) ~= "string" or id == "" then
		return nil
	end
	local def = cat.Get(id) or cat.Get(string.match(id, "^([^@]+)@") or "")
	if type(def) ~= "table" then
		return nil
	end
	if knownElement(def.Element) then
		return def.Element
	end
	if type(def.Elements) == "table" and knownElement(def.Elements[1]) then
		return def.Elements[1]
	end
	return nil
end

function PetFx.ElementOf(look, override)
	if knownElement(override) then
		return override
	end
	look = type(look) == "table" and look or {}
	if knownElement(look.Element) then
		return look.Element
	end
	local e = catalogElement(look.Base) or catalogElement(look.Id)
	if not e and type(look.Hybrid) == "table" then
		e = catalogElement(look.Hybrid.StyleId)
	end
	return e or SPECIES_ELEMENT[look.Species] or "Celestial"
end

-- the pet's own glow colours: PetBuilder.EvolutionColors (stage 2: its two Neon accents Glow / GlowB), else the Neon
-- parts of the model (Glow / GlowB names or MK_Key on mesh pets, then the Aura group), else the element's palette
local builder = nil -- PetBuilder, required lazily (it requires this module at load time)
local function getBuilder()
	if builder == nil then
		builder = false
		local ok, mod = pcall(function()
			local inst = script.Parent:FindFirstChild("PetBuilder")
			return inst and require(inst) or nil
		end)
		if ok and type(mod) == "table" and type(mod.EvolutionColors) == "function" then
			builder = mod
		end
	end
	return builder or nil
end

local function glowColors(model, look, element)
	local pb = getBuilder()
	if pb and type(look) == "table" and look.Hybrid == nil then
		local ok, a, b = pcall(pb.EvolutionColors, {
			Id = look.Id,
			PetId = look.Base,
			Rarity = look.Rarity,
			Look = { Species = look.Species, Primary = look.Primary, Secondary = look.Secondary, WingColor = look.WingColor },
		}, 2)
		if ok and typeof(a) == "Color3" and typeof(b) == "Color3" then
			return a, b
		end
	end
	local found = {}
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
			local key = p:GetAttribute("MK_Key") or string.match(p.Name, "^(%a+)")
			if key == "Glow" or key == "GlowB" then
				found[key] = found[key] or p.Color
			elseif key == "Aura" then
				if not found.AuraA then
					found.AuraA = p.Color
				elseif not found.AuraB and p.Color ~= found.AuraA then
					found.AuraB = p.Color
				end
			end
		end
	end
	local spec = E[element]
	local last = spec.Color[#spec.Color]
	local a = found.Glow or found.AuraA or spec.LightColor
	local b = found.GlowB or found.AuraB or rgb(last[2], last[3], last[4])
	return a, b
end

----------------------------------------------------------------------
-- Specs (pure numbers: the tests and the renders read them)
----------------------------------------------------------------------
local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

function PetFx.Spec(element, stage, detail)
	element = knownElement(element) and element or "Celestial"
	stage = (stage == 2) and 2 or 1
	detail = (detail == "Low") and "Low" or "High"
	local main = copy(E[element])
	local aura = nil
	local rate = main.Rate * (stage == 2 and 1.15 or 1)
	local auraRate = (stage == 2) and AURA_RATE or 0
	if detail == "Low" then
		rate, auraRate = rate * 0.5, auraRate * 0.5
	end
	local total = rate + auraRate
	local cap = RATE_CAP[detail]
	if total > cap then
		rate, auraRate = rate * cap / total, auraRate * cap / total
	end
	main.Rate = math.floor(rate * 100 + 0.5) / 100
	if stage == 2 then
		aura = copy(AURA)
		aura.Rate = math.floor(auraRate * 100 + 0.5) / 100
	end
	local light = LIGHT[stage]
	return {
		Element = element,
		Stage = stage,
		Detail = detail,
		Main = main,
		Aura = aura,
		Light = { Brightness = light.Brightness, Range = light.Range, Color = E[element].LightColor },
		Rate = main.Rate + (aura and aura.Rate or 0),
		Wide = (stage == 2) and STAGE2_WIDE or 1,
		Grow = (stage == 2) and STAGE2_SIZE or 1,
	}
end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------
local function numSeq(points, mul)
	local kps = {}
	for i, p in ipairs(points) do
		kps[i] = NumberSequenceKeypoint.new(p[1], p[2] * mul)
	end
	return NumberSequence.new(kps)
end

local function colorSeq(points)
	local kps = {}
	for i, p in ipairs(points) do
		kps[i] = ColorSequenceKeypoint.new(p[1], rgb(p[2], p[3], p[4]))
	end
	return ColorSequence.new(kps)
end

local function makeEmitter(name, s, scale, wide, grow)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	pe.Rate = s.Rate
	pe.Lifetime = NumberRange.new(s.Lifetime[1], s.Lifetime[2])
	pe.Speed = NumberRange.new(s.Speed[1] * scale * wide, s.Speed[2] * scale * wide)
	pe.SpreadAngle = Vector2.new(s.Spread[1], s.Spread[2])
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Drag = s.Drag
	pe.Acceleration = Vector3.new(s.Accel[1] * scale, s.Accel[2] * scale, s.Accel[3] * scale)
	pe.Rotation = NumberRange.new(s.Rot[1], s.Rot[2])
	pe.RotSpeed = NumberRange.new(s.RotSpeed[1], s.RotSpeed[2])
	pe.Size = numSeq(s.Size, scale * grow)
	pe.Transparency = numSeq(s.Transparency, 1)
	if s.Squash then
		pe.Squash = numSeq(s.Squash, 1)
	end
	if s.ColorSeq then
		pe.Color = s.ColorSeq
	else
		pe.Color = colorSeq(s.Color)
	end
	pe.LightEmission = s.Light
	pe.LightInfluence = s.Influence or 0
	pe.Brightness = s.Brightness or 1
	pe.LockedToPart = s.Locked == true
	if s.Orientation then
		pe.Orientation = Enum.ParticleOrientation[s.Orientation]
	end
	return pe
end

----------------------------------------------------------------------
-- Graphics quality (client only; the server always builds the emitters on)
----------------------------------------------------------------------
local Q = {
	Mode = nil, -- nil = not decided yet, "Low" | "High"
	Off = setmetatable({}, { __mode = "k" }), -- emitters WE turned off
	Conn = nil,
	Hooked = false,
}
PetFx._Q = Q

local function isClient()
	local ok, yes = pcall(function()
		return RunService:IsClient()
	end)
	return ok and yes == true
end

local function sliderMode()
	local ok, level = pcall(function()
		local value = UserSettings().GameSettings.SavedQualityLevel
		if typeof(value) == "EnumItem" then
			return value.Value
		end
		return tonumber(value)
	end)
	if ok and type(level) == "number" and level >= 1 and level <= 3 then
		return "Low"
	end
	return "High"
end

local function turnOff(pe)
	if pe:IsA("ParticleEmitter") and pe.Enabled then
		pe.Enabled = false
		Q.Off[pe] = true
	end
end

-- the game's Graphics setting (client/GraphicsQuality + ClientSettings), found lazily, never yields a Build
local function hookGraphics()
	if Q.Hooked then
		return
	end
	Q.Hooked = true
	task.defer(function()
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			local ps = lp and lp:FindFirstChild("PlayerScripts")
			local client = ps and ps:FindFirstChild("Client")
			local gqm = client and client:FindFirstChild("GraphicsQuality")
			local csm = client and client:FindFirstChild("ClientSettings")
			if not (gqm and csm) then
				return
			end
			local GQ, CS = require(gqm), require(csm)
			if type(GQ) ~= "table" or type(CS) ~= "table" or type(GQ.Effective) ~= "function" then
				return
			end
			local function sync()
				local st = GQ._St
				if type(st) == "table" and st.Started then
					PetFx.SetQuality(GQ.Effective())
				end
			end
			if CS.Changed and type(CS.Changed.Connect) == "function" then
				CS.Changed:Connect(function(key)
					if key == "Gfx" then
						task.defer(sync)
					end
				end)
			end
			sync()
		end)
	end)
end

function PetFx.SetQuality(mode)
	mode = (mode == "Low") and "Low" or "High"
	Q.Mode = mode
	if mode == "Low" then
		for _, pe in ipairs(CollectionService:GetTagged(TAG)) do
			turnOff(pe)
		end
		if not Q.Conn then
			Q.Conn = CollectionService:GetInstanceAddedSignal(TAG):Connect(function(pe)
				if Q.Mode == "Low" then
					turnOff(pe)
				end
			end)
		end
	else
		if Q.Conn then
			Q.Conn:Disconnect()
			Q.Conn = nil
		end
		for pe in pairs(Q.Off) do
			Q.Off[pe] = nil
			if pe.Parent then
				pe.Enabled = true
			end
		end
	end
	return mode
end

function PetFx.Quality()
	if Q.Mode == nil and isClient() then
		PetFx.SetQuality(sliderMode())
		hookGraphics()
	end
	return Q.Mode or "High"
end

----------------------------------------------------------------------
-- Apply / Clear
----------------------------------------------------------------------
local function rootOf(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	local root = model:FindFirstChild("Body")
	if root and root:IsA("BasePart") then
		return root
	end
	local pp = model:IsA("Model") and model.PrimaryPart or nil
	return pp
end

function PetFx.Clear(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local fx = root:FindFirstChild(FX_NAME)
	while fx do
		fx:Destroy()
		fx = root:FindFirstChild(FX_NAME)
	end
	for _, p in ipairs(model:GetChildren()) do
		if p:GetAttribute(PULSE_FLAG) then
			p:SetAttribute(PULSE_FLAG, nil)
			p:SetAttribute("PB_Pulse", nil)
		end
	end
end

-- stage 2: the Neon aura parts breathe (PetBuilder.Animate reads PB_Pulse)
local function flagPulse(model, detail)
	local n, max = 0, PULSE_MAX[detail]
	for _, p in ipairs(model:GetChildren()) do
		if n >= max then
			break
		end
		if p:IsA("BasePart") and p.Material == Enum.Material.Neon and string.sub(p.Name, 1, 4) == "Aura" then
			if p:GetAttribute("PB_Pulse") == nil then
				p:SetAttribute("PB_Pulse", p.Transparency)
				p:SetAttribute(PULSE_FLAG, true)
			end
			n = n + 1
		end
	end
	return n
end

function PetFx.Apply(model, look, stage, opts)
	opts = type(opts) == "table" and opts or {}
	local root = rootOf(model)
	if not root then
		return nil
	end
	PetFx.Clear(model)
	stage = tonumber(stage) or 0
	if stage <= 0 or opts.NoFx == true or (opts.Viewport == true and opts.Fx ~= true) then
		return nil
	end
	stage = (stage >= 2) and 2 or 1
	local detail = (opts.Detail == "Low") and "Low" or "High"
	local scale = tonumber(opts.Scale) or tonumber(model:GetAttribute("PB_Scale")) or 1
	if scale ~= scale or scale <= 0 then
		scale = 1
	end
	local element = PetFx.ElementOf(look, opts.Element)
	local spec = PetFx.Spec(element, stage, detail)

	local fx = Instance.new("Attachment")
	fx.Name = FX_NAME
	fx:SetAttribute("Stage", stage)
	fx:SetAttribute("Element", element)
	fx:SetAttribute("Detail", detail)
	fx:SetAttribute("Rate", spec.Rate)

	local emitters = { makeEmitter("FxMain", spec.Main, scale, spec.Wide, spec.Grow) }
	if spec.Aura then
		local a, b = glowColors(model, look, element)
		local aura = copy(spec.Aura)
		aura.ColorSeq = ColorSequence.new({
			ColorSequenceKeypoint.new(0, a:Lerp(rgb(255, 255, 255), 0.35)),
			ColorSequenceKeypoint.new(0.5, a),
			ColorSequenceKeypoint.new(1, b),
		})
		emitters[2] = makeEmitter("FxAura", aura, scale, spec.Wide, spec.Grow)
	end
	local low = isClient() and PetFx.Quality() == "Low"
	for _, pe in ipairs(emitters) do
		CollectionService:AddTag(pe, TAG)
		if low then
			pe.Enabled = false
			Q.Off[pe] = true
		end
		pe.Parent = fx
	end

	local light = Instance.new("PointLight")
	light.Name = "FxLight"
	light.Brightness = spec.Light.Brightness
	light.Range = math.min(60, spec.Light.Range * math.max(1, scale))
	light.Color = spec.Light.Color
	light.Shadows = false
	light.Parent = fx

	if stage == 2 then
		fx:SetAttribute("Pulse", flagPulse(model, detail))
	end
	fx.Parent = root
	return fx
end

PetFx._Order = ORDER
return PetFx
