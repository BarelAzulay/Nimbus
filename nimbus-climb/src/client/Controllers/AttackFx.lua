-- AttackFx (client): plays the pet attack effects that shared/AttackFxCatalog resolves (docs/superpowers/specs/
-- 2026-10-23-pet-attack-vfx-design.md "Architecture", "The 5 beats of every attack", "Rarity ladder", "Budgets,
-- quality, readability"; plan docs/superpowers/plans/2026-10-23-pet-attack-vfx.md Task 6). Client only: every
-- instance is local, nothing replicates. BattleController (Task 7) calls Play from its attack handlers and keeps its
-- cube Fx.* call as the fallback whenever Play returns false. Plain Lua 5.1-compatible syntax only.
--
-- API:
--   AttackFx.Play(ctx) -> bool     false = not played (the caller draws its cube Fx.* instead): unknown attack /
--       element / kind / shape, no source point, a texture key missing from TextureIds, the budget full, an error.
--       ctx = { Attack ("Melee" | "Ranged" | "Special" | "Element" | "Hurt" | "Ko" | "Victory"), Kind (Special),
--               Shape (Element: "Cone" | "Circle" | "Line"), Element, Rarity, Stage, PetId,
--               From = { Unit, Model, Pos }, To = { Unit, Model, Pos } or a list of them (allies / several targets),
--               Mine (own team: full density, camera punch, screen glow), Crit, Strong, Miss,
--               DueAt (clock time the impact must land: the charge is shortened to fit, impact never later, except
--               that a basic Ranged shot keeps its recipe's Beats.MinTravel of flight: player note 1),
--               Angle (Element attacks without a To: the WORLD yaw of the attack, direction (cos a, 0, sin a)),
--               Radius (Cone reach / Circle radius, default 9 / 8), Length (Line, default 24),
--               Ground (world Y of the floor under From; default From.Y - 1.6), Now (the clock; default os.clock()) }
--       Play writes ctx.ImpactLate = seconds the impact lands after DueAt (0 unless a Ranged shot's MinTravel needed
--       more time than DueAt left; BattleController then plays the Hit that much later).
--       A point is Model:GetPivot() while the Model is in the game, else its last known point, else Pos: a unit
--       destroyed mid-travel ends the effect at its last known point; From.Model may be nil (From.Pos only).
--   AttackFx.Update(now)            advances every live effect and pose; called from BattleController's existing
--                                   per-frame step (no RenderStepped / Heartbeat connection of its own)
--   AttackFx.Pose(unitId) -> { Name, P, Ranged, Amp?, Reach?, Blend, Prev? } | nil   the pose a battle unit shows now (PetPoses
--       names; P 0..1). Blend = 1 normally; for AttackFx.CROSSFADE (0.12 s) after a pose replaces another mid-way,
--       Blend rises 0 -> 1 and Prev = { Name, P, Ranged } is the replaced pose, still animating. The CALLER blends:
--       root = frame * PoseBody(Prev):Lerp(PoseBody(cur), Blend), Animate with the current pose (Prev while
--       Blend < 0.5; the returned tables are reused per unit: read them at once). The newest play on a unit wins (Ko > Cast > Windup / Strike / Shoot / Victory > Hurt while
--       the higher one is still playing); Melee = Windup + the Strike lunge, Ranged = the ranged Windup (rear back) +
--       Shoot (the head snaps forward, the body kicks back: never the lunge, player note 1); a melee Strike freezes for HIT_STOP (0.05 s) at the impact; Ko holds at P = 1 until
--       Cancel(unitId) / ClearAll(). nil = no attack pose (the caller shows IdleBattle or nothing). A melee Strike carries
--       Amp (the band's leap scale) and Reach (AttackFx.LeapReach at the Play: the leap lands on the target); the caller
--       passes both on to PetBuilder.PoseBody / Animate (PetPoses.Sample's amp, reach).
--   AttackFx.LeapReach(src, tgt) -> number | nil   the melee leap's length in the caster's pose units (studs at scale
--       1): from its front edge to the target's near edge, minus LEAP_MARGIN 0.3, clamped 0 .. LEAP_MAX 12 world studs,
--       / the caster's PB_Scale. src / tgt = { Model?, Last = Vector3 }
--   AttackFx.Cancel(unitId)         drops the unit's pose and ends the effects it cast (a unit swapped out / gone)
--   AttackFx.ClearAll()             ends everything (the battle is over)
--   AttackFx.SetQuality("Low" | "High" | nil)   nil = follow client/GraphicsQuality.Effective(). Low: emitters per
--       effect <= 2 (the Burst, then the first of the recipe's LowKeep it has: the element's most characteristic one),
--       particle counts halved, no Beams / Trails / bloom light; switching to Low strips the Beams /
--       Trails of the live effects at once
--   AttackFx.Stats() -> { Live, Stepped, Emitters, Beams, Trails, Lights, Cores, Pooled, PoolInstances, Errors }
--       Live = full effects, Stepped = stepped-down ones, the rest = kits held by live effects / pooled kits
--   AttackFx.Hooks = { Punch = fn(amount, seconds), ScreenGlow = fn(color, seconds), DimWorld = fn(seconds) }
--       set by the caller: the camera punch (own pet, band 3+, amount <= PUNCH_MAX 0.35: route it through
--       BattleController's Me.Shake / ShakeScale path), the edge glow (own pet, band 4) and a signature's dimming
--       (own pet). AttackFx never touches the camera or Lighting itself; other players' effects call no hook.
--   AttackFx.Folder() -> Folder     workspace.ClientBattle.AttackFx (the kits, live and pooled)
--   Tests: AttackFx._Deps({ MeshLibrary =, TextureIds =, GraphicsQuality = }) (false = the real one again),
--          AttackFx._Live() (the live effects)
--
-- Budget: MAX_LIVE (10) full effects; over it a play steps down one rarity band (MAX_STEPPED more at most), then
-- Play returns false. Per effect: MAX_EMITTERS (6 High / 2 Low) ParticleEmitters, MAX_BEAMS, MAX_TRAILS,
-- MAX_LIGHTS, MAX_CORES solid pieces. Over a cap the layers are RANKED, never cut in catalog order: emitters by
-- emitterRank (the Burst, LowKeep, impact detail ...), beams by beamRank (the alive detail, the recipe's own beams, the
-- ladder's DoubleArc / ShotArcs; one beam each first, then each layer's own count, best first: beamBudget).
-- Counts are the catalog's FULL density x recipe.Density (0.6 for others' pets)
-- x 0.5 at Low. Emitters stay Enabled = false (Rate 0) and are fired with Emit(): one emitter serves several points
-- (allies, rain) and nothing ever streams on by itself.
--
-- Kits (pooled per kind under the folder, hidden when free, POOL keep sizes below; nothing is created per frame):
--   Emitter  an invisible anchored host Part + a ParticleEmitter (the host's Size gives the Box / Sphere shapes);
--            4x4 sheets: FlipbookLayout Grid4x4, FlipbookMode + FlipbookFramerate from blender/vfx/textures.json
--            (SHEETS below), LightEmission per sheet (glows 1, smoke / dust / rock 0), size + transparency curves
--   Beam     two host Parts with an Attachment each + a Beam (fx_lightning / fx_speedlines strips, or untextured)
--   Trail    a host Part with two Attachments + a Trail
--   Light    a host Part + a PointLight
--   Disc     a flat cylinder carrying a soft glow image (fx_glow) on its top face (untextured ground glows: scorch,
--            ground glow, the Shadow floor darkening; Task 8: a hard Neon plate read as pink plastic). Without the
--            glow texture id it falls back to the plain Neon cylinder.
--   Core     the single MeshPart "Core" of a vfx_* key from MeshLibrary.Assemble, tinted (Color / Material from the
--            recipe; band 2+ adds a hot inner core, band 3+ a twin blade / fins), scaled and faded with easing
-- Cores: a key MeshLibrary.IsReady says is not usable here is skipped: the effect still plays with its texture
-- layers only (every recipe reads without its core: the impact burst, the element detail and the charge glow are
-- all textured). Textures are "rbxassetid://" .. the TextureIds number (Image ids only, never Decal ids).
-- Layer kinds: Emitter (flipbook particles; burst motions Burst, Geyser = an upward column, Implode = pulled
-- inward, Fling, Rise, Shatter, Erupt; Spiral / Fall / trails stream over their beat), Decal (a textured 4x4 sheet
-- drawn as a ground-flat particle (VelocityPerpendicular), else a glow Disc), Beam (path bolts, spirals, arcs, the
-- double crescent, stray strikes, constellation lines), Trail (afterimages, the pounce leap, wind on allies), Light
-- (flash, bloom pulse, the colour-shifting plasma rim), Ring (vfx_ring / vfx_shell expanding), Mesh (vfx_* pieces
-- erupting). Layer Delay = seconds after its beat starts; At "Behind" = behind the caster. Unknown motions play as
-- a plain burst. The signature Actor (vfx_sig_*) moves by its Motion (SpiralUp, Rise, ChargeThrough, Burst, Sweep,
-- Orbit, RingRise, RiseRoar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent and script.Parent.Parent

local AttackFx = {}

AttackFx.MAX_LIVE = 10
AttackFx.MAX_STEPPED = 4
AttackFx.MAX_EMITTERS = { High = 6, Low = 2 }
AttackFx.MAX_BEAMS = 4
AttackFx.MAX_TRAILS = 4
AttackFx.MAX_LIGHTS = 3
AttackFx.MAX_CORES = 14
AttackFx.PUNCH_MAX = 0.35 -- BattleController SHAKE_MAX
AttackFx.CROSSFADE = 0.12
AttackFx.HIT_STOP = 0.05
AttackFx.Hooks = { Punch = nil, ScreenGlow = nil, DimWorld = nil }

local K = {
	PARENT = "ClientBattle",
	FOLDER = "AttackFx",
	KEEP = { Emitter = 24, Beam = 8, Trail = 6, Light = 8, Disc = 8 },
	CORE_KEEP = 6, -- per vfx_* key
	CORE_KEYS = 22,
	LOW_COUNT = 0.5,
	MAX_ALLIES = 4,
	MOUTH = 0.9, -- studs in front of the caster's centre (x size)
	ABOVE = 5,
	BEHIND = 2.6,
	DROP = 1.6, -- default height of a unit's centre over the floor
	HURT = 0.5,
	KO = 0.9,
	VICTORY = 1.2,
	SHOOT = 0.6, -- the ranged Shoot pose (PetPoses): the head snaps forward, the body kicks back, settles
	LEAP_STEP = 0.08, -- the melee Strike's leap grows by this per rarity band above Common (PetPoses amp, <= 1.25)
	-- (Task 9 player decision: the melee leap lands on the target) its forward reach = the gap between the caster's and
	-- the target's facing edges minus LEAP_MARGIN, clamped 0 .. LEAP_MAX world studs
	LEAP_MARGIN = 0.3,
	LEAP_MAX = 12,
	BAND_RARITY = { "Common", "Rare", "Legendary", "Secret" },
	PRIO = { Ko = 4, Cast = 3, Windup = 2, Strike = 2, Shoot = 2, Recoil = 2, Victory = 2, Hurt = 1 },
}
AttackFx.POOL_KEEP_TOTAL = K.KEEP.Emitter + K.KEEP.Beam + K.KEEP.Trail + K.KEEP.Light + K.KEEP.Disc + K.CORE_KEEP * K.CORE_KEYS

-- the 4x4 sheets of blender/vfx/textures.json: key -> { FlipbookMode, fps, LightEmission }
-- (fx_lightning / fx_speedlines are grid-1 strips: Beams / Trails only)
local SHEETS = {
	fx_flame = { "Loop", 24, 0.75 }, fx_embers = { "Loop", 20, 1 }, fx_smoke = { "OneShot", 16, 0 },
	fx_splash = { "OneShot", 20, 0.35 }, fx_droplets = { "OneShot", 16, 0.25 }, fx_ripple = { "OneShot", 16, 0.4 },
	fx_iceshards = { "Loop", 16, 0.45 }, fx_snow = { "Loop", 12, 0.5 }, fx_frostmist = { "OneShot", 16, 0.3 },
	fx_petals = { "Loop", 16, 0.3 }, fx_leaves = { "Loop", 16, 0.15 }, fx_thorn = { "OneShot", 24, 0.2 },
	fx_rock = { "Loop", 16, 0 }, fx_dust = { "OneShot", 16, 0 }, fx_crack = { "OneShot", 20, 0.6 },
	-- (Task 9 Studio: fully additive, the golden stars / rays summed to a white flare on the pale arena; half-lit they
	-- keep their gold)
	fx_sparks = { "Loop", 24, 1 }, fx_stormcloud = { "Loop", 12, 0.1 }, fx_stars = { "Loop", 16, 0.5 },
	fx_rays = { "OneShot", 20, 0.5 }, fx_sparkle = { "Loop", 16, 1 }, fx_wisps = { "Loop", 16, 0.4 },
	fx_voidring = { "OneShot", 20, 0.5 }, fx_darkglass = { "Loop", 16, 0.2 }, fx_slash = { "OneShot", 30, 1 },
	fx_shock = { "OneShot", 20, 0.9 }, fx_glow = { "Loop", 12, 1 }, fx_streak = { "Loop", 24, 1 },
	fx_hexshield = { "Loop", 16, 0.8 },
}

local sin, cos, abs, min, max, floor, sqrt, huge, pi = math.sin, math.cos, math.abs, math.min, math.max, math.floor, math.sqrt, math.huge, math.pi
local TAU = 2 * pi
local V3 = Vector3.new
local UP = V3(0, 1, 0)
local ONE = V3(1, 1, 1)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

----------------------------------------------------------------------
-- Helpers: easing, numbers
----------------------------------------------------------------------
local function clamp01(x)
	if x ~= x or x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- 0..1 progress of t through [a, b] (an empty window is a step at a)
local function seg(t, a, b)
	if b <= a then
		return (t >= a) and 1 or 0
	end
	return clamp01((t - a) / (b - a))
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function outCubic(x)
	x = 1 - clamp01(x)
	return 1 - x * x * x
end

-- ease out with an overshoot (~1.1) that settles at 1
local function outBack(x)
	x = clamp01(x)
	if x == 0 then
		return 0
	end
	local s = 1.70158
	x = x - 1
	return 1 + (s + 1) * x * x * x + s * x * x
end

local function hash(i, salt)
	local h = sin(i * 12.9898 + (salt or 0) * 78.233) * 43758.5453
	return h - floor(h)
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

local function flat(v)
	return V3(v.X, 0, v.Z)
end

-- CFrame at pos looking along dir (-Z = dir), safe when dir is vertical
local function face(pos, dir)
	if dir.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	dir = dir.Unit
	if abs(dir.Y) > 0.985 then
		return CFrame.lookAt(pos, pos + dir, V3(0, 0, -1))
	end
	return CFrame.lookAt(pos, pos + dir)
end

local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local function material(name)
	if type(name) == "string" then
		local ok, m = pcall(function()
			return Enum.Material[name]
		end)
		if ok and m then
			return m
		end
	end
	return Enum.Material.Neon
end

----------------------------------------------------------------------
-- Dependencies (lazy; _Deps overrides them in tests)
----------------------------------------------------------------------
local deps = {}
local mods = {}

local function loadModule(parent, name)
	local m = mods[name]
	if m == nil then
		m = false
		local inst = parent and parent:FindFirstChild(name)
		if inst then
			local ok, result = pcall(require, inst)
			if ok and type(result) == "table" then
				m = result
			end
		end
		mods[name] = m
	end
	return m or nil
end

local function dep(name)
	local o = deps[name]
	if o then
		return o
	end
	if name == "GraphicsQuality" then
		return loadModule(Client, name)
	end
	return loadModule(ReplicatedStorage:FindFirstChild("Shared"), name)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	live = {}, -- live effects, in play order
	poses = {}, -- unitId -> { Segs, Prio, Prev?, SwitchAt? }
	pool = { Emitter = {}, Beam = {}, Trail = {}, Light = {}, Disc = {} },
	corePool = {}, -- key -> { kits }
	forced = nil, -- SetQuality's mode (nil = GraphicsQuality)
	mode = nil, -- the mode applied to the live effects
	now = nil, -- the last Update clock
	folder = nil,
	errors = 0,
	warned = {},
}

local function warnOnce(key, msg)
	if not St.warned[key] then
		St.warned[key] = true
		warn("[AttackFx] " .. tostring(msg))
	end
end

local function ensureFolder()
	local f = St.folder
	if f and f.Parent and f.Parent.Parent == Workspace then
		return f
	end
	-- the folder is gone (a battle clean-up destroyed ClientBattle): the pooled kits went with it
	St.pool = { Emitter = {}, Beam = {}, Trail = {}, Light = {}, Disc = {} }
	St.corePool = {}
	local root = Workspace:FindFirstChild(K.PARENT)
	if not root then
		root = Instance.new("Folder")
		root.Name = K.PARENT
		root.Parent = Workspace
	end
	f = root:FindFirstChild(K.FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = K.FOLDER
		f.Parent = root
	end
	St.folder = f
	return f
end

----------------------------------------------------------------------
-- Kits
----------------------------------------------------------------------
local function hostPart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Transparency = 1
	p.Size = V3(0.2, 0.2, 0.2)
	return p
end

local NEW = {}

function NEW.Emitter(folder)
	local host = hostPart("FxEmitter")
	local em = Instance.new("ParticleEmitter")
	em.Name = "Fx"
	em.Enabled = false
	em.Rate = 0
	em.Parent = host
	host.Parent = folder
	return { Kind = "Emitter", Root = host, Em = em, N = 2 }
end

function NEW.Beam(folder)
	local h0 = hostPart("FxBeam")
	local h1 = hostPart("FxBeamEnd")
	h1.Parent = h0
	local a0 = Instance.new("Attachment")
	a0.Parent = h0
	local a1 = Instance.new("Attachment")
	a1.Parent = h1
	local b = Instance.new("Beam")
	b.Enabled = false
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightInfluence = 0
	b.Parent = h0
	h0.Parent = folder
	return { Kind = "Beam", Root = h0, H1 = h1, Beam = b, N = 5 }
end

function NEW.Trail(folder)
	local h = hostPart("FxTrail")
	local a0 = Instance.new("Attachment")
	a0.Position = V3(0, 0.5, 0)
	a0.Parent = h
	local a1 = Instance.new("Attachment")
	a1.Position = V3(0, -0.5, 0)
	a1.Parent = h
	local tr = Instance.new("Trail")
	tr.Enabled = false
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Parent = h
	h.Parent = folder
	return { Kind = "Trail", Root = h, A0 = a0, A1 = a1, Trail = tr, N = 4 }
end

function NEW.Light(folder)
	local h = hostPart("FxLight")
	local l = Instance.new("PointLight")
	l.Enabled = false
	l.Brightness = 0
	l.Shadows = false
	l.Parent = h
	h.Parent = folder
	return { Kind = "Light", Root = h, Light = l, N = 2 }
end

function NEW.Disc(folder)
	local d = hostPart("FxDisc")
	d.Shape = Enum.PartType.Cylinder
	d.Material = Enum.Material.Neon
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Right -- the cylinder's end cap: up once the disc lies flat
	g.LightInfluence = 0
	g.CanvasSize = Vector2.new(64, 64)
	g.Parent = d
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.ImageTransparency = 1
	im.ImageRectOffset = Vector2.new(256, 256) -- fx_glow is a 4x4 flipbook sheet (1024 px): one frame, not all 16
	im.ImageRectSize = Vector2.new(256, 256)
	im.Parent = g
	d.Parent = folder
	return { Kind = "Disc", Root = d, Gui = g, Img = im, N = 3 }
end

local function coreReady(key)
	local ML = dep("MeshLibrary")
	if not (ML and type(ML.IsReady) == "function" and type(key) == "string") then
		return false
	end
	local ok, ready = pcall(ML.IsReady, key)
	return ok and ready == true
end

local function newCore(key, folder)
	local ML = dep("MeshLibrary")
	local ok, model = pcall(ML.Assemble, key, {}, {})
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local part = model:FindFirstChild("Core")
	if not (part and part:IsA("BasePart")) then
		part = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not part then
		model:Destroy()
		return nil
	end
	part.Parent = folder
	model:Destroy()
	part.Name = "FxCore_" .. key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	return { Kind = "Core", Key = key, Root = part, Base = part.Size, N = 1 }
end

local function take(kind, key)
	local folder = ensureFolder()
	if kind == "Core" and not coreReady(key) then
		return nil
	end
	local list = (kind == "Core") and St.corePool[key] or St.pool[kind]
	while list and #list > 0 do
		local kit = table.remove(list)
		if kit.Root.Parent == folder then
			return kit
		end
		pcall(kit.Root.Destroy, kit.Root)
	end
	if kind == "Core" then
		return newCore(key, folder)
	end
	return NEW[kind](folder)
end

local function hide(kit)
	local k = kit.Kind
	if k == "Emitter" then
		kit.Em.Enabled = false
		pcall(kit.Em.Clear, kit.Em)
		kit.Root.Size = V3(0.2, 0.2, 0.2)
	elseif k == "Beam" then
		kit.Beam.Enabled = false
	elseif k == "Trail" then
		kit.Trail.Enabled = false
		pcall(kit.Trail.Clear, kit.Trail)
	elseif k == "Light" then
		kit.Light.Enabled = false
		kit.Light.Brightness = 0
	else
		kit.Root.Transparency = 1
		if kit.Img then
			kit.Img.ImageTransparency = 1
		end
	end
end

local function give(kit)
	if not kit then
		return
	end
	pcall(hide, kit)
	local folder = St.folder
	local list, keep
	if kit.Kind == "Core" then
		list = St.corePool[kit.Key]
		if not list then
			list = {}
			St.corePool[kit.Key] = list
		end
		keep = K.CORE_KEEP
	else
		list, keep = St.pool[kit.Kind], K.KEEP[kit.Kind]
	end
	if folder and kit.Root.Parent == folder and #list < keep then
		list[#list + 1] = kit
	else
		pcall(kit.Root.Destroy, kit.Root)
	end
end

----------------------------------------------------------------------
-- Points of an effect (refreshed every frame)
----------------------------------------------------------------------
-- a side's point: the model's pivot while it is in the game, else its last known point, else Pos
local function pointOf(side)
	local m = side.Model
	if m then
		if m.Parent then
			local ok, cf = pcall(m.GetPivot, m)
			if ok and typeof(cf) == "CFrame" then
				side.Last = cf.Position
				return side.Last
			end
		else
			side.Model = nil -- destroyed / parked: keep its last known point
		end
	end
	if not side.Last and typeof(side.Pos) == "Vector3" then
		side.Last = side.Pos
	end
	return side.Last
end

local function groundOf(eff, p)
	return V3(p.X, p.Y - eff.Drop + 0.05, p.Z)
end

local function hitOf(eff)
	local hit
	if eff.Path == "Self" then
		hit = eff.S
	elseif eff.Path == "Allies" then
		hit = eff.T[1] or eff.S
	elseif eff.Area == "Cone" then
		hit = eff.S + eff.Dir * (eff.Reach * 0.6)
	elseif eff.Area == "Line" then
		hit = eff.S + eff.Dir * (eff.Reach * 0.5)
	elseif eff.Area == "Circle" then
		hit = eff.S
	else
		hit = eff.T[1] or (eff.S + eff.Dir * 8)
	end
	if eff.Miss and eff.Path ~= "Self" and eff.Path ~= "Allies" then
		hit = hit + eff.Dir * 2.5 + eff.Right * 1.2 -- a miss lands beside the target
	end
	return hit
end

local function refresh(eff)
	local s = pointOf(eff.Src)
	if s then
		eff.S = s
	end
	for i, side in ipairs(eff.Targets) do
		local p = pointOf(side)
		if p then
			eff.T[i] = p
		end
	end
	local first = eff.T[1]
	if first and not eff.Area then
		local d = flat(first - eff.S)
		if d.Magnitude > 0.2 then
			eff.Dir = d.Unit
		end
	end
	eff.Right = eff.Dir:Cross(UP)
	eff.Mouth = eff.S + eff.Dir * (K.MOUTH * eff.Size) + UP * 0.25
	eff.Hit = hitOf(eff)
end

-- fills `out` with the world points of an anchor; returns how many
local function atPoints(eff, at, out)
	local n = 1
	if at == "Source" then
		out[1] = eff.Mouth
	elseif at == "Core" then
		out[1] = eff.CorePos or eff.Hit
	elseif at == "Ground" then
		out[1] = groundOf(eff, eff.Hit)
	elseif at == "Above" then
		out[1] = eff.Hit + UP * (K.ABOVE * eff.Size)
	elseif at == "Behind" then
		out[1] = eff.S - eff.Dir * (K.BEHIND * eff.Size) + UP * 0.5
	elseif at == "Self" then
		out[1] = eff.S
	elseif at == "Allies" then
		n = 0
		for i = 1, min(#eff.T, K.MAX_ALLIES) do
			n = n + 1
			out[n] = eff.T[i]
		end
		if n == 0 then
			n = 1
			out[1] = eff.S
		end
	else
		out[1] = eff.Hit -- Target / Path / unknown
	end
	for i = #out, n + 1, -1 do
		out[i] = nil
	end
	return n
end

-- a solid piece's anchor point (+ its offsets in the effect's right / forward frame)
local function anchorPoint(eff, it)
	local a = it.Anchor
	local p
	if a == "Path" then
		p = eff.S:Lerp(eff.Hit, it.F or 1)
	elseif a == "Self" then
		p = eff.S
	elseif a == "Source" then
		p = eff.Mouth
	elseif a == "Above" then
		p = eff.Hit + UP * (K.ABOVE * eff.Size)
	elseif a == "Behind" then
		p = eff.S - eff.Dir * (K.BEHIND * eff.Size)
	elseif type(a) == "number" then
		p = eff.T[a] or eff.S
	else
		p = eff.Hit
	end
	return p + eff.Right * (it.OffR or 0) + eff.Dir * (it.OffD or 0)
end

-- where a projectile core is at t (also drives the layers At = "Core"); other paths: the hit point
local function corePosOf(eff, t)
	local core, T = eff.Recipe.Core, eff.Times
	if eff.Path ~= "Projectile" or core.Stretch then
		return eff.Hit
	end
	local launch = eff.Mouth
	if finite(core.Rise) then
		launch = launch + UP * (core.Rise * eff.Size)
	end
	if t <= T.Travel then
		return launch
	elseif t >= T.Impact then
		return eff.Hit
	end
	local u = seg(t, T.Travel, T.Impact)
	local arc = (finite(core.Rise) and 0 or 0.5) * eff.Size * sin(pi * u)
	return launch:Lerp(eff.Hit, u) + UP * arc
end

----------------------------------------------------------------------
-- Solid pieces (cores, rings, meshes, the signature actor): MOVE[...](eff, it, t) -> CFrame, scale (Vector3, x the
-- piece's base size x it.S), transparency; nil = hidden
----------------------------------------------------------------------
local MOVE = {}

local function fadeTo(it, f)
	return it.Trans + (1 - it.Trans) * f
end

MOVE.Projectile = function(eff, it, t)
	local T, core = eff.Times, eff.Recipe.Core
	local appear
	if it.Charged then -- the Blast orb grows above the pet through the charge
		appear = outBack(seg(t, 0, max(0.12, T.Release))) * (1 + 0.06 * sin(t * 30) * (1 - seg(t, T.Release - 0.05, T.Release)))
	else
		appear = outBack(seg(t, T.Release, T.Release + 0.08))
	end
	if appear <= 0 then
		return nil
	end
	-- (a basic ranged shot bursts into its explosion at once: Task 9 Studio, Water's orb lingering 0.2 s on the target,
	-- swelling, read as a bubble round it)
	local pop = eff.Recipe.Beats.MinTravel and seg(t, T.Impact, T.Impact + 0.08) or seg(t, T.Impact, T.Linger + 0.05)
	local pos = eff.CorePos
	local look = eff.Hit - pos
	if look.Magnitude < 0.05 then
		look = eff.Dir
	end
	local cf = face(pos, look)
	if core.Spin then
		cf = cf * CFrame.Angles(0, 0, t * 14)
	end
	if it.Role == "Twin" then
		cf = cf * CFrame.Angles(0, 0, pi / 2 + t * 6)
	end
	return cf, (it.Shape or ONE) * (appear * (1 + 0.5 * outCubic(pop))), fadeTo(it, smooth(pop))
end

MOVE.Stretch = function(eff, it, t)
	local T = eff.Times
	local p0 = eff.Mouth
	local p1 = it.Line and (eff.S + eff.Dir * eff.Reach + UP * 0.25) or eff.Hit
	local d = p1 - p0
	local L = d.Magnitude
	local grow = outCubic(seg(t, T.Travel - 0.02, T.Travel + max(0.08, T.Impact - T.Travel)))
	if L < 0.1 or grow <= 0 then
		return nil
	end
	local out = seg(t, T.Linger, eff.EndRel)
	local len = L * grow
	local th = (it.Thick or 1) * (1 + 0.1 * sin(t * 45)) * max(0.05, 1 - smooth(out))
	local c = p0 + d.Unit * (len / 2)
	return face(c, d), V3(th, th, len / max(0.01, it.Base.Z * it.S)), fadeTo(it, smooth(out) * 0.6)
end

MOVE.Swipe = function(eff, it, t)
	local T = eff.Times
	local t0 = T.Release + (it.Delay or 0)
	local appear = outBack(seg(t, t0, t0 + 0.08))
	if appear <= 0 then
		return nil
	end
	local u = outCubic(seg(t, t0, T.Impact + 0.05))
	local fade = smooth(seg(t, T.Impact + 0.03, it.T1))
	local pos = eff.Hit + UP * (0.9 * eff.Size) - eff.Dir * ((1.0 - 1.4 * u) * eff.Size)
	local yaw = (it.Mirror and -1 or 1) * (0.95 - 1.9 * u)
	local cf = face(pos, eff.Dir) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, it.Tilt or 0.55)
	return cf, (it.Shape or ONE) * (appear * (1 + 0.18 * fade)), fadeTo(it, fade)
end

-- erupts from the ground (spikes, roots, the cage, lava spikes), holds, sinks and fades
MOVE.Rise = function(eff, it, t)
	if t < it.TR then
		return nil
	end
	local base = groundOf(eff, anchorPoint(eff, it))
	local h = it.Base.Y * it.S
	local r = outBack(seg(t, it.TR, it.TR + 0.13))
	local sink = smooth(seg(t, it.TS, it.T1))
	local y = h * (r - 0.5) - h * 0.7 * sink
	return CFrame.new(base + UP * y) * (it.Rot or CFrame.new()), ONE, fadeTo(it, sink)
end

-- expands flat on the ground (shockwave, nova, slam ring) or round (the Blast dome)
MOVE.Ring = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local p = anchorPoint(eff, it)
	if it.Flat then
		p = groundOf(eff, p) + UP * 0.1
	end
	local g = it.From + (it.To - it.From) * outCubic(seg(t, it.T0, it.TG))
	local fade = smooth(seg(t, it.TF, it.T1))
	if it.Face then -- stood up across the attack's direction (the flat XZ ring turned to face eff.Dir)
		return face(p, eff.Dir) * CFrame.Angles(pi / 2, 0, 0), ONE * g, fadeTo(it, fade)
	end
	return CFrame.new(p) * CFrame.Angles(0, t * (it.Spin or 0), 0), ONE * g, fadeTo(it, fade)
end

-- a bubble / disc around an ally: pops in, ripples at the impact, fades out
MOVE.Shell = function(eff, it, t)
	local a = outBack(seg(t, it.T0, it.T0 + 0.2))
	if t < it.T0 or a <= 0 then
		return nil
	end
	local T = eff.Times
	local p = anchorPoint(eff, it)
	local ripple = 1 + 0.08 * sin(pi * seg(t, T.Impact, T.Impact + 0.3))
	local fade = smooth(seg(t, it.TF, it.T1))
	local cf = it.Disc and face(p, eff.Dir) or (CFrame.new(p) * CFrame.Angles(0, t * 0.8, 0))
	return cf, ONE * (a * ripple), fadeTo(it, fade)
end

-- a quick pop (the hurt flash, the KO poof)
MOVE.Pop = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local s = it.From + (it.To - it.From) * outCubic(u)
	return CFrame.new(anchorPoint(eff, it) + UP * 0.2), ONE * s, fadeTo(it, smooth(seg(u, 0.25, 1)))
end

-- the victory star: rises and spins
MOVE.Star = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local p = eff.S + UP * (0.8 + 2.6 * outCubic(u))
	return face(p, eff.Dir) * CFrame.Angles(0, t * 6, 0), ONE * outBack(seg(u, 0, 0.2)), fadeTo(it, smooth(seg(u, 0.7, 1)))
end

-- a fanned blade flying out (the Cone element attack)
MOVE.Fly = function(eff, it, t)
	local T = eff.Times
	if t < T.Release then
		return nil
	end
	local u = outCubic(seg(t, T.Release, T.Impact))
	local d = eff.Dir * cos(it.Ang) + eff.Right * sin(it.Ang)
	local p = eff.Mouth + d * (eff.Reach * 0.85 * u)
	local fade = smooth(seg(t, T.Impact, it.T1))
	return face(p, d), ONE * ((0.6 + 0.7 * u) * outBack(seg(t, T.Release, T.Release + 0.08))), fadeTo(it, fade)
end

-- a piece of the Storm special's rain: falls from the cloud, pops on landing
MOVE.Fall = function(eff, it, t)
	if t < it.TR then
		return nil
	end
	local land = groundOf(eff, eff.Hit + eff.Right * it.OffR + eff.Dir * it.OffD) + UP * 0.3
	local top = land + UP * (K.ABOVE * eff.Size + 2)
	local u = seg(t, it.TR, it.TR + it.Drop)
	local fade = seg(t, it.TR + it.Drop, it.TR + it.Drop + 0.15)
	if fade >= 1 then
		return nil
	end
	return face(top:Lerp(land, u * u), V3(0, -1, 0)), ONE * (1 + 0.4 * fade), fadeTo(it, fade)
end

-- the Frost alive detail: shards lying around the target visibly melt
MOVE.Melt = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local p = groundOf(eff, anchorPoint(eff, it)) + UP * (0.15 * it.S)
	local sv = V3(1 - 0.25 * u, max(0.05, 1 - 0.85 * u), 1 - 0.25 * u) * outBack(seg(u, 0, 0.12))
	return CFrame.new(p) * it.Rot, sv, fadeTo(it, smooth(seg(u, 0.45, 1)))
end

-- the Earth alive detail: chunks scatter and bounce once
MOVE.Bounce = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local q = t - it.T0
	local g = 30
	local tb = 2 * it.VY / g
	local y
	if q < tb then
		y = it.VY * q - 0.5 * g * q * q
	else
		local q2 = q - tb
		y = max(0, it.VY * 0.4 * q2 - 0.5 * g * q2 * q2)
	end
	local out = eff.Right * cos(it.Ang) + eff.Dir * sin(it.Ang)
	local p = groundOf(eff, eff.Hit) + out * (0.4 + it.VH * min(q, tb * 1.4)) + UP * (y + 0.3 * it.S)
	return CFrame.new(p) * CFrame.Angles(q * it.SX, q * it.SY, 0), ONE, fadeTo(it, smooth(seg(t, it.T1 - 0.25, it.T1)))
end

-- the signature actor (a vfx_sig_* piece) by its Motion
MOVE.Actor = function(eff, it, t)
	local T = eff.Times
	if t < it.T0 then
		return nil
	end
	local m = it.Motion
	local u = seg(t, it.T0, it.T1)
	local fade = smooth(seg(t, it.TF, it.T1))
	if m == "SpiralUp" then
		local top = eff.S + UP * (1 + 4.5 * eff.Size)
		local p, look
		if t < T.Travel then
			local v = seg(t, it.T0, T.Travel)
			local a = v * TAU * 1.5 + it.I
			p = eff.S + UP * (1 + 4.5 * eff.Size * smooth(v)) + (eff.Right * cos(a) + eff.Dir * sin(a)) * (1.8 * (1 - v))
			look = eff.Right * -sin(a) + eff.Dir * cos(a) + UP * 0.6
		else
			local v = seg(t, T.Travel, T.Impact)
			p = top:Lerp(eff.Hit, v * v)
			look = eff.Hit - top
		end
		return face(p, look), ONE * outBack(seg(t, it.T0, it.T0 + 0.2)), fadeTo(it, fade)
	elseif m == "ChargeThrough" then
		local p = eff.Mouth:Lerp(eff.Hit + eff.Dir * 3, outCubic(u))
		return face(p, eff.Dir), ONE * outBack(seg(u, 0, 0.15)), fadeTo(it, fade)
	elseif m == "Burst" then
		local p = eff.Hit + UP * 0.6
		return face(p, -eff.Dir) * CFrame.Angles(0, 0, t * 2), ONE * (0.2 + 1.2 * outCubic(seg(t, it.T0, it.T0 + 0.5))), fadeTo(it, fade)
	elseif m == "Sweep" then
		local p = eff.Hit + UP * (4 * eff.Size) + eff.Right * ((-6 + 12 * smooth(u)) * eff.Size)
		return face(p, eff.Right) * CFrame.Angles(0.3, 0, 0), ONE * outBack(seg(u, 0, 0.15)), fadeTo(it, fade)
	elseif m == "Orbit" then
		local center = (type(it.Anchor) == "number" and eff.T[it.Anchor]) or eff.Hit
		local a = it.I / it.N * TAU + t * 3
		local p = center + V3(cos(a) * 1.6 * eff.Size, 0.3 * sin(t * 4 + it.I), sin(a) * 1.6 * eff.Size)
		return CFrame.new(p) * CFrame.Angles(0, -a, 0), ONE * outBack(seg(t, it.T0, it.T0 + 0.2)), fadeTo(it, fade)
	elseif m == "RiseRoar" then
		local base = groundOf(eff, anchorPoint(eff, it))
		local h = it.Base.Y * it.S
		local r = outBack(seg(t, it.T0, it.T0 + 0.3))
		local nod = sin(pi * seg(t, T.Release, T.Release + 0.35))
		return face(base + UP * (h * (r - 0.5)) + eff.Dir * (0.5 * nod), eff.Dir) * CFrame.Angles(-0.35 * nod, 0, 0), ONE, fadeTo(it, fade)
	end
	-- Rise (and unknown motions): comes up into place, holds, fades
	local p = anchorPoint(eff, it) - UP * (3 * (1 - outCubic(seg(t, it.T0, it.T0 + 0.5))))
	return face(p, -eff.Dir), ONE * outBack(seg(t, it.T0, it.T0 + 0.25)), fadeTo(it, fade)
end

----------------------------------------------------------------------
-- Drawing the items every frame
----------------------------------------------------------------------
local DRAW = {}

function DRAW.Solid(eff, it, t)
	local part = it.Kit.Root
	if t < it.T0 or t >= it.T1 then
		if part.Transparency < 1 then
			part.Transparency = 1
		end
		return
	end
	local cf, sv, tr = it.Move(eff, it, t)
	if not cf or tr >= 0.995 then
		if part.Transparency < 1 then
			part.Transparency = 1
		end
		return
	end
	local b, s = it.Base, it.S
	part.Size = V3(max(0.05, b.X * sv.X * s), max(0.05, b.Y * sv.Y * s), max(0.05, b.Z * sv.Z * s))
	part.CFrame = cf
	part.Transparency = tr
	if it.Shift then -- the Secret core's colour-shifting rim: the shell breathing into the rim colour
		-- (Task 9 Studio: breathing from WHITE, every band 4 shell was drawn 50-80 % white whatever its colour: the white
		-- ball / white sheet; it breathes from its own colour now, the white plasma is the heart inside)
		local h, sat, v = it.Shift:ToHSV()
		local own = typeof(it.Color) == "Color3" and it.Color or WHITE
		part.Color = own:Lerp(Color3.fromHSV((h + 0.08 * sin(t * 5)) % 1, sat, v), 0.3 + 0.2 * sin(t * 9))
	end
end

local function emitAt(it, p, n)
	it.Kit.Root.CFrame = CFrame.new(p)
	it.Kit.Em:Emit(n)
end

function DRAW.Emitter(eff, it, t)
	if t < it.T0 then
		return
	end
	local pts = it.Pts
	if it.Mode == "Burst" then
		if it.Fired then
			return
		end
		it.Fired = true
		local n = atPoints(eff, it.At, pts)
		local each = max(1, floor(it.Count / sqrt(n) + 0.5))
		for i = 1, n do
			local p = pts[i]
			if it.Flat then
				-- (At "Ground" is already on the floor)
				p = ((it.At == "Ground") and p or groundOf(eff, p)) + UP * (0.04 + 0.01 * it.Index)
			end
			emitAt(it, p, each)
		end
		return
	end
	if t > it.T1 + 1e-6 then
		return
	end
	it.Acc = it.Acc + it.Rate * eff.Dt
	local k = floor(it.Acc)
	if k <= 0 then
		return
	end
	it.Acc = it.Acc - k
	local n = atPoints(eff, it.At, pts)
	local u = seg(t, it.T0, it.T1)
	for i = 1, n do
		local p = pts[i]
		if it.Stream == "Spiral" then
			local a = t * 8 + i * 2.1
			p = p + V3(cos(a) * 1.2 * eff.Size, (u * 2.2 - 0.6) * eff.Size, sin(a) * 1.2 * eff.Size)
		elseif it.Stream == "Alive" then
			p = groundOf(eff, p) + UP * 0.2
		end
		emitAt(it, p, max(1, floor(k / sqrt(n) + 0.5)))
	end
end

-- beam end points by mode; returns p0, p1, axis (the curve direction) or nil
local BEAM = {}

function BEAM.Path(eff, it, t)
	local p0, p1 = eff.Mouth, eff.Hit
	local grow = outCubic(seg(t, it.T0, it.T0 + max(0.06, (eff.Times.Impact - it.T0) * 0.5)))
	-- (Task 9 Studio, Storm s3: grown on its own clock toward the target's pivot, the bolt raced ahead of the shot, low
	-- over the floor: on a flying shot the strip runs from the mouth to the shot itself, then to the hit)
	local core = eff.Recipe and eff.Recipe.Core
	if eff.Path == "Projectile" and eff.CorePos and not (core and core.Stretch) then
		p1 = (t < eff.Times.Impact) and eff.CorePos or eff.Hit
		grow = 1
	end
	if it.I > 1 or it.Jitter then -- extra bolts jump about the main one
		local f = floor(t * 20) + it.I * 7
		local j = (hash(f, 1) - 0.5) * 1.6 * eff.Size
		local k = (hash(f, 2) - 0.5) * 1.2 * eff.Size
		p0 = p0 + eff.Right * j * 0.4
		p1 = p1 + eff.Right * j + UP * k
	end
	return p0, p0:Lerp(p1, grow), eff.Right
end

function BEAM.Arc(eff, it, t)
	local f = floor(t * 14) + it.I * 13
	local a = hash(f, 3) * TAU
	local c = eff.Hit + V3(cos(a) * 1.2 * eff.Size, (hash(f, 4) - 0.3) * 1.4 * eff.Size, sin(a) * 1.2 * eff.Size)
	local b = hash(f, 5) * TAU
	return c, c + V3(cos(b), hash(f, 6) - 0.5, sin(b)) * (1.6 * eff.Size), eff.Right
end

function BEAM.Crescent(eff, it, t)
	local u = outCubic(seg(t, it.T0, it.T0 + 0.18))
	local tilt = 1.5 - 1.2 * u
	local c = eff.Hit + UP * (0.8 * eff.Size)
	return c + eff.Right * (1.8 * eff.Size) + UP * (tilt * eff.Size * 0.5), c - eff.Right * (1.8 * eff.Size) - UP * (tilt * eff.Size * 0.3), eff.Dir
end

function BEAM.Strike(eff, it, t)
	local f = floor(t * 12) + it.I * 31
	if hash(f, 7) < 0.4 then
		return nil
	end
	local a = hash(it.I + floor(t * 3), 8) * TAU
	local g = groundOf(eff, eff.Hit) + V3(cos(a), 0, sin(a)) * ((1.6 + 1.4 * hash(it.I, 9)) * eff.Size)
	return g + UP * (6 * eff.Size) + V3(hash(f, 10) - 0.5, 0, hash(f, 11) - 0.5), g, eff.Right
end

-- the i-th star of the Celestial constellation around the hit point
local function constellationStar(eff, i)
	local a = hash(i, 12) * TAU
	local r = (1.4 + hash(i, 13)) * eff.Size
	return eff.Hit + V3(cos(a) * r, (1 + 1.6 * hash(i, 14)) * eff.Size, sin(a) * r)
end

function BEAM.Connect(eff, it, t)
	local p0, p1 = constellationStar(eff, it.I), constellationStar(eff, it.I + 1)
	local u = seg(t, it.T0 + (it.I - 1) * 0.08, it.T0 + (it.I - 1) * 0.08 + 0.2)
	if u <= 0 then
		return nil
	end
	return p0, p0:Lerp(p1, outCubic(u)), eff.Right
end

function DRAW.Beam(eff, it, t)
	local b = it.Kit.Beam
	if t < it.T0 or t > it.T1 then
		if b.Enabled then
			b.Enabled = false
		end
		return
	end
	local p0, p1, axis = BEAM[it.Mode](eff, it, t)
	if not p0 or (p1 - p0).Magnitude < 0.05 then
		if b.Enabled then
			b.Enabled = false
		end
		return
	end
	local fwd = axis.Unit
	local upv = (p1 - p0).Unit:Cross(fwd)
	if upv.Magnitude < 1e-3 then -- the beam runs along its curve axis: any perpendicular will do
		upv = fwd:Cross((abs(fwd.Y) < 0.9) and UP or V3(1, 0, 0))
	end
	it.Kit.Root.CFrame = CFrame.fromMatrix(p0, fwd, upv.Unit)
	it.Kit.H1.CFrame = CFrame.fromMatrix(p1, fwd, upv.Unit)
	local env = outCubic(seg(t, it.T0, it.T0 + 0.06)) * (1 - smooth(seg(t, it.T1 - 0.14, it.T1)))
	if it.Flicker then
		env = env * (0.6 + 0.4 * hash(floor(t * 30), it.I))
	end
	if it.Spiral then
		local c = it.Curve * sin(t * 14 + it.I * pi)
		b.CurveSize0 = c
		b.CurveSize1 = -c
	end
	b.Width0 = max(0.01, it.Width0 * env)
	b.Width1 = max(0.01, it.Width1 * env)
	if not b.Enabled then
		b.Enabled = true
	end
end

function DRAW.Trail(eff, it, t)
	local tr = it.Kit.Trail
	if t < it.T0 then
		return
	end
	if t > it.T1 then
		if tr.Enabled then
			tr.Enabled = false
		end
		return
	end
	local p, look
	local u = seg(t, it.T0, it.T1)
	if it.Mode == "Leap" then
		local g0, g1 = eff.S, eff.Hit
		p = g0:Lerp(g1, outCubic(u)) + UP * (1.6 * eff.Size * sin(pi * u)) + eff.Right * it.Side
		look = g1 - g0
	elseif it.Mode == "Wind" then
		local c = eff.T[it.Ally] or eff.S
		local a = u * TAU * 1.5 + it.Ally
		p = c + V3(cos(a) * 1.4 * eff.Size, (u * 1.6 - 0.6) * eff.Size, sin(a) * 1.4 * eff.Size)
		look = V3(-sin(a), 0, cos(a))
	else
		p = (eff.CorePos or eff.Hit) + eff.Right * it.Side
		look = eff.Hit - p
	end
	it.Kit.Root.CFrame = face(p, flat(look).Magnitude > 0.01 and look or eff.Dir)
	if not it.On then
		it.On = true
		pcall(tr.Clear, tr)
		tr.Enabled = true
	end
end

function DRAW.Light(eff, it, t)
	local l = it.Kit.Light
	if t < it.T0 or t > it.T1 then
		if l.Enabled then
			l.Enabled = false
		end
		return
	end
	local n = atPoints(eff, it.At, it.Pts)
	local p = it.Pts[1]
	if n > 1 then
		local sum = V3(0, 0, 0)
		for i = 1, n do
			sum = sum + it.Pts[i]
		end
		p = sum / n
	end
	it.Kit.Root.CFrame = CFrame.new(p + UP * 0.5)
	local b
	if it.Pulse then
		b = it.B * (0.65 + 0.35 * sin(t * 28)) * sin(pi * seg(t, it.T0, it.T1))
	else
		b = it.B * seg(t, it.T0, it.T0 + 0.04) * (1 - smooth(seg(t, it.T0 + 0.04, it.T1)))
	end
	if it.Shift then
		local h, s, v = it.Color:ToHSV()
		l.Color = Color3.fromHSV((h + t * 0.8) % 1, s, v)
	end
	l.Brightness = max(0, b)
	if not l.Enabled then
		l.Enabled = true
	end
end

function DRAW.Disc(eff, it, t)
	local d = it.Kit.Root
	if t < it.T0 or t > it.T1 then
		if d.Transparency < 1 then
			d.Transparency = 1
		end
		if it.Soft and it.Kit.Img.ImageTransparency < 1 then
			it.Kit.Img.ImageTransparency = 1
		end
		return
	end
	atPoints(eff, it.At, it.Pts)
	local p = it.Pts[1]
	if it.At ~= "Ground" then -- (At "Ground" is already on the floor)
		p = groundOf(eff, p)
	end
	p = p + UP * (0.03 + 0.008 * it.Index)
	local g = (0.55 + 0.45 * outCubic(seg(t, it.T0, it.T0 + 0.15))) * (1 + 0.1 * seg(t, it.T0, it.T1))
	local size = it.D * g
	d.Size = V3(0.06, size, size)
	d.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, pi / 2)
	local tr = fadeTo(it, smooth(seg(t, it.T0 + (it.T1 - it.T0) * 0.4, it.T1)))
	if it.Soft then
		it.Kit.Img.ImageTransparency = tr
	else
		d.Transparency = tr
	end
end

----------------------------------------------------------------------
-- Building an effect's items
----------------------------------------------------------------------
local function beatStart(eff, beat)
	local T = eff.Times
	if beat == "Charge" then
		return 0
	end
	return T[beat] or T.Impact
end

local function beatEnd(eff, beat)
	local T = eff.Times
	if beat == "Charge" then
		return T.Release
	elseif beat == "Release" then
		return T.Travel
	elseif beat == "Travel" then
		return T.Impact
	elseif beat == "Impact" then
		return T.Linger
	end
	return eff.EndRel
end

local function addItem(eff, it)
	it.Index = #eff.Items + 1
	eff.Items[it.Index] = it
	return it
end

local function addSolid(eff, key, it)
	if eff.Cores >= AttackFx.MAX_CORES then
		return nil
	end
	local kit = take("Core", key)
	if not kit then
		return nil
	end
	eff.Cores = eff.Cores + 1
	kit.Root.Color = it.Color or WHITE
	kit.Root.Material = it.Material or Enum.Material.Neon
	kit.Root.Transparency = 1
	it.Kind = "Solid"
	it.Kit = kit
	it.Base = kit.Base
	it.Fn = DRAW.Solid
	it.S = it.S or eff.Size
	it.Trans = it.Trans or 0
	it.T0 = it.T0 or 0
	it.T1 = min(it.T1 or eff.EndRel, eff.EndRel)
	return addItem(eff, it)
end

-- the core of the recipe, by its Path
local function buildCore(eff)
	local r = eff.Recipe
	local core, T = r.Core, eff.Times
	local key, path = core.Key, core.Path
	if type(key) ~= "string" then
		return
	end
	local S = eff.Size * (finite(core.Scale) and core.Scale or 1)
	local mat = material(core.Material)
	local trans = finite(core.Transparency) and core.Transparency or 0
	local function look(extra)
		local it = { Color = core.Color, Material = mat, Trans = trans, S = S, Shift = core.RimShift and core.RimColor or nil }
		for k, v in pairs(extra) do
			it[k] = v
		end
		return it
	end
	local endImpact = T.Linger + 0.06
	if path == "Projectile" then
		if core.Stretch then
			addSolid(eff, key, look({ Move = MOVE.Stretch, T0 = T.Travel - 0.02, Thick = core.Thick or 1 }))
			return
		end
		local charged = core.Grow == true or finite(core.Rise)
		local t0 = charged and 0 or T.Release
		-- core.Girth: the shot's width x (its length stays: a thick bolt, not a longer spear)
		local girth = (finite(core.Girth) and core.Girth > 0) and V3(core.Girth, core.Girth, 1) or ONE
		local main = addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Shape = girth }))
		if main and core.InnerColor then -- band 2+: a hot inner core showing through
			main.Trans = max(main.Trans, 0.35)
			addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Color = core.InnerColor, Material = Enum.Material.Neon, Trans = 0, Shift = false, S = S * 0.55, Shape = girth }))
		end
		if core.Upgraded then -- band 3+: fins (the twin turned a quarter)
			addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Role = "Twin", Shape = V3(0.75, 0.75, 1.1) * girth, Color = core.RimColor or core.InnerColor or core.Color }))
		end
	elseif path == "Swipe" then
		local t1 = T.Linger + 0.2
		local main = addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1 }))
		if main and core.InnerColor then
			main.Trans = max(main.Trans, 0.3)
			addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1, Color = core.InnerColor, Material = Enum.Material.Neon, Trans = 0, Shift = false, Shape = V3(0.8, 0.6, 0.55) }))
		end
		if core.Upgraded then -- band 3+: a second blade, mirrored and a beat late
			addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1 + 0.06, Delay = 0.06, Mirror = true, Tilt = -0.55, S = S * 0.85, Color = core.RimColor or core.InnerColor or core.Color }))
		end
	elseif path == "Ground" then
		if key == "vfx_ring" then -- the Pounce slam: a ring races out over the ground
			addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, T0 = T.Impact, TG = T.Linger + 0.25, TF = T.Impact + 0.1, T1 = T.Linger + 0.45, From = 0.3, To = finite(core.Grow) and core.Grow or 3 }))
			return
		end
		local n = min(6, finite(core.Count) and core.Count or 1)
		local around = (key == "vfx_root") or n == 1
		local travel = max(0.05, T.Impact - T.Travel)
		for i = 1, n do
			local it = look({ Move = MOVE.Rise, T0 = 0, TS = T.Linger + (eff.EndRel - T.Linger) * 0.3, T1 = eff.EndRel })
			if around then
				local a = (i - 1) / n * TAU + hash(i, 21)
				local rad = (n == 1) and 0 or 0.9 * eff.Size
				it.Anchor, it.OffR, it.OffD = "Hit", cos(a) * rad, sin(a) * rad
				it.TR = T.Travel + travel * 0.6 * (i - 1) / max(1, n - 1)
				it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), (n == 1) and 0 or -0.35) * CFrame.Angles(0, hash(i, 22) * TAU, 0)
			else -- spikes along the path, alternating sides
				local f = 0.35 + 0.65 * (i - 1) / max(1, n - 1)
				it.Anchor, it.F, it.OffR = "Path", f, ((i % 2 == 0) and 0.45 or -0.45) * eff.Size
				it.TR = T.Travel + travel * (i - 1) / max(1, n - 1) * 0.85
				it.Rot = CFrame.Angles((hash(i, 23) - 0.5) * 0.4, hash(i, 24) * TAU, (hash(i, 25) - 0.5) * 0.4)
			end
			if core.KeepMaterial then -- the Freeze cage rises a little slower
				it.TR = T.Travel
			end
			addSolid(eff, key, it)
		end
	elseif path == "Area" then
		local travel = max(0.05, T.Impact - T.Travel)
		if core.Fall then -- the Storm special: the element rains out of the cloud
			local n = min(8, finite(core.Count) and core.Count or 6)
			for i = 1, n do
				local a, rad = hash(i, 31) * TAU, (0.4 + 2.6 * hash(i, 32)) * eff.Size
				addSolid(eff, key, look({ Move = MOVE.Fall, T0 = T.Travel, TR = T.Travel + travel * 0.9 * hash(i, 33), Drop = 0.3, OffR = cos(a) * rad, OffD = sin(a) * rad, T1 = T.Linger + 0.3 }))
			end
		elseif core.Fan then
			local n = min(5, finite(core.Count) and core.Count or 3)
			for i = 1, n do
				local ang = (n == 1) and 0 or (-0.45 + 0.9 * (i - 1) / (n - 1))
				addSolid(eff, key, look({ Move = MOVE.Fly, T0 = T.Release, T1 = T.Linger + 0.15, Ang = ang, Trans = (i == (n + 1) / 2) and trans or max(trans, 0.25) }))
			end
		elseif core.Stretch then
			-- (the recipe's Core.Thick wins: Task 8, the Line core was always 1.2 thick whatever the catalog said)
			addSolid(eff, key, look({ Move = MOVE.Stretch, T0 = T.Travel - 0.02, Line = true, Thick = finite(core.Thick) and core.Thick or 1.2 }))
		elseif key == "vfx_ring" then -- the Circle nova
			local to = (eff.Reach * 2) / 4 / max(0.1, S)
			addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = "Self", T0 = T.Travel, TG = T.Impact + 0.1, TF = T.Impact, T1 = T.Linger + 0.35, From = 0.3, To = to }))
		else -- the ground elements' spikes / roots over the attack's shape
			local n = min(6, finite(core.Count) and core.Count or 4)
			for i = 1, n do
				local it = look({ Move = MOVE.Rise, T0 = 0, TS = T.Linger + (eff.EndRel - T.Linger) * 0.3, T1 = eff.EndRel, Anchor = "Self" })
				local f = (i - 0.5) / n
				if eff.Area == "Circle" then
					local a = f * TAU
					it.OffR, it.OffD = cos(a) * eff.Reach * 0.6, sin(a) * eff.Reach * 0.6
				else
					local spread = (eff.Area == "Cone") and (((i % 2 == 0) and 1 or -1) * f * eff.Reach * 0.35) or (((i % 2 == 0) and 0.4 or -0.4) * eff.Size)
					it.OffR, it.OffD = spread, (0.15 + 0.85 * f) * eff.Reach
				end
				it.TR = T.Travel + travel * f
				it.Rot = CFrame.Angles((hash(i, 26) - 0.5) * 0.4, hash(i, 27) * TAU, (hash(i, 28) - 0.5) * 0.4)
				addSolid(eff, key, it)
			end
		end
	elseif path == "Self" then
		if key == "vfx_ring" then -- the Rally roar: rings pulse outward
			local n = min(3, finite(core.Pulses) and core.Pulses or 1)
			local span = max(0.2, T.Linger - T.Travel)
			for i = 1, n do
				local t0 = T.Travel + span * (i - 1) / n
				addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = "Self", T0 = t0, TG = t0 + 0.45, TF = t0 + 0.1, T1 = t0 + 0.55, From = 0.3, To = finite(core.Grow) and core.Grow or 3 }))
			end
		elseif core.Flash or core.Poof then
			addSolid(eff, key, look({ Move = MOVE.Pop, Anchor = "Self", T0 = 0, T1 = core.Poof and min(eff.EndRel, 0.7) or min(eff.EndRel, 0.3), From = core.Poof and 0.8 or 0.6, To = core.Poof and 2 or 1.6, Trans = core.Poof and 0.3 or 0.15 }))
		else
			addSolid(eff, key, look({ Move = MOVE.Star, T0 = T.Travel, T1 = eff.EndRel }))
		end
	elseif path == "Allies" then
		local n = min(K.MAX_ALLIES, max(1, #eff.T))
		for i = 1, n do
			if key == "vfx_ring" then
				addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = i, T0 = T.Travel, TG = T.Impact + 0.1, TF = T.Linger, T1 = eff.EndRel, From = 0.4, To = finite(core.Grow) and core.Grow or 1.5, Spin = 1.5 }))
			else
				local disc = string.find(key, "disc", 1, true) ~= nil
				addSolid(eff, key, look({ Move = MOVE.Shell, Anchor = i, OffD = disc and 1.2 * eff.Size or 0, Disc = disc, T0 = T.Travel, TF = T.Linger + (eff.EndRel - T.Linger) * 0.5, T1 = eff.EndRel }))
			end
		end
	end
