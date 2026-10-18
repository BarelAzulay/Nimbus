-- PetController (client): every player's equipped pets follow their owner from BEHIND, with a floating pet card.
--
--   PetController.Init()
--   PetController.Stop()            -- tears everything down (tests / hot reload)
--   PetController.GetPetCount()     -- number of pet models currently alive (debug helper)
--   PetController.GetMoveStats()    -- { Rigid = n, Pivot = n }: pets posed in the last frame by one root write /
--                                      by the PivotTo fallback (debug helper for the smoke tests)
--   PetController.PlayEvolution(key, stage[, opts]) -> release()
--                                      Phase 4 (contract 3.6): parks the local player's follower of `key` (model and
--                                      card hidden) while CareController plays EvolutionFx on its own clones, then
--                                      rebuilds it at `stage` (1 | 2) and lets it fly back into its slot. opts: a number
--                                      (seconds to stay parked) or { Seconds = n, From = Vector3 (where the evolved
--                                      clone stood: the follower starts from there) }; default EvolutionFx.Duration
--                                      (stage) + 0.3 s. release(fromPosition?) ends the park early. The stage counts
--                                      until State's PetGrowth catches up (never lower than the stored stage).
--   PetController.GetCards()        -- debug: { { UserId, Key, Mode, Gui, Shown } } of every live pet card
--   PetController.GetFollowerInfo(player) -- debug: { { Key, Model, Stage = built model stage, Want = card stage,
--                                      Level, Card = BillboardGui | nil, Parked, Diving, Back = back multiplier } }
--
-- What it does
--   * Reads the player attribute `EquippedPets` (csv of pet KEYS, Config.Attr.EquippedPets) of EVERY player
--     and keeps one follower per player. A key is a plain pet id (Normal copy), "petId@Golden" / "petId@Rainbow"
--     (tier copies: PetBuilder draws the finish from Look.Finish) or "hyb:<uid>" (a fused hybrid). Every follower is
--     built from PetKeys.DefOf(key); hybrids need their record, which the server publishes for the equipped ones in
--     the attribute `EquippedHybrids` ("uid=Body/Style/Tier/Rarity[/Seed];...", PetService). Keys that cannot be
--     described (unknown pets, a hybrid without its record yet) are ignored, at most Config.Pets.MaxEquipped are
--     used. All pets are drawn on this client only (workspace.ClientPets, one Folder per owner named after the
--     UserId); the server pays nothing.
--   * Each pet is a PetBuilder model. Right after it is built, every static part (body, head, eyes, eyelids...)
--     is welded once to the anchored PrimaryPart (like NpcController / ShowcaseController do), so a pose is ONE
--     CFrame write on the root: the engine carries the welded parts along. PetBuilder.Animate then re-poses only
--     the wing / tail / halo parts from the root (they stay anchored). A model that cannot be welded falls back
--     to PivotTo; a pet whose Animate keeps failing gets its animated parts welded too, so nothing trails behind.
--   * Phase 4 follow-behind (contract 3.9): pets trail in slots { side, up, back, ahead } BEHIND the owner (1 pet
--     4.5 studs back; 2 pets side by side 4.2 back; 3 pets two in front, one 6.5 back; `ahead` is 0 everywhere, so a
--     pet never runs ahead of a walking owner), at about head height, bob and sway with their own phase, ease
--     towards their slot with an exponential filter (LEAD_H cancels most of the lag), face the direction the owner
--     travels, bank into turns, pitch forward when they speed up and flap harder when the owner runs or is in the
--     air. Evolved followers trail a little further back (back x min(1.4, height / 3), the measured model height).
--   * Phase 4 evolved models (3.6): the stored evolution stage (State.PetGrowth(key).Evo for your own pets, the
--     player attribute EquippedInfo "level:stage,..." for others) is passed to PetBuilder.Build through opts.Evolved
--     only. Your own evolved followers are Low detail (<= petEvoLow 380 / petEvo2Low 520 parts); other players'
--     evolved followers are drawn evolved only within 40 studs and at most 6 at a time (nearest first), else as the
--     normal Low model (their card still shows the stars). Heights are measured once per key|stage (GetExtentsSize).
--   * Phase 4 pet cards (3.9, client/UI/PetCard.lua): your own followers show "Lv n" + the XP bar (State.PetLevel +
--     TycoonCatalog.XpToNext, refreshed on State.Changed) and the gold EVOLVE! pill when the pet is ready (a tap
--     opens the Pets panel on that pet); other players' followers show the level (and stars) from EquippedInfo
--     only, at most 12 cards at once (nearest first, MaxDistance 60). Cards hide while the owner is InBattle, while
--     a follower is parked or diving, and with the model. Card writes happen on events and in a 2 Hz tick only.
--   * Phase 4 home portal (3.10): when the owner's portal was just used (the player attribute HomePortal cleared /
--     PortalArrived written, and a teleport > 35 studs within 0.5 s of it) the followers fly into the portal centre
--     and shrink (0.4 s), then pop out of the arrival ring behind the owner (the fresh = 2 emerge path).
--   * Phase 3: while the owner's player attribute `InBattle` is set (BattleService), the followers are parked: the
--     battle team fights on the floor, drawn by BattleController. They snap back into formation afterwards.
--   * Owners that are downed keep their pets close; owners that teleport (> 35 studs in one step) or
--     respawn get their pets snapped back into formation. A pet that ends up > 60 studs from its slot snaps.
--   * Pets of OTHER players are only shown within 150 studs of the viewer (with a little hysteresis) and are
--     updated less often the further away they are (LOD). The local player's pets are always shown.
--   * Models are built lazily under a time budget (one per frame at least, more only while the frame's build
--     time stays under BUILD_BUDGET: a first-time High sculpt is far more expensive than a cached clone),
--     destroyed when the pet is unequipped, when the owner's character is removed or when the player leaves,
--     and parked (Parent = nil) while culled.
--
-- Performance: the per-frame code touches only numbers stored on long-lived tables, builds no tables or
-- closures, and creates exactly one CFrame per pet per update (the rotation matrix is written out by hand).
-- Per pet and frame Lua writes one root CFrame plus the animated parts (no part is written twice). Cards are
-- never written per frame. Everything is wrapped in pcall so one broken pet can never stop the others.
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetCatalog = require(Shared:WaitForChild("PetCatalog"))
local PetBuilder = require(Shared:WaitForChild("PetBuilder"))
-- Phase 2 pet keys (tiers + hybrids); without the module plain pet ids keep working through PetCatalog
local PetKeys = nil
do
	local module = Shared:FindFirstChild("PetKeys") or Shared:WaitForChild("PetKeys", 5)
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			PetKeys = result
		end
	end
end

-- optional modules: a build without one still draws the followers
local function optionalModule(parent, name, waitSeconds)
	if not parent then
		return nil
	end
	local inst = parent:FindFirstChild(name)
	if not inst and waitSeconds then
		inst = parent:WaitForChild(name, waitSeconds)
	end
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end
local Client = script.Parent and script.Parent.Parent
local TycoonCatalog = optionalModule(Shared, "TycoonCatalog")
local State = optionalModule(Client, "State")
local PetCard = optionalModule(Client and Client:FindFirstChild("UI"), "PetCard")

local PetController = {}

local LocalPlayer = Players.LocalPlayer
local ATTR = Config.Attr
local PHYS = Config.Physics

local sin, cos, exp, sqrt, abs = math.sin, math.cos, math.exp, math.sqrt, math.abs
-- Luau and Lua 5.1 have math.atan2; Lua 5.3+ folds it into math.atan(y, x). Support both.
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end
local PI = math.pi
local TAU = math.pi * 2

----------------------------------------------------------------------
-- Tuning (feel only)
----------------------------------------------------------------------
local FOLDER_NAME = "ClientPets"
local HYBRID_ATTR = "EquippedHybrids" -- written by PetService (not in Config.Attr): looks of the equipped hybrids
local MAX_EQUIPPED = 3
if type(Config.Pets) == "table" and type(Config.Pets.MaxEquipped) == "number" then
	MAX_EQUIPPED = math.max(1, math.floor(Config.Pets.MaxEquipped))
end

-- Culling / level of detail (studs from the local player's character, or from the camera while it has
-- none; the local player's own pets ignore all of this)
local CULL_IN = 138 -- other players' pets appear inside this distance ...
local CULL_OUT = 150 -- ... and are parked beyond this one
local LOD_MID = 55 -- beyond this distance a follower is updated every 2nd frame
local LOD_FAR = 105 -- ... and beyond this one every 4th frame

-- Teleports and catch-up
local TELEPORT_STEP2 = 35 * 35 -- owner moved further than this in one update -> snap the formation
local SNAP_DIST2 = 60 * 60 -- a pet further than this from its slot snaps to it

-- Time steps
local MAX_DT = 0.1
local MIN_DT = 1 / 240
local ROOT_POLL = 0.25 -- seconds between searches for a missing HumanoidRootPart
local SLOW_TICK = 0.5 -- seconds between housekeeping checks per follower
-- Builds per frame: a cached clone costs a few ms, a first-time High sculpt (~300 parts) tens of ms, so the
-- budget is time, not a count: the first build of a frame always runs, the next ones only while the frame has
-- spent less than BUILD_BUDGET seconds building, and never more than BUILD_MAX.
local BUILD_BUDGET = 0.004
local BUILD_MAX = 3
local BUILD_RETRY = 5 -- seconds before a failed build is tried again
local WELD_NAME = "PetFollowWeld"

-- Owner motion estimate
local VEL_RATE = 12 -- smoothing of the owner velocity (1/s)
local MAX_SPEED = 140 -- clamp for the instantaneous velocity (dash 85, cannons ~170)
local HEAD_MIN_SPEED = 3 -- below this the owner "faces" its LookVector instead of its velocity
local HEAD_RATE_MOVE = 4 -- how fast the formation swings round while the owner travels (1/s)
local HEAD_RATE_IDLE = 1.6 -- ... and while it stands still and turns on the spot
local RUN_K_FROM = 14 -- horizontal speed where the "running" factor starts ...
local RUN_K_SPAN = math.max(6, (PHYS and PHYS.RunSpeed or 27) - 14) -- ... and where it reaches 1
local RUN_RATE = 5
local AIR_RATE = 8
local DOWN_RATE = 4

-- Pet motion
local LEAD_H = 0.12 -- seconds of owner velocity added to the target (cancels most of the filter lag)
local LEAD_V = 0.05
local RUN_AHEAD = 4.0 -- Phase 3: studs the side pets moved forward at full run speed (unused: every `ahead` is 0)
local RUN_RISE = 0.6 -- studs the pets rise at full run speed
local FACE_RATE = 7 -- pet yaw easing (1/s)
local TILT_RATE = 9 -- pitch / roll easing (1/s)
local BANK_GAIN = 0.1 -- radians of roll per radian/second of yaw rate
local BANK_MAX = 0.55
local PITCH_GAIN = 0.0125 -- radians of nose-down pitch per stud/second of forward speed

-- Slots: { side (+ = owner's right), up (above the HumanoidRootPart), back (behind the owner), ahead (0..1) }.
-- The HumanoidRootPart is ~3 studs above the floor, so +2 puts a pet's body at head height.
-- Phase 4 (contract 3.9, the player's "follow the player from behind"): trailing slots, `ahead` = 0 everywhere
-- (prototyped through this file's filter math: 4.5 / 4.6 / 6.5 studs behind at rest, worst lag 7.7 studs at
-- 24 studs/s, settles at 6.5, never ahead of the owner while moving).
local FORMATION = {
	[1] = { { 0.0, 2.3, 4.5, 0 } },
	[2] = { { -1.8, 2.0, 4.2, 0 }, { 1.8, 2.6, 4.2, 0 } },
	[3] = { { -2.2, 1.9, 4.0, 0 }, { 2.2, 2.5, 4.0, 0 }, { 0.0, 2.9, 6.5, 0 } },
}

-- Phase 4 tuning (cards, evolved models, the portal dive)
local P4K = {
	CARD_HEIGHT = 0.7, -- studs above the top of the pet
	OTHER_CARDS = 12, -- other players' cards at once (nearest first) ...
	OTHER_CARD_DIST = 60, -- ... within this distance (also the cards' MaxDistance)
	OTHER_EVO_MAX = 6, -- other players' evolved models at once (nearest first) ...
	OTHER_EVO_IN = 40, -- ... within this distance
	OTHER_EVO_OUT = 46, -- an evolved model already shown keeps its look up to here (no flicker at the edge)
	EVO_BACK_MAX = 1.4, -- evolved followers: back x min(1.4, height / 3)
	EVO_GRACE = 0.6, -- s: a stage that rose without PlayEvolution waits this long (the animation may park it first)
	GLOBAL_TICK = 0.5, -- s between card / evolved-model selections
	DIVE_TIME = 0.4, -- s the followers take to fly into a used home portal
	DIVE_WINDOW = 0.5, -- s: a teleport this close to the portal closing is a portal trip
	DIVE_NEAR = 8, -- studs: an owner this close to an open portal who teleports used it
	PARK_DEFAULT = 4.6, -- s a follower stays parked by PlayEvolution when EvolutionFx cannot say
}

-- Wing speed. PetBuilder.Animate beats the wings at FLAP_HZ * Flap * (1 + 1.25 * Excited) per second, so the
-- two channels multiply. Running while jumping is the normal state in a parkour game, and an uncapped product
-- reached 11-15 beats/s (4-5 frames per beat at 60 fps, strobing at 30 fps), so the speed-up is capped here.
local PB_FLAP_HZ = 2.0 -- PetBuilder's FLAP_HZ (beats per second at Flap = 1, Excited = 0)
local MAX_BEAT_HZ = 6.0 -- ceiling for the whole product, at the fastest per-pet flapVar
local FLAP_VAR_MAX = 1.15 -- 0.9 + 0.25, the top of the per-pet flapVar range

local BUILD_OPTS = { Scale = 1 }

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local initialized = false
local petsFolder = nil -- workspace.ClientPets
local followers = {} -- [Player] = follower
local order = {} -- array of followers (swap-remove), iterated every frame
local followerCount = 0
local localFollower = nil -- the follower of LocalPlayer (reference point for culling)
local renderConn = nil
local playerConns = {}
local frameIndex = 0
local buildsThisFrame = 0 -- models built in the current frame
local buildStart = 0 -- os.clock() when the frame's first build started
local movedRigid, movedPivot = 0, 0 -- pets posed in the current frame (root write / PivotTo fallback)
local lastRigid, lastPivot = 0, 0 -- ... in the last finished frame (GetMoveStats)
local nextFolderCheck = 0
local warnedAt = {} -- [key] = os.clock() of the last warning (rate limit)
-- Phase 4: every new helper lives in this table (keeps the file's active locals low)
local P4 = {
	heights = {}, -- ["key|stage"] = measured model height (GetExtentsSize Y, Scale 1)
	overrides = {}, -- [key] = stage passed to PlayEvolution (until State's PetGrowth catches up)
	parks = {}, -- [key] = { Until = os.clock(), From = Vector3 | nil } while PlayEvolution parks that follower
	nextGlobal = 0, -- os.clock() of the next card / evolved-model selection
	stateConn = nil,
	menu = nil, -- MenuController (lazy, for the EVOLVE! pill)
}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

-- Shortest signed difference of two angles, in [-PI, PI).
local function wrapAngle(a)
	return (a + PI) % TAU - PI
end

local function warnLimited(key, message)
	local now = os.clock()
	local last = warnedAt[key]
	if last == nil or now - last > 10 then
		warnedAt[key] = now
		warn("[PetController] " .. tostring(message))
	end
end

local function ensurePetsFolder()
	if petsFolder and petsFolder.Parent == workspace then
		return petsFolder
	end
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		petsFolder = existing
	else
		petsFolder = Instance.new("Folder")
		petsFolder.Name = FOLDER_NAME
		petsFolder.Parent = workspace
	end
	return petsFolder
end

----------------------------------------------------------------------
-- Slots
----------------------------------------------------------------------
-- side, up, back, ahead for pet `i` of `n` (a generic fan for unusual MaxEquipped values).
local function slotOffsets(n, i)
	local set = FORMATION[n]
	local s = set and set[i]
	if s then
		return s[1], s[2], s[3], s[4]
	end
	-- Phase 4: a trailing fan behind the owner (contract 3.9), never ahead
	local a = ((i - 0.5) / n - 0.5) * 2.4 -- -1.2 .. +1.2 radians
	local side = sin(a) * 2.4
	local back = 4 + (1 - cos(a)) * 2.5
	local up = 1.9 + (i % 3) * 0.55
	return side, up, back, 0
end

local function assignSlots(f)
	local n = f.n
	for i = 1, n do
		local p = f.pets[i]
		p.slot = i
		p.side, p.up, p.back, p.ahead = slotOffsets(n, i)
	end
end

----------------------------------------------------------------------
-- Pet records and models
----------------------------------------------------------------------
local function newPetRecord(def, key)
	local rnd = math.random
	return {
		def = def,
		id = key or def.Id, -- the copy's key (tier copies and hybrids are different followers than Normal ones)
		model = nil,
		slot = 1,
		side = 0,
		up = 2,
		back = 1,
		ahead = 0,
		lift = 0, -- extra hover for tall pets
		-- Phase 4
		key = key or def.Id,
		infoIndex = 0, -- position of the key in EquippedPets (EquippedInfo uses the same order)
		stage = 0, -- the stage the model was built at
		want = 0, -- the stage the pet has (card stars; the model follows unless capped)
		level = 1,
		backMul = 1, -- evolved followers trail a little further back
		height = 2.7,
		card = nil, -- PetCard (own pets always, others' only when selected)
		rebuildAt = nil, -- os.clock() when the model must be rebuilt at `want`
		parked = false, -- PlayEvolution: hidden while the evolution plays
		emergeFrom = nil, -- Vector3: the next fresh pose starts here (the evolved clone's spot)
		diveStep = 0,
		-- personality (so a group never moves in lockstep)
		phase = rnd() * TAU,
		phase2 = rnd() * TAU,
		bobRate = 2.3 + rnd() * 1.1,
		bobAmp = 0.34 + rnd() * 0.16,
		swayRate = 0.8 + rnd() * 0.6,
		swayAmp = 0.35 + rnd() * 0.3,
		rateH = 5.6 + rnd() * 2.0,
		rateV = 7.5 + rnd() * 2.5,
		flapVar = 0.9 + rnd() * 0.25,
		yawBias = (rnd() - 0.5) * 0.3,
		-- motion state
		x = 0,
		y = 0,
		z = 0,
		yaw = 0,
		pitch = 0,
		roll = 0,
		fresh = 1, -- 0 settled, 1 snap into the slot, 2 emerge from the owner
		retryAt = 0,
		animFails = 0,
		root = nil, -- the model's anchored PrimaryPart
		rigid = false, -- true: the static parts are welded to `root` (a pose is one root CFrame write)
		pivotInv = nil, -- inverse of root.PivotOffset when it is not the identity
		opts = { Flap = 1, Excited = 0 }, -- reused every frame for PetBuilder.Animate
	}
end

local function destroyPetModel(p)
	local model = p.model
	p.model = nil
	p.root = nil
	p.rigid = false
	if p.card then
		pcall(p.card.Destroy, p.card)
		p.card = nil
	end
	if model then
		pcall(model.Destroy, model)
	end
end

-- Parts that PetBuilder.Animate re-poses on every call: members of a PB_G group with a PB_Base pose, except the
-- eyelids ("lid" groups only change their transparency, they move with the head like every static part).
local function isAnimatedPart(part)
	local spec = part:GetAttribute("PB_G")
	if type(spec) ~= "string" or type(part:GetAttribute("PB_Base")) ~= "string" then
		return false
	end
	local kind = string.match(spec, "^[^:]*:([^:]*)")
	return kind ~= "lid"
end

-- Welds parts of `model` to its anchored `root` at their current offset (once per build, never per frame).
-- all = false: the static parts only (Animate keeps posing the rest); true: every part that is still anchored.
local function weldParts(model, root, all)
	local inv = root.CFrame:Inverse()
	local identity = CFrame.new()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root and part.Anchored and (all or not isAnimatedPart(part)) then
			local weld = Instance.new("Weld")
			weld.Name = WELD_NAME
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = inv * part.CFrame
			weld.C1 = identity
			weld.Parent = part
			part.Anchored = false
		end
	end
	root.Anchored = true
end

-- Builds the model of one pet (inside pcall: a broken definition must not take the controller down).
-- Phase 4: the stage goes through opts.Evolved only (never on the shared def); own evolved pets are Low detail.
local function buildModel(f, p)
	local stage = P4.modelStage(f, p)
	local detail = (f.isLocal and stage == 0) and "High" or "Low" -- v3 LOD: own pets High, others Low; evolved Low
	local opts = { Scale = BUILD_OPTS.Scale, Detail = detail }
	if stage > 0 then
		opts.Evolved = stage
	end
	local ok, model = pcall(PetBuilder.Build, p.def, opts)
	if not ok or typeof(model) ~= "Instance" then
		p.retryAt = os.clock() + BUILD_RETRY
		warnLimited("build_" .. tostring(p.id), "could not build pet " .. tostring(p.id) .. ": " .. tostring(model))
		return
	end
	p.stage = stage
	p.rebuildAt = nil
	-- the model's height, measured once per key|stage: taller pets hover a little higher, evolved ones trail
	-- further back, and the card floats over the head
	local hkey = tostring(p.key) .. "|" .. stage
	local h = P4.heights[hkey]
	if not h then
		local okSize, size = pcall(model.GetExtentsSize, model)
		if okSize and typeof(size) == "Vector3" then
			h = size.Y
			P4.heights[hkey] = h
		end
	end
	h = h or 2.7
	p.height = h
	p.lift = clamp((h - 2.7) * 0.35, -0.4, 0.6)
	p.backMul = 1
	if stage > 0 then
		p.backMul = clamp(h / 3, 1, P4K.EVO_BACK_MAX)
	end
	pcall(model.SetAttribute, model, "PC_Key", tostring(p.key))
	pcall(model.SetAttribute, model, "PC_Stage", stage)
	-- weld the static parts to the anchored root once: every later pose is a single root CFrame write
	-- (followers live in workspace, where joints are solved; never do this inside a ViewportFrame)
	local root = model.PrimaryPart
	p.root, p.rigid, p.pivotInv = nil, false, nil
	if root and root:IsA("BasePart") then
		local okWeld, err = pcall(weldParts, model, root, false)
		if okWeld then
			p.root = root
			p.rigid = true
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = root.PivotOffset:GetComponents()
			if abs(x) + abs(y) + abs(z) > 1e-6 or abs(r00 - 1) + abs(r11 - 1) + abs(r22 - 1) + abs(r01) + abs(r02) + abs(r10) + abs(r12) + abs(r20) + abs(r21) > 1e-6 then
				p.pivotInv = root.PivotOffset:Inverse()
			end
		else
			warnLimited("weld_" .. tostring(p.id), "could not weld pet " .. tostring(p.id) .. ", using PivotTo: " .. tostring(err))
		end
	end
	p.model = model
	p.animFails = 0
	model.Parent = f.folder
	if f.isLocal or p.cardOk then
		P4.ensureCard(f, p) -- a rebuilt model keeps its card (others' cards: chosen by P4.globalTick)
	end
end

-- Animate gave up on this pet: weld its animated parts too (in their last pose), so they keep following.
local function freezeAnimatedParts(p)
	if p.rigid and p.model and p.root then
		pcall(weldParts, p.model, p.root, true)
	end
end

----------------------------------------------------------------------
-- Follower lifecycle
----------------------------------------------------------------------
local function newFollower(player)
	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	return {
		player = player,
		userId = player.UserId,
		isLocal = (player == LocalPlayer),
		folder = folder,
		visible = false,
		pets = {},
		n = 0,
		csv = "",
		hyb = "",
		applied = false,
		char = nil,
		root = nil,
		conns = {},
		index = 0,
		downed = false,
		established = false,
		failures = 0,
		disabled = false,
		nextRootCheck = 0,
		nextSlow = 0,
		accDt = 0,
		resetPending = true,
		-- owner motion estimate
		ox = 0,
		oy = 0,
		oz = 0,
		vx = 0,
		vy = 0,
		vz = 0,
		runK = 0,
		airK = 0,
		downK = 0,
		headYaw = 0,
		-- Phase 4
		info = {}, -- EquippedInfo: [index] = { level, stage }
		infoText = nil,
		dist = 0, -- studs from the viewer (2 Hz)
		portal = nil, -- the open home portal { x, y, z } (HomePortal attribute)
		portalGone = nil, -- the portal that closed last ...
		portalGoneAt = -1e9, -- ... and when (os.clock())
		arrivedAt = -1e9, -- PortalArrived seen (os.clock())
		dive = false, -- portal dive running
		diveT0 = 0,
		diveX = 0,
		diveY = 0,
		diveZ = 0,
	}
end

local function snapAllPets(f)
	for i = 1, f.n do
		f.pets[i].fresh = 1
	end
end

-- Shows / parks the follower's folder. Positions are stale after being parked, so snap on show.
local function setVisible(f, visible)
	if f.visible == visible then
		return
	end
	f.visible = visible
	if visible then
		f.folder.Parent = ensurePetsFolder()
		f.resetPending = true
		f.accDt = 0
		snapAllPets(f)
	else
		f.folder.Parent = nil
	end
	P4.syncCards(f)
end

-- The owner has no character (died, respawning, left): pets are destroyed and rebuilt for the new one.
local function releaseCharacter(f)
	f.root = nil
	f.char = nil
	f.established = false
	f.nextRootCheck = 0
	setVisible(f, false)
	for i = 1, f.n do
		local p = f.pets[i]
		destroyPetModel(p)
		p.fresh = 1
	end
end

local function acquireRoot(f)
	local char = f.player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not root.Parent then
		return
	end
	f.root = root
	f.char = char
	local pos = root.Position
	f.ox, f.oy, f.oz = pos.X, pos.Y, pos.Z
	f.vx, f.vy, f.vz = 0, 0, 0
	f.runK, f.airK, f.downK = 0, 0, 0
	f.resetPending = true
	f.accDt = 0
	local look = root.CFrame.LookVector
	f.headYaw = atan2(-look.X, -look.Z)
	snapAllPets(f)
end

-- "uid=Body/Style/Tier/Rarity[/Seed];..." -> a stand-in profile { Hybrids = { [uid] = record } } for PetKeys.DefOf
local function parseHybrids(text)
	local hybrids = {}
	if type(text) ~= "string" then
		return { Hybrids = hybrids }
	end
	for entry in string.gmatch(text, "[^;]+") do
		local uid, rest = string.match(entry, "^%s*([%w_%-]+)=(.+)$")
		if uid then
			local fields = {}
			for field in string.gmatch(rest .. "/", "([^/]*)/") do
				fields[#fields + 1] = field
			end
			if fields[1] and fields[1] ~= "" and fields[2] and fields[2] ~= "" then
				local rec = { Body = fields[1], Style = fields[2], Tier = "Normal" }
				if fields[3] == "Golden" or fields[3] == "Rainbow" then
					rec.Tier = fields[3]
				end
				if fields[4] and fields[4] ~= "" then
					rec.Rarity = fields[4]
				end
				local seed = tonumber(fields[5])
				if seed then
					rec.Seed = seed
				end
				hybrids[uid] = rec
			end
		end
	end
	return { Hybrids = hybrids }
end

-- The definition to build for one key (nil: skip it).
local function defForKey(key, hybridProfile)
	if PetKeys then
		local ok, def = pcall(PetKeys.DefOf, key, hybridProfile)
		if ok and type(def) == "table" then
			return def
		end
		return nil
	end
	return PetCatalog.Get(key)
end

-- Rebuilds the pet list from the player's attributes: keeps matching pets, destroys the rest, adds new ones.
local function applyEquipped(f)
	local csv = f.player:GetAttribute(ATTR.EquippedPets)
	if type(csv) ~= "string" then
		csv = ""
	end
	local hyb = f.player:GetAttribute(HYBRID_ATTR)
	if type(hyb) ~= "string" then
		hyb = ""
	end
	if f.applied and csv == f.csv and hyb == f.hyb then
		return
	end
	f.applied = true
	f.csv = csv
	f.hyb = hyb

	local hybridProfile = parseHybrids(hyb)
	local wanted, wantedKeys, wantedIndex = {}, {}, {}
	local index = 0
	for token in string.gmatch(csv, "[^,]+") do
		index = index + 1
		local key = string.match(token, "^%s*(.-)%s*$")
		local def = key ~= "" and defForKey(key, hybridProfile) or nil
		if def and #wanted < MAX_EQUIPPED then
			wanted[#wanted + 1] = def
			wantedKeys[#wanted] = key
			wantedIndex[#wanted] = index
		end
	end

	local old = f.pets
	local used = {}
	local pets = {}
	for i = 1, #wanted do
		local def = wanted[i]
		local key = wantedKeys[i]
		local found = nil
		for j = 1, #old do
			-- same key and the same definition (a hybrid whose record changed is rebuilt)
			if not used[j] and old[j].id == key and old[j].def == def then
				used[j] = true
				found = old[j]
				break
			end
		end
		if not found then
			found = newPetRecord(def, key)
			-- a pet equipped while its owner is already flying around emerges from the owner
			if f.established then
				found.fresh = 2
			end
		end
		found.infoIndex = wantedIndex[i]
		pets[i] = found
	end
	for j = 1, #old do
		if not used[j] then
			destroyPetModel(old[j])
		end
	end
	f.pets = pets
	f.n = #pets
	assignSlots(f)
	P4.refreshFollower(f)
end

local function destroyFollower(f)
	for i = 1, #f.conns do
		pcall(f.conns[i].Disconnect, f.conns[i])
	end
	f.conns = {}
	for i = 1, #f.pets do
		destroyPetModel(f.pets[i])
	end
	f.pets = {}
	f.n = 0
	f.root = nil
	f.char = nil
	local folder = f.folder
	f.folder = nil
	f.visible = false
	if folder then
		pcall(folder.Destroy, folder)
	end
end

local function removeFollower(player)
	local f = followers[player]
	if not f then
		return
	end
	followers[player] = nil
	if localFollower == f then
		localFollower = nil
	end
	local idx = f.index
	local last = order[followerCount]
	if last ~= f then
		order[idx] = last
		last.index = idx
	end
	order[followerCount] = nil
	followerCount = followerCount - 1
	destroyFollower(f)
end

local function trackPlayer(player)
	if followers[player] then
		return
	end
	local f = newFollower(player)
	followers[player] = f
	if f.isLocal then
		localFollower = f
	end
	followerCount = followerCount + 1
	f.index = followerCount
	order[followerCount] = f

	local conns = f.conns
	conns[#conns + 1] = player:GetAttributeChangedSignal(ATTR.EquippedPets):Connect(function()
		applyEquipped(f)
	end)
	conns[#conns + 1] = player:GetAttributeChangedSignal(HYBRID_ATTR):Connect(function()
		applyEquipped(f)
	end)
	conns[#conns + 1] = player:GetAttributeChangedSignal(ATTR.Downed):Connect(function()
		f.downed = player:GetAttribute(ATTR.Downed) == true
	end)
	conns[#conns + 1] = player.CharacterAdded:Connect(function()
		f.nextRootCheck = 0 -- look for the new HumanoidRootPart on the next frame
	end)
	conns[#conns + 1] = player.CharacterRemoving:Connect(function(char)
		if f.char == char then
			releaseCharacter(f)
		end
	end)

	-- Phase 4: levels / stages of the equipped pets, the home portal
	conns[#conns + 1] = player:GetAttributeChangedSignal(P4.attr("EquippedInfo")):Connect(function()
		P4.readInfo(f)
		P4.refreshFollower(f)
	end)
	conns[#conns + 1] = player:GetAttributeChangedSignal(P4.attr("HomePortal")):Connect(function()
		P4.readPortal(f)
	end)
	conns[#conns + 1] = player:GetAttributeChangedSignal(P4.attr("PortalArrived")):Connect(function()
		f.arrivedAt = os.clock()
	end)

	f.downed = player:GetAttribute(ATTR.Downed) == true
	P4.readInfo(f)
	P4.readPortal(f)
	applyEquipped(f)
end

----------------------------------------------------------------------
-- Phase 4: levels, stages, pet cards, the evolution park and the portal dive (helpers live in P4)
----------------------------------------------------------------------
function P4.attr(name)
	return (type(ATTR) == "table" and ATTR[name]) or name
end

-- EquippedInfo "23:1,5:0" -> f.info[i] = { level, stage } (the order of EquippedPets)
function P4.readInfo(f)
	local text = f.player:GetAttribute(P4.attr("EquippedInfo"))
	if type(text) ~= "string" then
		text = ""
	end
	if text == f.infoText then
		return
	end
	f.infoText = text
	local info = {}
	local i = 0
	for token in string.gmatch(text, "[^,]+") do
		i = i + 1
		local lv, st = string.match(token, "^%s*(%d+)%s*:%s*(%d+)%s*$")
		if not lv then
			lv = string.match(token, "^%s*(%d+)%s*$")
		end
		info[i] = { math.max(1, math.floor(tonumber(lv) or 1)), clamp(math.floor(tonumber(st) or 0), 0, 2) }
	end
	f.info = info
end

-- HomePortal "x,y,z,yaw,closesAt" -> f.portal { x, y, z }; a portal that closes is remembered for the dive
function P4.readPortal(f)
	local text = f.player:GetAttribute(P4.attr("HomePortal"))
	local portal = nil
	if type(text) == "string" then
		local x, y, z = string.match(text, "^%s*([%-%d%.eE]+)%s*,%s*([%-%d%.eE]+)%s*,%s*([%-%d%.eE]+)")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if x and y and z and x == x and y == y and z == z then
			portal = { x, y, z }
		end
	end
	if not portal and f.portal then
		f.portalGone = f.portal
		f.portalGoneAt = os.clock()
	end
	f.portal = portal
end

-- the owner jumped > 35 studs: was it a trip through their home portal? (sets the dive centre)
function P4.portalJustUsed(f, now)
	local gone = f.portalGone
	if gone and (now - f.portalGoneAt <= P4K.DIVE_WINDOW or now - f.arrivedAt <= P4K.DIVE_WINDOW) then
		f.diveX, f.diveY, f.diveZ = gone[1], gone[2], gone[3]
		return true
	end
	local open = f.portal
	if open then
		local dx, dy, dz = f.ox - open[1], f.oy - open[2], f.oz - open[3]
		if dx * dx + dy * dy + dz * dz <= P4K.DIVE_NEAR * P4K.DIVE_NEAR then
			f.diveX, f.diveY, f.diveZ = open[1], open[2], open[3]
			return true
		end
	end
	return false
end

function P4.startDive(f, now)
	f.dive = true
	f.diveT0 = now
	f.diveY = f.diveY + 1.2 -- the swirl's centre stands above the ground point
	f.portalGone = nil
	for i = 1, f.n do
		local p = f.pets[i]
		p.diveStep = 0
		if p.model and p.rigid and p.root then
			-- everything follows the root now (the model is rebuilt when the dive ends)
			pcall(weldParts, p.model, p.root, true)
		end
	end
	P4.syncCards(f)
end

-- one frame of the dive: each pet flies into the portal centre (one root write) and shrinks in 3 steps
function P4.stepDive(f, dt, now, px, py, pz)
	f.ox, f.oy, f.oz = px, py, pz -- keep tracking the owner (no second teleport after the dive)
	local t = (now - f.diveT0) / P4K.DIVE_TIME
	if t >= 1 then
		P4.endDive(f)
		return
	end
	local remaining = math.max(0.02, (1 - t) * P4K.DIVE_TIME)
	local k = clamp(dt / remaining, 0, 1)
	local step = math.floor(t * 4)
	for i = 1, f.n do
		local p = f.pets[i]
		local model = p.model
		if model then
			local nx = p.x + (f.diveX - p.x) * k
			local ny = p.y + (f.diveY - p.y) * k
			local nz = p.z + (f.diveZ - p.z) * k
			p.x, p.y, p.z = nx, ny, nz
			local syw, cyw = sin(p.yaw), cos(p.yaw)
			local cf = CFrame.new(nx, ny, nz, cyw, 0, syw, 0, 1, 0, -syw, 0, cyw)
			local root = p.root
			if p.rigid and root and root.Parent == model then
				if p.pivotInv then
					root.CFrame = cf * p.pivotInv
				else
					root.CFrame = cf
				end
				movedRigid = movedRigid + 1
			else
				model:PivotTo(cf)
				movedPivot = movedPivot + 1
			end
			if step > p.diveStep then
				p.diveStep = step
				pcall(model.ScaleTo, model, math.max(0.15, 1 - 0.27 * step))
			end
		end
	end
end

-- the dive is over: fresh models pop out of the arrival ring behind the owner
function P4.endDive(f)
	f.dive = false
	f.vx, f.vy, f.vz = 0, 0, 0
	local root = f.root
	if root and root.Parent then
		local look = root.CFrame.LookVector
		if look.X * look.X + look.Z * look.Z > 0.04 then
			f.headYaw = atan2(-look.X, -look.Z)
		end
	end
	for i = 1, f.n do
		local p = f.pets[i]
		destroyPetModel(p)
		p.fresh = 2
		p.retryAt = 0
	end
end

-- the stored evolution stage of an own pet (State), never below a stage PlayEvolution announced
function P4.ownStage(p, level)
	local stored = 0
	if State and type(State.PetGrowth) == "function" then
		local ok, g = pcall(State.PetGrowth, p.key)
		if ok and type(g) == "table" then
			stored = tonumber(g.Evo) or 0
		end
	end
	local over = P4.overrides[p.key]
	if over then
		if stored >= over then
			P4.overrides[p.key] = nil
		else
			stored = over
		end
	end
	local ok, stage = pcall(PetCatalog.EvolutionStage, p.def, level, stored)
	if ok and type(stage) == "number" then
		return stage
	end
	return clamp(math.floor(stored), 0, 2)
end

-- level, stage, XP fill (0..1) and EVOLVE readiness of one pet
function P4.petInfo(f, p)
	local entry = f.info[p.infoIndex]
	local level, stage = entry and entry[1] or 1, entry and entry[2] or 0
	if not f.isLocal then
		local okMax, top = pcall(PetCatalog.MaxEvolution, p.def)
		if okMax and type(top) == "number" and stage > top then
			stage = top
		end
		return level, stage, 0, false
	end
	local xp = 0
	if State and type(State.IsLoaded) == "function" and State.IsLoaded() then
		local okL, lv, x = pcall(State.PetLevel, p.key)
		if okL and type(lv) == "number" then
			level, xp = lv, tonumber(x) or 0
		end
		stage = P4.ownStage(p, level)
	else
		local over = P4.overrides[p.key]
		if over and over > stage then
			stage = over
		end
	end
	local frac = 1
	local cap = nil
	local okCap, c = pcall(PetCatalog.LevelCap, p.def)
	if okCap and type(c) == "number" then
		cap = c
	end
	local need = nil
	if TycoonCatalog and type(TycoonCatalog.XpToNext) == "function" then
		local okN, n = pcall(TycoonCatalog.XpToNext, level)
		if okN and type(n) == "number" then
			need = n
		end
	end
	if not (cap and level >= cap) and need and need > 0 and need < math.huge then
		frac = clamp(xp / need, 0, 1)
	end
	local okR, nextStage = pcall(PetCatalog.CanEvolve, p.def, level, stage)
	return level, stage, frac, okR and nextStage ~= nil
end

-- the stage the model is built at: own pets always their stage, others' only when allowed (40 studs, 6 at most)
function P4.modelStage(f, p)
	if f.isLocal or p.evoOk then
		return p.want
	end
	return 0
end

-- re-reads levels / stages of a follower's pets: cards, and a rebuild when the model's stage is out of date
function P4.refreshFollower(f)
	local now = os.clock()
	for i = 1, f.n do
		local p = f.pets[i]
		local level, stage, frac, ready = P4.petInfo(f, p)
		p.level, p.want = level, stage
		if f.isLocal then
			local parked = P4.parks[p.key] ~= nil
			if parked and not p.parked then
				p.parked = true
				destroyPetModel(p)
			end
		end
		local card = p.card
		if card then
			pcall(card.SetLevel, card, level, stage, ready)
			if f.isLocal then
				pcall(card.SetXp, card, frac)
			end
		end
		if p.model and P4.modelStage(f, p) ~= p.stage then
			-- a stage that rose by itself waits a moment: PlayEvolution may park the pet for the animation first
			local wait = (f.isLocal and stage > p.stage) and P4K.EVO_GRACE or 0
			if not p.rebuildAt or p.rebuildAt > now + wait then
				p.rebuildAt = now + wait
			end
		elseif p.rebuildAt and p.model then
			p.rebuildAt = nil
		end
	end
end

function P4.openPets(key)
	if not P4.menu then
		P4.menu = optionalModule(script.Parent, "MenuController")
	end
	local MC = P4.menu
	if MC and type(MC.Open) == "function" then
		local ok, err = pcall(MC.Open, "Pets", { Tab = "Pets", Key = key, Action = "Evolve" })
		if not ok then
			warnLimited("menu_open", "could not open the Pets panel: " .. tostring(err))
		end
	end
end

-- shows / hides one pet card with its follower (parked, diving, culled, in battle)
function P4.syncCard(f, p)
	local card = p.card
	if card then
		pcall(card.SetShown, card, f.visible and not f.dive and not p.parked and p.model ~= nil)
	end
end

function P4.syncCards(f)
	for i = 1, f.n do
		P4.syncCard(f, f.pets[i])
	end
end

-- creates (or re-adorns) the card of a pet whose model exists
function P4.ensureCard(f, p)
	local adornee = p.root or (p.model and p.model.PrimaryPart)
	if not PetCard or not p.model or not adornee then
		return
	end
	local height = p.height * 0.5 + P4K.CARD_HEIGHT
	if p.card then
		pcall(p.card.SetAdornee, p.card, adornee, height)
	else
		local key = p.key
		local ok, card = pcall(PetCard.New, adornee, f.isLocal and "Follower" or "Other", height, {
			OnEvolve = function()
				P4.openPets(key)
			end,
		})
		if not ok or type(card) ~= "table" then
			warnLimited("card_" .. tostring(key), "could not build a pet card: " .. tostring(card))
			return
		end
		p.card = card
	end
	local level, stage, frac, ready = P4.petInfo(f, p)
	pcall(p.card.SetLevel, p.card, level, stage, ready)
	if f.isLocal then
		pcall(p.card.SetXp, p.card, frac)
	end
	P4.syncCard(f, p)
end

local function byDist(a, b)
	return a.dist < b.dist
end

-- 2 Hz: other players' cards (nearest 12 within 60 studs) and evolved models (nearest 6 within 40 studs)
function P4.globalTick(now, viewPos)
	if now < P4.nextGlobal then
		return
	end
	P4.nextGlobal = now + P4K.GLOBAL_TICK
	local list = {}
	for i = 1, followerCount do
		local f = order[i]
		if f and not f.isLocal then
			local root = f.root
			if f.visible and root and root.Parent and viewPos then
				local d = root.Position - viewPos
				f.dist = d.Magnitude
				list[#list + 1] = f
			else
				f.dist = math.huge
				for j = 1, f.n do
					local p = f.pets[j]
					p.evoOk = false
					p.cardOk = false
					if p.card then
						pcall(p.card.Destroy, p.card)
						p.card = nil
					end
				end
			end
		end
	end
	table.sort(list, byDist)
	local cards, evos = 0, 0
	for i = 1, #list do
		local f = list[i]
		for j = 1, f.n do
			local p = f.pets[j]
			-- evolved look: nearest first, at most 6, a shown one keeps it a little further out
			local ok = false
			if p.want > 0 and evos < P4K.OTHER_EVO_MAX then
				local reach = (p.stage > 0) and P4K.OTHER_EVO_OUT or P4K.OTHER_EVO_IN
				if f.dist <= reach then
					ok = true
					evos = evos + 1
				end
			end
			p.evoOk = ok
			if p.model and P4.modelStage(f, p) ~= p.stage and not p.rebuildAt then
				p.rebuildAt = now
			end
			-- the level card: nearest first, at most 12
			if not f.dive and cards < P4K.OTHER_CARDS and f.dist <= P4K.OTHER_CARD_DIST then
				cards = cards + 1
				p.cardOk = true
				if p.model and not p.card then
					P4.ensureCard(f, p)
				end
			else
				p.cardOk = false
				if p.card then
					pcall(p.card.Destroy, p.card)
					p.card = nil
				end
			end
		end
	end
end

-- per follower, a few times a second: parks that ran out
function P4.slowFollower(f, now)
	if not f.isLocal then
		return
	end
	for i = 1, f.n do
		local p = f.pets[i]
		if p.parked then
			local park = P4.parks[p.key]
			if not park or now >= park.Until then
				P4.parks[p.key] = nil
				P4.unparkKey(p.key, park and park.From or nil)
			end
		end
	end
end

function P4.unparkKey(key, from)
	local f = localFollower
	if not f then
		return
	end
	for i = 1, f.n do
		local p = f.pets[i]
		if p.key == key and p.parked then
			p.parked = false
			p.fresh = 2
			p.emergeFrom = from
			p.retryAt = 0
			p.rebuildAt = nil
		end
	end
	P4.refreshFollower(f)
end

-- seconds the evolution animation lasts (EvolutionFx.Duration), else a safe default
function P4.fxDuration(stage)
	local Fx = optionalModule(script.Parent, "EvolutionFx")
	if Fx and type(Fx.Duration) == "function" then
		local ok, d = pcall(Fx.Duration, stage)
		if ok and type(d) == "number" and d > 0 and d < 30 then
			return d + 0.3
		end
	end
	return P4K.PARK_DEFAULT
end

function P4.onStateChanged()
	if localFollower then
		P4.refreshFollower(localFollower)
	end
end

----------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------
-- Advances one follower by dt seconds. `viewPos` is where the viewer is (Vector3 or nil).
local function stepFollower(f, dt, now, viewPos)
	-- 1. owner root ------------------------------------------------------------------------------
	local root = f.root
	if root and not root.Parent then
		releaseCharacter(f)
		root = nil
	end
	if not root then
		if now >= f.nextRootCheck then
			f.nextRootCheck = now + ROOT_POLL
			acquireRoot(f)
			root = f.root
		end
		if not root then
			return
		end
	end

	-- 2. housekeeping a few times per second ---------------------------------------------------
	if now >= f.nextSlow then
		f.nextSlow = now + SLOW_TICK + (f.index % 5) * 0.02
		if f.player.Character ~= f.char then
			releaseCharacter(f) -- the character was replaced; the next poll picks up the new one
			return
		end
		if f.visible and f.folder.Parent ~= petsFolder then
			f.folder.Parent = ensurePetsFolder()
		end
		P4.slowFollower(f, now)
	end

	local rootPos = root.Position
	local px, py, pz = rootPos.X, rootPos.Y, rootPos.Z
	if px ~= px or py ~= py or pz ~= pz then
		return -- a broken (NaN) character position: wait for it to recover instead of poisoning the pets
	end

	-- 2b. Phase 4: the home portal dive (played out wherever the owner went, before any culling) ----------------
	if not f.dive and f.visible and f.established then
		local jx, jy, jz = px - f.ox, py - f.oy, pz - f.oz
		if jx * jx + jy * jy + jz * jz > TELEPORT_STEP2 and P4.portalJustUsed(f, now) then
			P4.startDive(f, now)
		end
	end
	if f.dive then
		P4.stepDive(f, dt, now, px, py, pz)
		return
	end

	-- 3. culling + level of detail -------------------------------------------------------------
	if f.player:GetAttribute("InBattle") ~= nil then -- Phase 3: the team fights (BattleController draws it): park the followers
		setVisible(f, false)
		return
	end
	if f.isLocal then
		if not f.visible then
			setVisible(f, true)
		end
	else
		local dist = 0
		if viewPos then
			local cx, cy, cz = px - viewPos.X, py - viewPos.Y, pz - viewPos.Z
			dist = sqrt(cx * cx + cy * cy + cz * cz)
		end
		if f.visible then
			if dist > CULL_OUT then
				setVisible(f, false)
				return
			end
		else
			if dist > CULL_IN then
				return
			end
			setVisible(f, true)
		end
		local stride = 1
		if dist > LOD_FAR then
			stride = 4
		elseif dist > LOD_MID then
			stride = 2
		end
		f.accDt = f.accDt + dt
		if stride > 1 and (frameIndex + f.index) % stride ~= 0 then
			return
		end
		dt = f.accDt
		f.accDt = 0
		if dt > MAX_DT then
			dt = MAX_DT
		end
	end
	if dt < MIN_DT then
		dt = MIN_DT
	end

	-- 4. owner motion estimate ---------------------------------------------------------------------
	local dx, dy, dz = px - f.ox, py - f.oy, pz - f.oz
	f.ox, f.oy, f.oz = px, py, pz
	local teleported = f.resetPending
	f.resetPending = false
	if dx * dx + dy * dy + dz * dz > TELEPORT_STEP2 then
		teleported = true
	end
	if teleported then
		f.vx, f.vy, f.vz = 0, 0, 0
		snapAllPets(f)
	else
		local kv = 1 - exp(-VEL_RATE * dt)
		f.vx = f.vx + (clamp(dx / dt, -MAX_SPEED, MAX_SPEED) - f.vx) * kv
		f.vy = f.vy + (clamp(dy / dt, -MAX_SPEED, MAX_SPEED) - f.vy) * kv
		f.vz = f.vz + (clamp(dz / dt, -MAX_SPEED, MAX_SPEED) - f.vz) * kv
	end
	local vx, vz = f.vx, f.vz
	local hs = sqrt(vx * vx + vz * vz)

	-- formation heading: travel direction, or the owner's facing when standing still
	local targetHead = f.headYaw
	local headRate = HEAD_RATE_IDLE
	if hs > HEAD_MIN_SPEED then
		targetHead = atan2(-vx, -vz)
		headRate = HEAD_RATE_MOVE
	else
		local look = root.CFrame.LookVector
		if look.X * look.X + look.Z * look.Z > 0.04 then
			targetHead = atan2(-look.X, -look.Z)
		end
	end
	if teleported then
		f.headYaw = targetHead
	else
		f.headYaw = wrapAngle(f.headYaw + wrapAngle(targetHead - f.headYaw) * (1 - exp(-headRate * dt)))
	end

	local runTarget = clamp((hs - RUN_K_FROM) / RUN_K_SPAN, 0, 1.3)
	f.runK = f.runK + (runTarget - f.runK) * (1 - exp(-RUN_RATE * dt))
	local airTarget = clamp((abs(f.vy) - 8) / 30, 0, 1)
	f.airK = f.airK + (airTarget - f.airK) * (1 - exp(-AIR_RATE * dt))
	local downTarget = 0
	if f.downed then
		downTarget = 1
	end
	f.downK = f.downK + (downTarget - f.downK) * (1 - exp(-DOWN_RATE * dt))

	local runK, airK, downK = f.runK, f.airK, f.downK
	-- Excited does most of the speeding up (and also widens the wing sweep and wags the tail); Flap only adds a
	-- little on top, and is capped so FLAP_HZ * Flap * (1 + 1.25 * Excited) stays below MAX_BEAT_HZ.
	local flapBase = 1 + 0.2 * runK + 0.25 * airK
	local excited = clamp(0.55 * runK + 0.75 * airK, 0, 1)
	if downK > 0 then
		flapBase = flapBase * (1 - 0.4 * downK)
		excited = excited * (1 - downK)
	end
	local flapCap = MAX_BEAT_HZ / (PB_FLAP_HZ * (1 + 1.25 * excited) * FLAP_VAR_MAX)
	if flapBase > flapCap then
		flapBase = flapCap
	end
	local compact = 1 - 0.45 * downK -- downed owners keep their pets close
	local leadX, leadZ = vx * LEAD_H, vz * LEAD_H
	local leadY = clamp(f.vy * LEAD_V, -1, 1.5)

	local face = f.headYaw
	local sh, ch = sin(face), cos(face)
	local rx, rz = ch, -sh -- owner's right (horizontal)
	local fx, fz = -sh, -ch -- owner's forward (horizontal)

	-- 5. pets ----------------------------------------------------------------------------------------
	local pets = f.pets
	for i = 1, f.n do
		local p = pets[i]
		local model = p.model
		if p.rebuildAt and now >= p.rebuildAt and not p.parked then
			-- Phase 4: the stage changed (EVOLVE, EquippedInfo, the 40-stud rule): rebuild where the pet is
			p.rebuildAt = nil
			destroyPetModel(p)
			model = nil
		end
		if not model and not p.parked and now >= p.retryAt and buildsThisFrame < BUILD_MAX
			and (buildsThisFrame == 0 or os.clock() - buildStart < BUILD_BUDGET) then
			if buildsThisFrame == 0 then
				buildStart = os.clock()
			end
			buildsThisFrame = buildsThisFrame + 1
			buildModel(f, p)
			model = p.model
		end
		if model then
			-- target position in the owner's frame
			local bob = sin(now * p.bobRate + p.phase) * p.bobAmp * (1 - 0.5 * downK)
			local sway = sin(now * p.swayRate + p.phase2) * p.swayAmp
			local side = p.side * compact + sway
			local fwd = p.ahead * RUN_AHEAD * runK - p.back * p.backMul * compact
			local tx = px + rx * side + fx * fwd + leadX
			local tz = pz + rz * side + fz * fwd + leadZ
			local ty = py + p.up * (1 - 0.2 * downK) + p.lift + bob + (1.2 - p.ahead) * RUN_RISE * runK + leadY

			if p.fresh ~= 0 then
				local from = p.emergeFrom
				if from then
					p.x, p.y, p.z = from.X, from.Y, from.Z -- Phase 4: where the evolved clone stood
					p.emergeFrom = nil
				elseif p.fresh == 2 then
					p.x, p.y, p.z = px, py + 0.5, pz -- emerge from the owner's chest (also out of the arrival ring)
				else
					p.x, p.y, p.z = tx, ty, tz
				end
				p.yaw = face
				p.pitch, p.roll = 0, 0
				p.fresh = 0
			end

			local ox, oy, oz = p.x, p.y, p.z
			local ex, ey, ez = tx - ox, ty - oy, tz - oz
			if ex * ex + ey * ey + ez * ez > SNAP_DIST2 then
				ox, oy, oz = tx, ty, tz
				ex, ey, ez = 0, 0, 0
				p.yaw = face
			end
			local kh = 1 - exp(-p.rateH * dt)
			local kvv = 1 - exp(-p.rateV * dt)
			local nx, ny, nz = ox + ex * kh, oy + ey * kvv, oz + ez * kh
			p.x, p.y, p.z = nx, ny, nz
			local pvx, pvz = (nx - ox) / dt, (nz - oz) / dt

			-- facing, banking, pitch
			local yawOld = p.yaw
			local wobble = 0.1 * sin(now * 0.9 + p.phase2)
			local yawStep = wrapAngle(face + p.yawBias + wobble - yawOld) * (1 - exp(-FACE_RATE * dt))
			local yaw = wrapAngle(yawOld + yawStep)
			p.yaw = yaw
			local syw, cyw = sin(yaw), cos(yaw)
			local forwardSpeed = -pvx * syw - pvz * cyw
			local lateralSpeed = pvx * cyw - pvz * syw
			local pitchT = -clamp(forwardSpeed * PITCH_GAIN, -0.28, 0.42)
			local rollT = clamp(yawStep / dt * BANK_GAIN, -BANK_MAX, BANK_MAX)
				- clamp(lateralSpeed * 0.015, -0.3, 0.3)
				+ 0.05 * sin(now * 1.3 + p.phase)
			local kt = 1 - exp(-TILT_RATE * dt)
			local pitch = p.pitch + (pitchT - p.pitch) * kt
			local roll = p.roll + (rollT - p.roll) * kt
			p.pitch, p.roll = pitch, roll

			if nx == nx and ny == ny and nz == nz and pitch == pitch and roll == roll and yaw == yaw then
				-- rotation = Ry(yaw) * Rx(pitch) * Rz(roll), written out so only one CFrame is created
				local spt, cpt = sin(pitch), cos(pitch)
				local srl, crl = sin(roll), cos(roll)
				local cf = CFrame.new(
					nx, ny, nz,
					cyw * crl + syw * spt * srl, -cyw * srl + syw * spt * crl, syw * cpt,
					cpt * srl, cpt * crl, -spt,
					-syw * crl + cyw * spt * srl, syw * srl + cyw * spt * crl, cyw * cpt
				)
				local root = p.root
				if p.rigid and root and root.Parent == model then
					-- one write: the welded static parts follow the anchored root
					if p.pivotInv then
						root.CFrame = cf * p.pivotInv
					else
						root.CFrame = cf
					end
					movedRigid = movedRigid + 1
				else
					model:PivotTo(cf)
					movedPivot = movedPivot + 1
				end

				if p.animFails < 3 then
					local o = p.opts
					o.Flap = flapBase * p.flapVar
					o.Excited = excited
					local okAnim = pcall(PetBuilder.Animate, model, now, o)
					if not okAnim then
						p.animFails = p.animFails + 1
						if p.animFails >= 3 then
							freezeAnimatedParts(p)
						end
					end
				end
			else
				-- numerical accident: restart this pet's motion from its slot on the next update
				p.fresh = 1
			end
		end
	end
	f.established = true
end

local function onRender(dt)
	local count = followerCount
	if count == 0 then
		return
	end
	frameIndex = frameIndex + 1
	buildsThisFrame = 0
	lastRigid, lastPivot = movedRigid, movedPivot
	movedRigid, movedPivot = 0, 0
	if dt > MAX_DT then
		dt = MAX_DT
	end
	local now = os.clock()
	if now >= nextFolderCheck then
		nextFolderCheck = now + 2
		ensurePetsFolder()
	end
	-- the viewer: the local character, else the camera
	local viewPos = nil
	local lf = localFollower
	if lf and lf.root and lf.root.Parent then
		viewPos = lf.root.Position
	else
		local camera = workspace.CurrentCamera
		if camera then
			viewPos = camera.CFrame.Position
		end
	end
	local okTick, errTick = pcall(P4.globalTick, now, viewPos)
	if not okTick then
		warnLimited("global_tick", "card / model selection failed: " .. tostring(errTick))
	end
	for i = 1, count do
		local f = order[i]
		if f and not f.disabled then
			local ok, err = pcall(stepFollower, f, dt, now, viewPos)
			if ok then
				f.failures = 0
			else
				f.failures = f.failures + 1
				warnLimited("step_" .. tostring(f.userId), "update failed: " .. tostring(err))
				if f.failures >= 10 then
					-- give up on this owner's pets rather than erroring every frame
					f.disabled = true
					releaseCharacter(f)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function PetController.GetPetCount()
	local total = 0
	for i = 1, followerCount do
		local f = order[i]
		for j = 1, f.n do
			if f.pets[j].model then
				total = total + 1
			end
		end
	end
	return total
end

-- Pets posed in the last finished frame: Rigid = one root CFrame write (welded statics), Pivot = PivotTo fallback.
function PetController.GetMoveStats()
	return { Rigid = lastRigid, Pivot = lastPivot }
end

-- Phase 4 (contract 3.6): parks the local follower of `key` while the evolution plays elsewhere, then rebuilds it
-- at `stage`. Returns release(fromPosition?) to end the park early (CareController calls it from EvolutionFx's
-- OnDone with the evolved clone's position).
function PetController.PlayEvolution(key, stage, opts)
	if type(key) ~= "string" or key == "" then
		return function() end
	end
	stage = clamp(math.floor(tonumber(stage) or 1), 1, 2)
	local seconds, from = nil, nil
	if type(opts) == "number" then
		seconds = opts
	elseif type(opts) == "table" then
		seconds = tonumber(opts.Seconds)
		if typeof(opts.From) == "Vector3" then
			from = opts.From
		end
	end
	if not seconds or seconds ~= seconds or seconds < 0 then
		seconds = P4.fxDuration(stage)
	end
	seconds = math.min(seconds, 30)
	P4.overrides[key] = math.max(P4.overrides[key] or 0, stage)
	local park = { Until = os.clock() + seconds, From = from }
	P4.parks[key] = park
	if localFollower then
		P4.refreshFollower(localFollower)
	end
	local released = false
	return function(fromPosition)
		if released then
			return
		end
		released = true
		if P4.parks[key] == park then
			P4.parks[key] = nil
			P4.unparkKey(key, typeof(fromPosition) == "Vector3" and fromPosition or from)
		end
	end
end

-- debug helpers (smoke tests): every live pet card, and one owner's followers
function PetController.GetCards()
	local out = {}
	for i = 1, followerCount do
		local f = order[i]
		for j = 1, f.n do
			local p = f.pets[j]
			local card = p.card
			if card and card.Gui then
				out[#out + 1] = { UserId = f.userId, Key = p.key, Mode = card.mode, Gui = card.Gui, Shown = card.Gui.Enabled == true }
			end
		end
	end
	return out
end

function PetController.GetFollowerInfo(player)
	local f = followers[player]
	local out = {}
	if not f then
		return out
	end
	for i = 1, f.n do
		local p = f.pets[i]
		out[i] = {
			Key = p.key, Model = p.model, Stage = p.stage, Want = p.want, Level = p.level,
			Card = p.card and p.card.Gui or nil, Parked = p.parked, Diving = f.dive, Back = p.backMul,
		}
	end
	return out
end

function PetController.Stop()
	if not initialized then
		return
	end
	initialized = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	for i = 1, #playerConns do
		playerConns[i]:Disconnect()
	end
	playerConns = {}
	if P4.stateConn then
		pcall(function()
			P4.stateConn:Disconnect()
		end)
		P4.stateConn = nil
	end
	P4.parks = {}
	P4.overrides = {}
	local list = {}
	for player in pairs(followers) do
		list[#list + 1] = player
	end
	for i = 1, #list do
		removeFollower(list[i])
	end
	if petsFolder then
		pcall(petsFolder.Destroy, petsFolder)
		petsFolder = nil
	end
end

function PetController.Init()
	if initialized then
		return
	end
	if not LocalPlayer then
		return
	end
	initialized = true

	-- a folder left over from an earlier run (hot reload) would hold orphaned models
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	petsFolder = nil
	ensurePetsFolder()

	playerConns[#playerConns + 1] = Players.PlayerAdded:Connect(trackPlayer)
	playerConns[#playerConns + 1] = Players.PlayerRemoving:Connect(removeFollower)
	for _, player in ipairs(Players:GetPlayers()) do
		trackPlayer(player)
	end

	-- Phase 4: own pets' levels / XP / stages follow the profile snapshot
	if State and type(State.Changed) == "table" and type(State.Changed.Connect) == "function" then
		local ok, conn = pcall(function()
			return State.Changed:Connect(function()
				local okR, err = pcall(P4.onStateChanged)
				if not okR then
					warnLimited("state_changed", "pet card refresh failed: " .. tostring(err))
				end
			end)
		end)
		if ok then
			P4.stateConn = conn
		end
	end

	renderConn = RunService.RenderStepped:Connect(onRender)
end

return PetController