end

-- the emitter layers this effect can afford, best first (the impact burst, then the impact detail ...); `keep` = the
-- recipe's LowKeep ({ [id] = order }) at Low quality: the element's chosen layer comes right after the Burst
local function emitterRank(layer, keep)
	if layer.Id == "Burst" then
		return 0
	elseif keep and keep[layer.Id] then
		return 0.5 + keep[layer.Id] * 0.01
	elseif layer.Beat == "Impact" then
		return 1
	elseif layer.Id == "Slash" then
		return 2
	elseif layer.Beat == "Travel" then
		return 3
	elseif layer.Alive then
		return 4
	elseif layer.Beat == "Linger" or layer.Beat == "Release" then
		return 5
	end
	return 6
end

local function isEmitter(layer)
	return layer.Kind == "Emitter" or (layer.Kind == "Decal" and type(layer.Texture) == "string")
end

-- the beams a Beam layer asks for (addBeamLayer draws at most this many)
local function beamWant(layer)
	return min(3, max(1, finite(layer.Count) and floor(layer.Count) or 1))
end

-- the beam layers this effect can afford, best first, like emitterRank (Task 9 review I1 / M6: built in catalog order
-- with the alive detail appended last, Storm's own Bolt + Crackle took all 4 beams from Rare up and its stray strikes
-- and the Mythic ShotArcs never drew; the Celestial Secret shot drew 1 of its 3 constellation lines): the alive detail,
-- then the recipe's own beams (the element's / attack's / kind's / signature's), then the rarity ladder's arcs
-- (DoubleArc / ShotArcs: a LayerSlots template)
local function beamRank(layer, slots)
	if layer.Alive then
		return 0
	elseif slots and slots[layer.Id] then
		return 2
	end
	return 1
end

-- how many beams each Beam layer gets ({ [layer] = n }) under `cap`: one each first, best first (every beam layer is
-- seen while there is room), then the rest of each layer's own count, best first (the alive detail fills up first)
local function beamBudget(layers, cap)
	local catalog = dep("AttackFxCatalog")
	local slots = type(catalog) == "table" and catalog.LayerSlots or nil
	local ranked = {}
	for i, layer in ipairs(layers) do
		if layer.Kind == "Beam" then
			ranked[#ranked + 1] = { L = layer, R = beamRank(layer, slots), I = i, N = beamWant(layer) }
		end
	end
	table.sort(ranked, function(a, b)
		if a.R ~= b.R then
			return a.R < b.R
		end
		return a.I < b.I
	end)
	local give, left = {}, cap
	for _, e in ipairs(ranked) do
		if left <= 0 then
			break
		end
		give[e.L], left = 1, left - 1
	end
	for _, e in ipairs(ranked) do
		if left <= 0 then
			break
		end
		local g = give[e.L]
		if g and e.N > g then
			local more = min(e.N - g, left)
			give[e.L], left = g + more, left - more
		end
	end
	return give
end

-- a charge glow at the mouth with no charge shown (shortened to fit the event): drawn by nobody, so it never takes
-- one of the effect's emitter slots
local function chargeDropped(eff, layer)
	return (layer.Beat or "Impact") == "Charge" and layer.At == "Source" and not layer.Alive and layer.Kind ~= "Decal"
		and eff.Times.Release <= 0.02
end

local function resetEmitter(em)
	em.Shape = Enum.ParticleEmitterShape.Box
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	em.EmissionDirection = Enum.NormalId.Top
	em.Orientation = Enum.ParticleOrientation.FacingCamera
	em.SpreadAngle = Vector2.new(180, 180)
	em.Acceleration = V3(0, 0, 0)
	em.Drag = 0
	em.LockedToPart = false
	em.VelocityInheritance = 0
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-60, 60)
	em.ZOffset = 0
	em.TimeScale = 1
	em.Brightness = 1
	em.Rate = 0
	em.Enabled = false
end

-- the emitter's look and motion for this layer (once per play, never per frame)
local function tuneEmitter(eff, it, layer)
	local kit = it.Kit
	local em, host = kit.Em, kit.Root
	resetEmitter(em)
	host.Size = V3(0.2, 0.2, 0.2)
	local key = layer.Texture
	local id = dep("TextureIds")[key]
	em.Texture = "rbxassetid://" .. tostring(id)
	local sheet = SHEETS[key] or { "Loop", 16, 0.5 }
	em.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	em.FlipbookMode = Enum.ParticleFlipbookMode[sheet[1]]
	em.FlipbookFramerate = NumberRange.new(sheet[2])
	em.FlipbookStartRandom = sheet[1] == "Loop"
	-- a layer's LightEmission overrides the sheet's (Task 9: the slash arc half-lit, so it keeps the element's colour)
	local own = finite(layer.LightEmission)
	em.LightEmission = own and clamp01(layer.LightEmission) or sheet[3]
	em.LightInfluence = (own or sheet[3] >= 0.5) and 0 or 0.6
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	if sheet[3] >= 0.8 then
		em.Color = ColorSequence.new(c:Lerp(WHITE, 0.45), c) -- glows start hot
	else
		em.Color = ColorSequence.new(c, c:Lerp(BLACK, 0.2))
	end
	local S = eff.Size
	local sz = (finite(layer.Size) and layer.Size or 1) * S * (eff.Strong and 1.12 or 1)
	local m = it.Preset
	local life = { 0.35, 0.6 }
	local sizeSeq = { 0.4, 1, 0.7 }
	local hold = 0.55
	local start = 0.1
	em.Speed = NumberRange.new(2.5 * S, 5.5 * S)
	em.Drag = 5
	em.Acceleration = V3(0, -3, 0)
	em.ZOffset = 0.4
	if m == "Shatter" then
		em.Speed = NumberRange.new(5 * S, 9 * S)
		em.Drag = 3
		em.Acceleration = V3(0, -22, 0)
		em.RotSpeed = NumberRange.new(-220, 220)
		life = { 0.45, 0.7 }
	elseif m == "Geyser" or m == "Erupt" then -- an upward column (Task 9: a fountain of drops rising from a patch of
		-- ground round the hit, not one clump: at the impact frame a single point read as a bubble)
		-- (round 3, Gemini: at +0.16 s the 2.2-stud patch of rising sheets still caged the target like a bubble: a narrow
		-- base under the target that fans OUT in a V, so the spray bursts away from it)
		host.Size = V3(1.2 * S, 0.3, 1.2 * S)
		em.SpreadAngle = Vector2.new(34, 34)
		em.Speed = NumberRange.new(13 * S, 19 * S)
		em.Drag = 0.5
		em.Acceleration = V3(0, -30, 0)
		life = { 0.5, 0.7 }
		sizeSeq = { 0.5, 1, 0.85 }
	elseif m == "Implode" then -- pulled inward to the centre (Task 9: from a 3.2-stud shell, 4.5 swallowed the target)
		host.Size = V3(3.2, 3.2, 3.2) * S
		em.Shape = Enum.ParticleEmitterShape.Sphere
		em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		em.SpreadAngle = Vector2.new(0, 0)
		em.Speed = NumberRange.new(7 * S, 10 * S)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		life = { 0.28, 0.36 }
		sizeSeq = { 1, 1, 0.25 }
	elseif m == "Fling" then
		em.SpreadAngle = Vector2.new(55, 55)
		em.Speed = NumberRange.new(6 * S, 10 * S)
		em.Drag = 0.5
		em.Acceleration = V3(0, -28, 0)
		life = { 0.5, 0.75 }
	elseif m == "Rise" then
		em.SpreadAngle = Vector2.new(25, 25)
		em.Speed = NumberRange.new(1.5 * S, 3 * S)
		em.Drag = 1
		em.Acceleration = V3(0, 1.5, 0)
		life = { 0.6, 0.95 }
		sizeSeq = { 0.5, 1, 1.3 }
	elseif m == "Slash" then -- one big arc, the sheet sweeps round
		em.Speed = NumberRange.new(0, 0)
		em.SpreadAngle = Vector2.new(0, 0)
		em.Acceleration = V3(0, 0, 0)
		em.Rotation = NumberRange.new(-25, 25)
		em.RotSpeed = NumberRange.new(0, 0)
		em.ZOffset = 0.6
		life = { 0.22, 0.26 }
		sizeSeq = { 0.7, 1, 1.1 }
		start = 0
	elseif m == "Flat" then -- a ground-flat sheet (Decal layers): faces up, stays put
		em.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		em.SpreadAngle = Vector2.new(0, 0)
		em.Speed = NumberRange.new(0.01, 0.01)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		em.RotSpeed = NumberRange.new(0, 0)
		em.ZOffset = 0
		local secs = finite(layer.Seconds) and layer.Seconds or 0.7
		life = { secs, secs }
		sizeSeq = { 0.55, 1, 1.1 }
		hold = 0.6
		start = 0.3
	elseif m == "Gather" then -- the charge glow: motes pulled in to the mouth
		host.Size = V3(3, 3, 3) * S
		em.Shape = Enum.ParticleEmitterShape.Sphere
		em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		em.Speed = NumberRange.new(3 * S, 4.5 * S)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		em.ZOffset = 0.2
		life = { 0.3, 0.42 }
		sizeSeq = { 0.3, 1, 0.2 }
	elseif m == "Cloud" then
		host.Size = V3(4 * S, 0.6, 4 * S)
		em.Speed = NumberRange.new(0.3, 0.8)
		em.Drag = 1
		em.Acceleration = V3(0, 0, 0)
		em.ZOffset = 0
		life = { 0.9, 1.3 }
		sizeSeq = { 0.6, 1, 1.15 }
		start = 0.25
		hold = 0.7
	elseif m == "Trail" then
		em.Speed = NumberRange.new(0.4, 1.4)
		em.Drag = 2
		em.Acceleration = V3(0, 0.8, 0)
		em.ZOffset = 0.2
		life = { 0.3, 0.5 }
	elseif m == "Spiral" then
		em.SpreadAngle = Vector2.new(15, 15)
		em.Speed = NumberRange.new(1, 2)
		em.Drag = 0.5
		em.Acceleration = V3(0, 1, 0)
		life = { 0.5, 0.8 }
	elseif m == "Fall" then
		host.Size = V3(6 * S, 0.4, 6 * S)
		em.EmissionDirection = Enum.NormalId.Bottom
		em.SpreadAngle = Vector2.new(6, 6)
		em.Speed = NumberRange.new(12, 16)
		em.Drag = 0
		em.Acceleration = V3(0, -10, 0)
		life = { 0.45, 0.6 }
	elseif m == "Bounce" then
		host.Size = V3(2.4 * S, 0.2, 2.4 * S)
		em.SpreadAngle = Vector2.new(35, 35)
		em.Speed = NumberRange.new(4, 6.5)
		em.Drag = 0
		em.Acceleration = V3(0, -26, 0)
		life = { 0.5, 0.7 }
	elseif m == "SwirlUp" then
		host.Size = V3(1.6 * S, 0.4, 1.6 * S)
		em.SpreadAngle = Vector2.new(20, 20)
		em.Speed = NumberRange.new(2, 4)
		em.Drag = 0.5
		em.Acceleration = V3(0, 2.5, 0)
		em.RotSpeed = NumberRange.new(-180, 180)
		life = { 0.6, 0.9 }
	end
	-- a layer's SpeedScale (Task 9: Earth's chunks flung further, so the break scatters instead of piling up)
	if finite(layer.SpeedScale) and layer.SpeedScale > 0 then
		em.Speed = NumberRange.new(em.Speed.Min * layer.SpeedScale, em.Speed.Max * layer.SpeedScale)
	end
	-- particles end with the effect: the kit is reused right after it
	local latest = eff.EndRel - it.T1
	local hi = max(0.12, min(life[2], latest))
	local lo = min(life[1], hi)
	em.Lifetime = NumberRange.new(lo, hi)
	em.Size = NumberSequence.new({ kp(0, sz * sizeSeq[1]), kp(0.2, sz * sizeSeq[2]), kp(1, sz * sizeSeq[3]) })
	-- (a layer's Transparency lifts the whole curve: Task 9, the band 4 ladder layers washed out the leap and the target)
	local a = finite(layer.Transparency) and clamp01(layer.Transparency) or 0
	em.Transparency = NumberSequence.new({ kp(0, a + (1 - a) * start), kp(0.12, a), kp(hold, a + (1 - a) * 0.1), kp(1, 1) })
end

local EMITTER_MOTIONS = { Geyser = true, Implode = true, Fling = true, Rise = true, Shatter = true, Erupt = true, Burst = true, Bounce = true, SwirlUp = true }

local function addEmitterLayer(eff, layer)
	local T = eff.Times
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = beatEnd(eff, beat)
	local mode, preset, stream = "Burst", "Burst", nil
	local at = layer.At
	if layer.Kind == "Decal" then
		preset = "Flat"
	elseif layer.Alive then
		mode, stream = "Stream", "Alive"
		preset = (layer.Motion == "Bounce" or layer.Motion == "SwirlUp") and layer.Motion or "Rise"
		t1 = min(eff.EndRel - 0.1, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) * 0.6)
	elseif beat == "Charge" and at == "Source" then
		if chargeDropped(eff, layer) then
			return -- no charge shown (shortened to fit the event)
		end
		mode, preset = "Stream", "Gather"
	elseif beat == "Charge" and at == "Above" then
		mode, preset, t1 = "Stream", "Cloud", T.Travel + 0.05
	elseif layer.Spiral then
		mode, preset, stream = "Stream", "Spiral", "Spiral"
	elseif layer.Fall or layer.Id == "Rain" then
		mode, preset, at, t1 = "Stream", "Fall", "Above", T.Impact + 0.05
	elseif beat == "Travel" and at == "Core" then
		mode, preset = "Stream", "Trail"
	elseif layer.Id == "Slash" then
		preset = "Slash"
		if eff.Path == "Swipe" or eff.Path == "Ground" then
			at = "Target" -- the arc sweeps through the target
		end
	elseif EMITTER_MOTIONS[layer.Motion] then
		preset = layer.Motion
	end
	if mode == "Burst" then
		t1 = t0
	end
	t1 = max(t0, min(t1, eff.EndRel - 0.05))
	local kit = take("Emitter")
	eff.Emitters = eff.Emitters + 1
	local count = (finite(layer.Count) and layer.Count or 1) * eff.Recipe.Density * (eff.Low and K.LOW_COUNT or 1)
	if eff.Crit and beat == "Impact" then
		count = count * 1.3
	end
	count = max(1, floor(count + 0.5))
	if preset == "Flat" then
		count = 1
	end
	local it = addItem(eff, {
		Kind = "Emitter", Kit = kit, Layer = layer, At = at, T0 = t0, T1 = t1, Mode = mode, Preset = preset, Stream = stream,
		Count = count, Rate = count / max(0.05, t1 - t0), Acc = 1, Pts = {}, Flat = preset == "Flat", Fn = DRAW.Emitter,
	})
	tuneEmitter(eff, it, layer)
end

-- `allow` = the beams beamBudget gave this layer (nil = its own count)
local function addBeamLayer(eff, layer, allow)
	local T = eff.Times
	local beat = layer.Beat or "Travel"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local mode, t1
	local at = layer.At
	if layer.Alive then
		mode = (layer.Motion == "Connect") and "Connect" or "Strike"
		t1 = min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6))
	elseif layer.Id == "DoubleArc" then
		mode, t1 = "Crescent", T.Impact + 0.2
	elseif layer.Id == "Rain" then -- the Storm special's lightning rain: bolts strike down around the target
		mode, t1 = "Strike", T.Impact + 0.2
	elseif at == "Path" then
		mode, t1 = "Path", T.Impact + 0.08
	else
		mode, t1 = "Arc", T.Impact + 0.15
	end
	local n = beamWant(layer)
	if allow then
		n = min(n, allow)
	end
	local id = layer.Texture and dep("TextureIds")[layer.Texture]
	for i = 1, n do
		if eff.Beams >= AttackFx.MAX_BEAMS then
			return
		end
		local kit = take("Beam")
		eff.Beams = eff.Beams + 1
		local b = kit.Beam
		local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
		b.Color = ColorSequence.new(c:Lerp(WHITE, 0.35), c)
		local a = finite(layer.Transparency) and clamp01(layer.Transparency) or 0 -- (Task 9: a see-through Mythic double arc)
		b.Transparency = NumberSequence.new({ kp(0, a + (1 - a) * 0.35), kp(0.15, a), kp(0.85, a), kp(1, a + (1 - a) * 0.35) })
		-- (Task 9 Studio: additive, the thin lightning strip vanished on the pale sky / floor; drawn mostly opaque in its
		-- colour it reads as a bolt)
		b.LightEmission = finite(layer.LightEmission) and clamp01(layer.LightEmission) or ((layer.Texture == "fx_lightning") and 0.25 or 1)
		b.LightInfluence = 0
		b.FaceCamera = true
		b.CurveSize0 = 0
		b.CurveSize1 = 0
		b.Segments = (mode == "Crescent" or layer.Spiral) and 16 or 2
		if id then
			b.Texture = "rbxassetid://" .. tostring(id)
			if layer.Texture == "fx_lightning" then
				b.TextureMode = Enum.TextureMode.Stretch
				b.TextureLength = 1
				b.TextureSpeed = 2.5
			else
				b.TextureMode = Enum.TextureMode.Wrap
				b.TextureLength = 4
				b.TextureSpeed = 3
			end
		else
			b.Texture = ""
		end
		local w = (finite(layer.Width) and layer.Width or ((mode == "Connect") and 0.12 or (layer.Spiral and 0.5 or 0.9))) * eff.Size
		local it = addItem(eff, {
			Kind = "Beam", Kit = kit, Layer = layer, Mode = mode, I = i, N = n, T0 = t0, T1 = t1, Fn = DRAW.Beam,
			Width0 = (mode == "Crescent") and w * 0.15 or w, Width1 = w, Flicker = layer.Texture == "fx_lightning",
			Spiral = layer.Spiral == true, Curve = (finite(layer.Curve) and layer.Curve or 2.2) * eff.Size,
			Jitter = layer.Id == "SigBolts",
		})
		if mode == "Crescent" then
			b.CurveSize0 = it.Curve
			b.CurveSize1 = -it.Curve
		end
	end
end

local function addTrailLayer(eff, layer)
	local T = eff.Times
	local beat = layer.Beat or "Travel"
	local t0 = beatStart(eff, beat)
	local t1 = beatEnd(eff, beat)
	if beat == "Travel" then
		t1 = T.Impact
	end
	local list = {}
	if layer.At == "Allies" then
		for a = 1, min(K.MAX_ALLIES, max(1, #eff.T)) do
			list[#list + 1] = { Mode = "Wind", Ally = a, Side = 0 }
		end
	else
		local n = min(2, max(1, finite(layer.Afterimages) and layer.Afterimages or 1))
		for i = 1, n do
			list[#list + 1] = { Mode = (layer.At == "Self") and "Leap" or "Core", Side = (n == 1) and 0 or ((i == 1) and -0.35 or 0.35) * eff.Size }
		end
	end
	local id = layer.Texture and dep("TextureIds")[layer.Texture]
	for _, spec in ipairs(list) do
		if eff.Trails >= AttackFx.MAX_TRAILS then
			return
		end
		local kit = take("Trail")
		eff.Trails = eff.Trails + 1
		local tr = kit.Trail
		local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
		tr.Color = ColorSequence.new(c:Lerp(WHITE, 0.4), c)
		tr.Transparency = NumberSequence.new({ kp(0, 0.15), kp(1, 1) })
		tr.WidthScale = NumberSequence.new({ kp(0, 1), kp(1, 0.1) })
		-- (a layer's Lifetime wins: Task 8 + Gemini, the ranged Streak at 0.2 s reached back to the mouth mid-flight and
		-- read as a tether, not a shot; a short comet tail instead)
		tr.Lifetime = (finite(layer.Lifetime) and layer.Lifetime > 0) and min(1, layer.Lifetime) or 0.2
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Texture = id and ("rbxassetid://" .. tostring(id)) or ""
		tr.TextureMode = Enum.TextureMode.Stretch
		local hw = 0.45 * eff.Size
		kit.A0.Position = V3(0, hw, 0)
		kit.A1.Position = V3(0, -hw, 0)
		addItem(eff, { Kind = "Trail", Kit = kit, Layer = layer, Mode = spec.Mode, Ally = spec.Ally, Side = spec.Side, T0 = t0, T1 = max(t0 + 0.05, t1), Fn = DRAW.Trail })
	end
end

local function addLightLayer(eff, layer)
	if eff.Lights >= AttackFx.MAX_LIGHTS then
		return
	end
	if eff.Low and (layer.Pulse or layer.Id == "Bloom") then
		return -- Low: no bloom
	end
	local T = eff.Times
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = min(eff.EndRel, (layer.Pulse and T.Impact + 0.2) or (beatEnd(eff, beat) + 0.25))
	if beat == "Travel" and layer.At == "Core" then
		t1 = T.Impact + 0.1
	end
	local kit = take("Light")
	eff.Lights = eff.Lights + 1
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	kit.Light.Color = c
	kit.Light.Range = (finite(layer.Range) and layer.Range or 8) * eff.Size
	kit.Light.Brightness = 0
	local b = (finite(layer.Brightness) and layer.Brightness or 2) * (eff.Crit and 1.3 or 1)
	addItem(eff, { Kind = "Light", Kit = kit, Layer = layer, At = layer.At, T0 = t0, T1 = max(t0 + 0.1, t1), B = b, Pulse = layer.Pulse == true, Shift = layer.ColorShift == true, Color = c, Pts = {}, Fn = DRAW.Light })
end

local function addDiscLayer(eff, layer)
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6))
	if layer.Alive then
		t1 = min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or 0.8))
	end
	local kit = take("Disc")
	local d = kit.Root
	local darken = layer.Motion == "Darken"
	local color = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	d.Color = color
	d.Material = darken and Enum.Material.SmoothPlastic or Enum.Material.Neon
	d.Transparency = 1
	local glow = dep("TextureIds")
	glow = glow and glow.fx_glow
	local soft = glow ~= nil and kit.Img ~= nil
	if kit.Img then
		kit.Img.Image = soft and ("rbxassetid://" .. tostring(glow)) or ""
		kit.Img.ImageColor3 = color
		kit.Img.ImageTransparency = 1
		kit.Gui.LightInfluence = darken and 1 or 0 -- a glow shines; the Shadow darkening is a lit dark blot
		kit.Gui.Brightness = darken and 1 or 1.6
	end
	local at = layer.At
	if at ~= "Allies" and at ~= "Self" and at ~= "Source" then
		at = "Ground"
	end
	addItem(eff, { Kind = "Disc", Kit = kit, Layer = layer, At = at, T0 = t0, T1 = max(t0 + 0.1, t1), D = (finite(layer.Size) and layer.Size or 4) * eff.Size, Trans = soft and 0.2 or 0.5, Soft = soft, Pts = {}, Fn = DRAW.Disc }) -- (Task 8: the soft sheet fades out to its rim by itself; a plain plate stays half see-through)
end

local function addRingLayer(eff, layer)
	local T = eff.Times
	local key = layer.Key or "vfx_ring"
	local t0 = beatStart(eff, layer.Beat or "Impact") + (finite(layer.Delay) and layer.Delay or 0)
	local flatRing = key == "vfx_ring"
	local anchor = (layer.At == "Self") and "Self" or ((layer.At == "Source") and "Source" or "Hit")
	if layer.Pop == true then -- a quick ball popping out at the anchor and fading (the ranged impact's fireball, note (b))
		addSolid(eff, key, {
			Layer = layer, Move = MOVE.Ring, Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
			Trans = finite(layer.Transparency) and layer.Transparency or 0.2, T0 = t0, TG = t0 + 0.14, TF = t0 + 0.06,
			T1 = min(eff.EndRel, t0 + 0.36), From = 0.35, To = finite(layer.Grow) and layer.Grow or 1,
		})
		return
	end
	if layer.Face == true then -- a quick ring standing up at the anchor, facing the attack (the ranged muzzle shock)
		addSolid(eff, key, {
			Layer = layer, Move = MOVE.Ring, Face = true, Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
			Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + 0.2, TF = t0 + 0.05,
			T1 = min(eff.EndRel, t0 + 0.32), From = 0.3, To = finite(layer.Grow) and layer.Grow or 1,
		})
		return
	end
	addSolid(eff, key, {
		Layer = layer, Move = MOVE.Ring, Flat = flatRing or layer.At == "Ground", Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
		Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + max(0.25, T.Linger - T.Impact + 0.2), TF = t0 + 0.08,
		T1 = min(eff.EndRel, t0 + max(0.4, T.Linger - T.Impact + 0.35)), From = 0.35, To = finite(layer.Grow) and layer.Grow or 2.5,
	})
end

local function addMeshLayer(eff, layer)
	local key = layer.Key
	if type(key) ~= "string" then
		return
	end
	local T = eff.Times
	local t0 = beatStart(eff, layer.Beat or "Impact") + (finite(layer.Delay) and layer.Delay or 0)
	local n = min(6, max(1, finite(layer.Count) and layer.Count or 1))
	local S = eff.Size * (finite(layer.Scale) and layer.Scale or 1)
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	local m = layer.Motion
	for i = 1, n do
		local a = (i - 1) / n * TAU + hash(i, 41) * 0.6
		local rad = (n == 1) and 0 or 1.1 * eff.Size
		local it = { Layer = layer, Color = c, S = S, Anchor = "Hit", OffR = cos(a) * rad, OffD = sin(a) * rad, T0 = t0 }
		if layer.Alive and m == "Melt" then
			it.Move, it.Material, it.Trans, it.T1 = MOVE.Melt, Enum.Material.Glass, 0.15, min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or 1))
			it.Rot = CFrame.Angles(pi / 2 - 0.2, hash(i, 42) * TAU, 0)
		elseif layer.Alive and m == "Bounce" then
			it.Move, it.Material, it.T1 = MOVE.Bounce, Enum.Material.SmoothPlastic, min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or 0.8))
			it.T0 = T.Impact
			it.VY, it.VH, it.Ang = (5 + 3 * hash(i, 43)) * eff.Size, (3 + 3 * hash(i, 44)) * eff.Size, a
			it.SX, it.SY = 6 + 6 * hash(i, 45), 4 + 6 * hash(i, 46)
		else -- Erupt / Wrap / anything else: up out of the ground around the target
			it.Move, it.Material = MOVE.Rise, Enum.Material.Neon
			it.TR = t0 + 0.04 * (i - 1)
			it.TS = (layer.Alive and t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) * 0.6) or (T.Linger + (eff.EndRel - T.Linger) * 0.3)
			it.T1 = min(eff.EndRel, layer.Alive and t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) or eff.EndRel)
			it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), (m == "Wrap") and -0.5 or -0.2) * CFrame.Angles(0, hash(i, 47) * TAU, 0)
		end
		addSolid(eff, key, it)
	end
end

local function addLayer(eff, layer, beams)
	local kind = layer.Kind
	if isEmitter(layer) then
		addEmitterLayer(eff, layer)
	elseif kind == "Decal" then
		addDiscLayer(eff, layer)
	elseif kind == "Beam" then
		local allow = beams and (beams[layer] or 0) or nil
		if not eff.Low and allow ~= 0 then
			addBeamLayer(eff, layer, allow)
		end
	elseif kind == "Trail" then
		if not eff.Low then
			addTrailLayer(eff, layer)
		end
	elseif kind == "Light" then
		addLightLayer(eff, layer)
	elseif kind == "Ring" then
		addRingLayer(eff, layer)
	elseif kind == "Mesh" then
		addMeshLayer(eff, layer)
	end
end

local function buildActor(eff)
	local sig = eff.Recipe.Sig
	local actor = sig and sig.Actor
	if type(actor) ~= "table" or type(actor.Key) ~= "string" then
		return
	end
	local T = eff.Times
	local t0 = beatStart(eff, actor.Beat or "Charge")
	local S = eff.Size * (finite(actor.Scale) and actor.Scale or 1)
	local c = typeof(actor.Color) == "Color3" and actor.Color or WHITE
	local n = min(9, max(1, finite(actor.Count) and actor.Count or 1))
	local anchors = {}
	if actor.At == "Allies" then
		local allies = min(K.MAX_ALLIES, max(1, #eff.T))
		n = min(n, floor(12 / allies))
		for a = 1, allies do
			anchors[#anchors + 1] = a
		end
	else
		anchors[1] = actor.At == "Target" and "Hit" or (actor.At or "Hit")
	end
	for _, anchor in ipairs(anchors) do
		for i = 1, n do
			local it = { Move = MOVE.Actor, Motion = actor.Motion, Anchor = anchor, I = i, N = n, Color = c, S = S, Material = Enum.Material.Neon, T0 = t0, T1 = eff.EndRel, TF = T.Linger + (eff.EndRel - T.Linger) * 0.4 }
			if actor.Motion == "SpiralUp" then
				it.T1 = T.Impact + 0.15
				it.TF = T.Impact
			elseif actor.Motion == "ChargeThrough" then
				it.T0, it.T1, it.TF = T.Travel, T.Linger + 0.2, T.Impact + 0.05
			elseif actor.Motion == "Sweep" then
				it.T1, it.TF = T.Impact + 0.2, T.Travel
			elseif actor.Motion == "RingRise" then
				local a = (i - 1) / n * TAU
				it.Move = MOVE.Rise
				it.OffR, it.OffD = cos(a) * 2.5 * eff.Size, sin(a) * 2.5 * eff.Size
				it.TR = t0 + 0.03 * (i - 1)
				it.TS = T.Linger + (eff.EndRel - T.Linger) * 0.3
				it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), 0.25)
			elseif actor.Motion == "RiseRoar" then
				it.OffR = (i - (n + 1) / 2) * 1.6 * eff.Size
			end
			addSolid(eff, actor.Key, it)
		end
	end
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
local function poseSample(entry, now)
	local best = nil
	for _, s in ipairs(entry.Segs) do
		if now >= s.T0 and (now < s.T0 + s.Dur or s.Hold) then
			best = s
		end
	end
	if not best then
		return nil
	end
	local el = now - best.T0
	if best.StopAt then
		el = el - min(max(0, now - best.StopAt), best.StopDur)
	end
	return best.Name, clamp01(el / best.Dur), best.Ranged == true, best.Amp, best.Reach
end

local function poseActive(entry, at)
	for _, s in ipairs(entry.Segs) do
		if s.Hold or at < s.T0 + s.Dur then
			return true
		end
	end
	return false
end

local function setPoses(unit, segs, now)
	if unit == nil or #segs == 0 then
		return
	end
	local prio = 0
	for _, s in ipairs(segs) do
		prio = max(prio, K.PRIO[s.Name] or 1)
	end
	local old = St.poses[unit]
	if old and old.Prio > prio and poseActive(old, segs[1].T0) then
		return -- a higher pose still plays then (a KO'd pet never strikes; an attack is not cut by a flinch)
	end
	local entry = { Segs = segs, Prio = prio }
	if old and poseActive(old, now) then
		entry.Prev = old -- crossfade from the old timeline, still animating
		entry.SwitchAt = max(now, segs[1].T0)
	end
	St.poses[unit] = entry
end

-- a model's oriented bounding box -> its centre's offset from `origin` along the flat unit `dir` and its half-length
-- along it (nil without a model)
local function spanAlong(model, origin, dir)
	if not model then
		return nil
	end
	local ok, cf, size = pcall(model.GetBoundingBox, model)
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return nil
	end
	local half = 0.5 * (abs(dir:Dot(cf.RightVector)) * size.X + abs(dir:Dot(cf.UpVector)) * size.Y + abs(dir:Dot(cf.LookVector)) * size.Z)
	return (cf.Position - origin):Dot(dir), half
end

-- the melee leap's forward reach (Task 9 player decision: the jump lands on the target): from the caster's front edge
-- to the target's near edge along the ground, minus K.LEAP_MARGIN, clamped 0 .. K.LEAP_MAX world studs; returned in
-- the caster's pose units (PetPoses studs at scale 1: the drawing multiplies the body offset by the model's PB_Scale).
-- Without models the pivots stand in with no size. nil = no target (the fixed hop)
function AttackFx.LeapReach(src, tgt)
	if not (src and tgt and typeof(src.Last) == "Vector3" and typeof(tgt.Last) == "Vector3") then
		return nil
	end
	local d = flat(tgt.Last - src.Last)
	local dist = d.Magnitude
	if dist < 0.05 then
		return 0
	end
	local u = d / dist
	local c0, ch = spanAlong(src.Model, src.Last, u)
	local t0, th = spanAlong(tgt.Model, src.Last, u)
	local front = (c0 or 0) + (ch or 0)
	local near = (t0 or dist) - (th or 0)
	local world = max(0, min(K.LEAP_MAX, near - front - K.LEAP_MARGIN))
	local s = src.Model and tonumber(src.Model:GetAttribute("PB_Scale")) or 1
	if not finite(s) or s <= 0 then
		s = 1
	end
	return world / s
end

local function schedulePoses(eff, now)
	local r = eff.Recipe
	local A = r.Attack
	local T = eff.Times
	local st = eff.Start
	local ranged = A == "Ranged"
	local segs = {}
	local offensive = eff.Path ~= "Self" and eff.Path ~= "Allies"
	if A == "Melee" or A == "Ranged" or (A == "Element" and eff.Area ~= "Circle") or (A == "Special" and r.Kind == "Pounce") then
		if T.Release > 0.04 then
			segs[#segs + 1] = { Name = "Windup", T0 = st, Dur = T.Release, Ranged = ranged }
		end
		if ranged then
			-- a shot, never the melee lunge (player note 1): rear back (the ranged Windup), then Shoot = the head snaps
			-- forward to loose the shot while the body kicks back; the pet stays at its spot
			segs[#segs + 1] = { Name = "Shoot", T0 = st + T.Release, Dur = K.SHOOT, Ranged = true }
		else
			local dur = max(0.45, min(0.9, (T.Impact - T.Release) / 0.26))
			-- the leap (player note (a)): it lands on the target at the impact (PetPoses Strike lands at p 0.26); a little
			-- longer and higher per rarity band (Amp). Melee only: its Reach is the gap to the target, so the leap lands ON
			-- it (Task 9 player decision); an element Cone / Line and the Pounce keep the short fixed hop (a blast from the spot)
			segs[#segs + 1] = { Name = "Strike", T0 = st + T.Release, Dur = dur, StopAt = (not eff.Miss) and (st + T.Impact) or nil, StopDur = AttackFx.HIT_STOP,
				Amp = 1 + K.LEAP_STEP * ((tonumber(r.Band) or 1) - 1), Reach = (A == "Melee") and AttackFx.LeapReach(eff.Src, eff.Targets[1]) or nil }
		end
	elseif A == "Special" or A == "Element" then
		-- Cast's release (p 0.66 .. 0.74) lands as the release beat ends
		segs[1] = { Name = "Cast", T0 = st, Dur = max(0.6, min(1.6, T.Travel / 0.7)) }
	elseif A == "Hurt" then
		segs[1] = { Name = "Hurt", T0 = st, Dur = K.HURT }
	elseif A == "Ko" then
		segs[1] = { Name = "Ko", T0 = st, Dur = K.KO, Hold = true }
	elseif A == "Victory" then
		segs[1] = { Name = "Victory", T0 = st, Dur = K.VICTORY }
	end
	setPoses(eff.Unit, segs, now)
	if offensive and not eff.Miss and (A == "Melee" or A == "Ranged" or A == "Element" or A == "Special") then
		for _, side in ipairs(eff.Targets) do
			if side.Unit ~= nil and side.Unit ~= eff.Unit then
				setPoses(side.Unit, { { Name = "Hurt", T0 = st + T.Impact, Dur = K.HURT } }, now)
			end
		end
	end
end

----------------------------------------------------------------------
-- Effects: lifecycle
----------------------------------------------------------------------
local function release(eff)
	for _, it in ipairs(eff.Items) do
		if it.Kit then
			give(it.Kit)
			it.Kit = nil
		end
	end
	eff.Items = {}
	eff.Emitters, eff.Beams, eff.Trails, eff.Lights, eff.Cores = 0, 0, 0, 0, 0
end

local function finish(eff)
	for i = #St.live, 1, -1 do
		if St.live[i] == eff then
			table.remove(St.live, i)
		end
	end
	release(eff)
end

-- Low quality: drop the Beams / Trails / bloom of a live effect at once
local function strip(eff)
	eff.Low = true
	local keep = {}
	for _, it in ipairs(eff.Items) do
		local layer = it.Layer
		local drop = it.Kind == "Beam" or it.Kind == "Trail" or (it.Kind == "Light" and layer and (layer.Pulse or layer.Id == "Bloom"))
		if drop then
			give(it.Kit)
			it.Kit = nil
			if it.Kind == "Beam" then
				eff.Beams = eff.Beams - 1
			elseif it.Kind == "Trail" then
				eff.Trails = eff.Trails - 1
			else
				eff.Lights = eff.Lights - 1
			end
		else
			keep[#keep + 1] = it
		end
	end
	eff.Items = keep
end

local function effectiveQuality()
	if St.forced then
		return St.forced
	end
	local gq = dep("GraphicsQuality")
	if gq and type(gq.Effective) == "function" then
		local ok, m = pcall(gq.Effective)
		if ok and m == "Low" then
			return "Low"
		end
	end
	return "High"
end

local function applyQuality()
	local q = effectiveQuality()
	if q == St.mode then
		return q
	end
	St.mode = q
	if q == "Low" then
		for _, eff in ipairs(St.live) do
			strip(eff)
		end
	end
	return q
end

local function callHook(name, ...)
	local fn = AttackFx.Hooks[name]
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			warnOnce("hook" .. name, "hook " .. name .. " failed: " .. tostring(err))
		end
	end
end

local function stepEffect(eff, now)
	local t = now - eff.Start
	eff.Dt = max(0, min(0.1, now - (eff.LastNow or now)))
	eff.LastNow = now
	if t < 0 then
		return
	end
	refresh(eff)
	eff.CorePos = corePosOf(eff, t)
	local r = eff.Recipe
	if not eff.Dimmed then
		eff.Dimmed = true
		if eff.Mine and r.Sig and finite(r.Sig.DimWorld) then
			callHook("DimWorld", r.Sig.DimWorld)
		end
	end
	if not eff.Punched and t >= eff.Times.Impact then
		eff.Punched = true
		if eff.Mine and not eff.Miss then
			if r.CameraPunch then
				callHook("Punch", min(AttackFx.PUNCH_MAX, 0.14 + 0.06 * (r.Band - 3) + (eff.Crit and 0.05 or 0)), 0.2)
			end
			if r.ScreenGlow then
				callHook("ScreenGlow", (r.Core and r.Core.RimColor) or (r.Palette and r.Palette.Edge) or WHITE, 0.35)
			end
		end
	end
	for _, it in ipairs(eff.Items) do
		if it.Kit then
			it.Fn(eff, it, t)
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
local function sideOf(s)
	if type(s) ~= "table" then
		return nil
	end
	local side = { Unit = s.Unit, Model = (typeof(s.Model) == "Instance") and s.Model or nil, Pos = (typeof(s.Pos) == "Vector3") and s.Pos or nil }
	if not pointOf(side) then
		return nil
	end
	return side
end

local function resolve(ctx, distance, step)
	local Cat = dep("AttackFxCatalog")
	if not (Cat and type(Cat.Resolve) == "function") then
		return nil
	end
	local rarity = ctx.Rarity
	if step then
		local band = Cat.BandOf(rarity)
		rarity = K.BAND_RARITY[max(1, band - 1)]
	end
	local ok, r = pcall(Cat.Resolve, {
		Element = ctx.Element, Attack = ctx.Attack, Kind = ctx.Kind, Shape = ctx.Shape, Rarity = rarity, Stage = ctx.Stage,
		PetId = ctx.PetId, Mine = ctx.Mine == true, Distance = distance,
	})
	if ok and type(r) == "table" and type(r.Beats) == "table" and type(r.Core) == "table" then
		return r
	end
	return nil
end

-- every sheet / strip the recipe uses has an id (else the caller falls back)
local function texturesOk(r)
	local ids = dep("TextureIds")
	if type(ids) ~= "table" then
		return false
	end
	local function ok(key)
		if key == nil then
			return true
		end
		local id = ids[key]
		return type(id) == "number" and id > 0
	end
	for _, layer in ipairs(r.Layers or {}) do
		if not ok(layer.Texture) then
			return false
		end
	end
	return ok(type(r.Alive) == "table" and r.Alive.Texture or nil)
end

-- -> start, charge, release, travel, late (seconds the impact lands AFTER dueAt: only a recipe's MinTravel, a basic
-- ranged shot's flight, is never cut, so the shot is always seen crossing the gap: player note 1)
local function fitTimes(b, now, dueAt)
	local C, R, Tr = b.Charge or 0, b.Release or 0, b.Travel or 0
	local keep = finite(b.MinTravel) and max(0, min(Tr, b.MinTravel)) or 0
	local start, late = now, 0
	if finite(dueAt) then
		local need = C + R + Tr
		local avail = dueAt - now
		if avail >= need then
			start = dueAt - need -- (may be a little ahead: the effect waits, then lands exactly on the event)
		else
			-- late: shorten the charge first, then the travel (down to its MinTravel), then the release; impact never
			-- after the event, except by what the MinTravel keeps
			local cut = need - max(0, avail)
			local c = min(C, cut)
			C, cut = C - c, cut - c
			c = min(Tr - keep, cut)
			Tr, cut = Tr - c, cut - c
			c = min(R, cut)
			R, cut = R - c, cut - c
			late = cut
		end
	end
	return start, C, R, Tr, late
end

function AttackFx.Play(ctx)
	if type(ctx) ~= "table" then
		return false
	end
	local eff = nil -- (outside the pcall: a build that fails half-way gives back every kit it took)
	local ok, result = pcall(function()
		local now = finite(ctx.Now) and ctx.Now or os.clock()
		local src = sideOf(ctx.From)
		if not src then
			return false
		end
		local targets = {}
		if type(ctx.To) == "table" then
			if ctx.To[1] ~= nil then
				for _, s in ipairs(ctx.To) do
					local side = sideOf(s)
					if side then
						targets[#targets + 1] = side
					end
				end
			else
				targets[1] = sideOf(ctx.To)
			end
		end
		local distance = nil
		if targets[1] then
			distance = (targets[1].Last - src.Last).Magnitude
		end
		-- budget: MAX_LIVE full effects, then MAX_STEPPED a band lower, then no
		local full, stepped = 0, 0
		for _, e in ipairs(St.live) do
			if e.Stepped then
				stepped = stepped + 1
			else
				full = full + 1
			end
		end
		local step = full >= AttackFx.MAX_LIVE
		if step and stepped >= AttackFx.MAX_STEPPED then
			return false
		end
		local r = resolve(ctx, distance, step)
		if not r or not texturesOk(r) then
			return false
		end
		local quality = applyQuality()
		local start, C, R, Tr, late = fitTimes(r.Beats, now, ctx.DueAt)
		ctx.ImpactLate = late
		local Imp, L = r.Beats.Impact or 0.15, r.Beats.Linger or 0.5
		local aliveSecs = (type(r.Alive) == "table" and finite(r.Alive.Seconds)) and r.Alive.Seconds or 0
		local T = { Charge = 0, Release = C, Travel = C + R, Impact = C + R + Tr }
		T.Linger = T.Impact + Imp
		local endRel = T.Linger + max(L, aliveSecs)
		local area = (r.Attack == "Element") and (r.Shape or "Cone") or nil
		local reach
		if area == "Line" then
			reach = finite(ctx.Length) and ctx.Length or 24
		elseif area == "Circle" then
			reach = finite(ctx.Radius) and ctx.Radius or 8
		else
			reach = finite(ctx.Radius) and ctx.Radius or 9
		end
		local dir = V3(0, 0, -1)
		if finite(ctx.Angle) then
			dir = V3(cos(ctx.Angle), 0, sin(ctx.Angle))
		end
		if targets[1] then
			local d = flat(targets[1].Last - src.Last)
			if d.Magnitude > 0.2 then
				dir = d.Unit
			end
		end
		local drop = K.DROP
		if finite(ctx.Ground) then
			local d = src.Last.Y - ctx.Ground
			if d >= 0.2 and d <= 8 then
				drop = d
			end
		end
		eff = {
			Recipe = r, Unit = src.Unit, Src = src, Targets = targets, T = {}, S = src.Last, Dir = dir, Right = dir:Cross(UP),
			Path = r.Core.Path, Area = area, Reach = reach, Drop = drop, Size = r.Size or 1,
			Start = start, Times = T, EndRel = endRel, End = start + endRel,
			Mine = ctx.Mine == true, Crit = ctx.Crit == true, Strong = ctx.Strong == true, Miss = ctx.Miss == true,
			Stepped = step, Low = quality == "Low", Items = {}, Emitters = 0, Beams = 0, Trails = 0, Lights = 0, Cores = 0,
		}
		for i, side in ipairs(targets) do
			eff.T[i] = side.Last
		end
		refresh(eff)
		eff.CorePos = corePosOf(eff, 0)
		-- what this effect draws: the core, the layers it can afford, the alive detail, the signature actor
		buildCore(eff)
		local layers = {}
		for _, layer in ipairs(r.Layers or {}) do
			if not (eff.Miss and (layer.Beat == "Impact" or layer.Beat == "Linger")) then
				layers[#layers + 1] = layer
			end
		end
		if type(r.Alive) == "table" and r.Alive.Kind and not eff.Miss then
			local a = {}
			for k, v in pairs(r.Alive) do
				a[k] = v
			end
			a.Id, a.Alive, a.Beat = "Alive", true, "Linger"
			a.At = (eff.Path == "Self" or eff.Path == "Allies") and "Self" or "Target"
			layers[#layers + 1] = a
		end
		local cap = AttackFx.MAX_EMITTERS[quality] or 6
		local keep = nil
		if quality == "Low" and type(r.LowKeep) == "table" then
			keep = {}
			for i, id in ipairs(r.LowKeep) do
				keep[id] = keep[id] or i
			end
		end
		local ranked = {}
		for i, layer in ipairs(layers) do
			if isEmitter(layer) and not chargeDropped(eff, layer) then
				ranked[#ranked + 1] = { L = layer, R = emitterRank(layer, keep), I = i }
			end
		end
		table.sort(ranked, function(a, b)
			if a.R ~= b.R then
				return a.R < b.R
			end
			return a.I < b.I
		end)
		local allowed = {}
		for i = 1, min(cap, #ranked) do
			allowed[ranked[i].L] = true
		end
		local beams = beamBudget(layers, AttackFx.MAX_BEAMS) -- (the alive detail first, the ladder's arcs last)
		for _, layer in ipairs(layers) do
			if not isEmitter(layer) or allowed[layer] then
				addLayer(eff, layer, beams)
			end
		end
		buildActor(eff)
		St.live[#St.live + 1] = eff
		schedulePoses(eff, now)
		return true
	end)
	if not ok then
		St.errors = St.errors + 1
		warnOnce("play", "Play failed: " .. tostring(result))
		if eff then
			pcall(finish, eff) -- out of St.live (if it got there) and every kit back to its pool, hidden
		end
		return false
	end
	return result == true
end

function AttackFx.Update(now)
	now = finite(now) and now or os.clock()
	St.now = now
	applyQuality()
	for i = #St.live, 1, -1 do
		local eff = St.live[i]
		if eff then
			local ok, err = pcall(stepEffect, eff, now)
			if not ok then
				St.errors = St.errors + 1
				warnOnce("step", "effect failed: " .. tostring(err))
				pcall(finish, eff)
			elseif now >= eff.End then
				finish(eff)
			end
		end
	end
	for unit, entry in pairs(St.poses) do
		local pending = entry.Prev and entry.SwitchAt and now < entry.SwitchAt + AttackFx.CROSSFADE
		if not pending then
			entry.Prev = nil
		end
		if not poseActive(entry, now) and not pending then
			St.poses[unit] = nil
		end
	end
end

-- (the returned table and its Prev are reused per pose entry: read them at once, do not keep them across frames)
function AttackFx.Pose(unit)
	local entry = St.poses[unit]
	if not entry then
		return nil
	end
	local now = St.now or os.clock()
	local name, p, ranged, amp, reach = poseSample(entry, now)
	local prev = entry.Prev
	local out = entry.Out
	if not out then
		out = {}
		entry.Out = out
	end
	out.Blend, out.Prev = 1, nil
	if not name then
		if prev and entry.SwitchAt and now < entry.SwitchAt then -- the new pose has not started: the old one plays on
			local n2, p2, r2, a2, x2 = poseSample(prev, now)
			if n2 then
				out.Name, out.P, out.Ranged, out.Amp, out.Reach = n2, p2, r2, a2, x2
				return out
			end
		end
		return nil
	end
	out.Name, out.P, out.Ranged, out.Amp, out.Reach = name, p, ranged, amp, reach
	if prev and entry.SwitchAt then
		local w = (now - entry.SwitchAt) / AttackFx.CROSSFADE
		if w < 1 then
			local n2, p2, r2, a2, x2 = poseSample(prev, now)
			if n2 then
				local po = entry.PrevOut
				if not po then
					po = {}
					entry.PrevOut = po
				end
				po.Name, po.P, po.Ranged, po.Amp, po.Reach = n2, p2, r2, a2, x2
				out.Blend = max(0, w)
				out.Prev = po
			end
		end
	end
	return out
end

function AttackFx.Cancel(unit)
	St.poses[unit] = nil
	for i = #St.live, 1, -1 do
		local eff = St.live[i]
		if eff and eff.Unit == unit then
			pcall(finish, eff)
		end
	end
end

function AttackFx.ClearAll()
	for i = #St.live, 1, -1 do
		pcall(finish, St.live[i])
	end
	St.live = {}
	St.poses = {}
end

function AttackFx.SetQuality(q)
	if q ~= "Low" and q ~= "High" then
		q = nil
	end
	St.forced = q
	applyQuality()
end

function AttackFx.Stats()
	local s = { Live = 0, Stepped = 0, Emitters = 0, Beams = 0, Trails = 0, Lights = 0, Cores = 0, Pooled = 0, PoolInstances = 0, Errors = St.errors }
	for _, eff in ipairs(St.live) do
		if eff.Stepped then
			s.Stepped = s.Stepped + 1
		else
			s.Live = s.Live + 1
		end
		s.Emitters = s.Emitters + eff.Emitters
		s.Beams = s.Beams + eff.Beams
		s.Trails = s.Trails + eff.Trails
		s.Lights = s.Lights + eff.Lights
		s.Cores = s.Cores + eff.Cores
	end
	local function count(list)
		for _, kit in ipairs(list) do
			s.Pooled = s.Pooled + 1
			s.PoolInstances = s.PoolInstances + kit.N
		end
	end
	for _, list in pairs(St.pool) do
		count(list)
	end
	for _, list in pairs(St.corePool) do
		count(list)
	end
	return s
end

function AttackFx.Folder()
	return ensureFolder()
end

-- TESTS ONLY: dependency overrides ({ MeshLibrary =, TextureIds =, GraphicsQuality = }; false = the real one)
function AttackFx._Deps(t)
	for k, v in pairs(type(t) == "table" and t or {}) do
		deps[k] = v or nil
	end
end

-- TESTS ONLY: the live effects (read only)
function AttackFx._Live()
	return St.live
end

return AttackFx
