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
--                                      Level, Card = BillboardGui | nil, Parked, Diving, Back / Side = the slot (studs), Width, Slot,
--                                      Sitting = the owner sits and the pet has its ground spot (bug batch 2 #7) } }
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
--   * Phase 5 follow-behind (contract 3.8): pets trail in slots BEHIND the owner chosen from their measured widths
--     (PetController.FormationFor: 1 pet behind-right, 2 side by side with the smaller on the left, 3 as a V with the
--     biggest behind the right one; a 1.2-stud camera channel keeps the owner's centre line free), at about head
--     height, bob and sway a little with their own phase, ease towards their slot with a looser exponential filter
--     (rateH 4.2 + 0.6 per slot, LEAD_H 0.10), then a 2-pass separation pushes overlapping pets apart (and off the
--     owner) so big pets never touch or fuse; they face the direction the owner travels, bank into turns, pitch
--     forward when they speed up and flap harder when the owner runs or is in the air.
--   PetController.FormationFor(widths) -> { { side, back }, ... }   (pure; slots in the owner's frame, studs)
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
--   * bug batch 2 #7: while the owner sits (Humanoid.Sit / SeatPart: a lobby bench or any seat) the followers settle
--     on the ground in a row about 3 studs in front of the owner (side by side, no overlap), facing them, lying down in
--     HomeFx's nap pose (its LIE_ANGLE roll and SLEEP_ANIM slow wings, copied into SIT), and ease back into the
--     formation when the owner stands up. A battle still parks them first (that check comes before it).
--   * Phase 3: while the owner's player attribute `InBattle` is set (BattleService), the followers are parked: the
--     battle team fights on the floor, drawn by BattleController. They snap back into formation afterwards.
--     Wave 5 (bug #26): in a dungeon InBattle is the RUN id ("D12") for the whole run, so there the followers park
--     only while the attribute InFight is true (DungeonService: a room's fight); in the hall, the corridors, the
--     walk-ins and the treasure they follow. When InFight goes true -> nil they stay parked HANDOVER seconds more
--     (= BattleController's dungeon linger: the fighter model is still drawn), and longer while BattleController still
--     draws the fighter (BattleController.FighterDrawn: a LOST room's KO'd models linger), at most HANDOVER_MAX 5 s;
--     then they reappear and the fighter pet walks back into its slot from where BattleController last drew it
--     (BattleController.LastDrawn(userId)). The name cards show / hide with the followers.
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

-- wave 5 (bug #26): seconds the followers wait after a dungeon fight (= BattleController K.DUNGEON_LINGER)
local HANDOVER = 1.0
PetController.HANDOVER = HANDOVER
-- the hand-over also waits while BattleController still draws the fighter (a LOST room: the KO'd models linger
-- END_LINGER 3.5 s with the result card), but never longer than this after the fight ended
local HANDOVER_MAX = 5.0
PetController.HANDOVER_MAX = HANDOVER_MAX
local ATTR_IN_FIGHT = (Config.Attr and Config.Attr.InFight) or "InFight"

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
local LEAD_H = 0.10 -- seconds of owner velocity added to the target (cancels most of the filter lag)
local LEAD_V = 0.05
local RUN_RISE = 0.6 -- studs the pets rise at full run speed
local FACE_RATE = 7 -- pet yaw easing (1/s)
local TILT_RATE = 9 -- pitch / roll easing (1/s)
local BANK_GAIN = 0.1 -- radians of roll per radian/second of yaw rate
local BANK_MAX = 0.55
local PITCH_GAIN = 0.0125 -- radians of nose-down pitch per stud/second of forward speed

-- Phase 5 formation (contract 3.8, the player's "big pets touch each other; follow without fusing, less attached"):
-- slots come from the measured model widths (PetController.FormationFor), a camera channel keeps every pet off the
-- owner's centre line, and a 2-pass separation after the filter keeps pets apart from each other and the owner.
local F5 = {
	OWNER_R = 1.5, -- the owner as a horizontal circle (studs)
	GAP_OWNER = 2.5, -- studs between the owner circle and the front row
	GAP_PET = 1.0, -- studs between the right-hand pet and the one behind it
	CHANNEL = 1.2, -- no pet within this many studs of the owner's centre line (the camera sees the player)
	DIAG = 0.35, -- the front row tucks in by this share of the smaller half width
	SEP_GAP = 0.4, -- studs the separation keeps between two pets / a pet and the owner
	DEFAULT_W = 3.2, -- width of a pet whose model is not measured yet (the stage-0 median)
	UP = { -- studs above the HumanoidRootPart per slot (n pets): about head height, the back pet a little higher
		[1] = { 2.3 },
		[2] = { 2.0, 2.6 },
		[3] = { 1.9, 2.5, 2.9 },
	},
	RATE_H = 4.2, -- horizontal filter rate of slot 1 (1/s), +RATE_STEP per further slot (looser than Phase 4)
	RATE_STEP = 0.6,
}

-- Phase 4 tuning (cards, evolved models, the portal dive)
local P4K = {
	CARD_HEIGHT = 0.7, -- studs above the top of the pet
	OTHER_CARDS = 12, -- other players' cards at once (nearest first) ...
	OTHER_CARD_DIST = 60, -- ... within this distance (also the cards' MaxDistance)
	OTHER_EVO_MAX = 6, -- other players' evolved models at once (nearest first) ...
	OTHER_EVO_IN = 40, -- ... within this distance
	OTHER_EVO_OUT = 46, -- an evolved model already shown keeps its look up to here (no flicker at the edge)
	EVO_GRACE = 0.6, -- s: a stage that rose without PlayEvolution waits this long (the animation may park it first)
	GLOBAL_TICK = 0.5, -- s between card / evolved-model selections
	DIVE_TIME = 0.4, -- s the followers take to fly into a used home portal
	DIVE_WINDOW = 0.5, -- s: a teleport this close to the portal closing is a portal trip
	DIVE_NEAR = 8, -- studs: an owner this close to an open portal who teleports used it
	PARK_DEFAULT = 4.6, -- s a follower stays parked by PlayEvolution when EvolutionFx cannot say
	OVERRIDE_GRACE = 15, -- s after the park: a PlayEvolution stage State never confirmed is dropped (State wins)
}

-- bug batch 2 #7 (the player: "when a player sits on [a bench] the pets sit on the ground"): the settle-while-sitting
-- tuning and helpers. The pose numbers are HomeFx's nap pose (G.LIE_ANGLE, G.SLEEP_ANIM), copied: HomeFx is not required.
local SIT = {
	AHEAD = 2.2, -- studs from the owner's root to the near edge of a pet (its centre: AHEAD + r, ~3-4 studs)
	GAP = 0.5, -- studs between two pets of the row
	LIE_ANGLE = 1.35, -- HomeFx G.LIE_ANGLE: radians a resting pet rolls onto its side
	ANIM_FLAP = 0.15, -- HomeFx G.SLEEP_ANIM = { Flap = 0.15 }
	RATE_V = 3, -- vertical filter rate while settling down / getting up (1/s; following: 7.5-10)
	TILT_RATE = 3, -- roll / pitch easing while settling down / getting up (1/s; following: TILT_RATE 9)
	EASE_OUT = 2, -- s after the owner stands up that the slower rates still apply
	MAX_SPEED = 14, -- studs/s a pet may glide while settling down / getting up (+ the owner's own speed): no zooming
	REPLAN = 1.5, -- studs the owner may move (a moving seat) before the row is laid out again
	DROP = 14, -- studs searched below the owner for the ground
	FALLBACK_DROP = 3, -- the ground under the owner's root when the ray finds nothing
	params = nil, -- RaycastParams (lazy, reused)
	lows = {}, -- ["key|stage"] = SIT.lieLow of the fresh model (wings / tail at rest, like HomeFx measures it)
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
local meshVerNow = 0 -- Phase 6 (runtime-pets): PetBuilder.MeshVersion() of this frame (a change = some mesh keys usable)
local buildStart = 0 -- os.clock() when the frame's first build started
local movedRigid, movedPivot = 0, 0 -- pets posed in the current frame (root write / PivotTo fallback)
local lastRigid, lastPivot = 0, 0 -- ... in the last finished frame (GetMoveStats)
local nextFolderCheck = 0
local warnedAt = {} -- [key] = os.clock() of the last warning (rate limit)
-- Phase 4: every new helper lives in this table (keeps the file's active locals low)
local P4 = {
	heights = {}, -- ["key|stage"] = measured model height (GetExtentsSize Y, Scale 1)
	widths = {}, -- ["key|stage"] = measured model width (max of GetExtentsSize X / Z, Scale 1; FormationFor)
	overrides = {}, -- [key] = stage passed to PlayEvolution (until State's PetGrowth catches up)
	overrideUntil = {}, -- [key] = os.clock() after which an unconfirmed override is stale (park end + OVERRIDE_GRACE)
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
-- PetController.FormationFor(widths) -> { { side, back }, ... } (pure; contract 3.8): the slot of each pet (same order
-- as `widths`, studs in the owner's frame: side + = right, back = behind the root) from the pets' widths.
--   1 pet:  behind-right { Channel + w/2, OwnerRadius + GapOwner + w/2 - Diag x w/2 }
--   2 pets: the smaller left { -(Channel + wa/2), row }, the other right { Channel + wb/2, row },
--           row = OwnerRadius + GapOwner + max(wa, wb)/2 - Diag x min(wa, wb)/2
--   3 pets: the two smallest as for 2; the biggest behind the right one { Channel + wc/2, row + wb/2 + GapPet + wc/2 }
--   n > 3 (never with a team of 3): the V goes on, every further pet behind the last one of its side
-- Ties keep the input order. Junk widths count as F5.DEFAULT_W.
local function formationFor(widths)
	local out = {}
	if type(widths) ~= "table" then
		return out
	end
	local n = #widths
	if n == 0 then
		return out
	end
	local w = {}
	local order = {}
	for i = 1, n do
		local v = tonumber(widths[i])
		if not v or v ~= v or v <= 0 or v == math.huge then
			v = F5.DEFAULT_W
		end
		w[i] = v
		order[i] = i
	end
	table.sort(order, function(a, b)
		if w[a] ~= w[b] then
			return w[a] < w[b]
		end
		return a < b
	end)
	local C, R, G, D = F5.CHANNEL, F5.OWNER_R, F5.GAP_OWNER, F5.DIAG
	if n == 1 then
		local x = w[1]
		out[1] = { C + x / 2, R + G + x / 2 - D * x / 2 }
		return out
	end
	local a, b = order[1], order[2]
	local wa, wb = w[a], w[b]
	local row = R + G + math.max(wa, wb) / 2 - D * math.min(wa, wb) / 2
	out[a] = { -(C + wa / 2), row }
	out[b] = { C + wb / 2, row }
	-- the rest: behind the last pet of the right side, then the left, and so on (3 pets: the biggest behind the right one)
	local lastR, lastL = { b, row }, { a, row }
	for k = 3, n do
		local c = order[k]
		local wc = w[c]
		local right = (k % 2) == 1
		local last = right and lastR or lastL
		local back = last[2] + w[last[1]] / 2 + F5.GAP_PET + wc / 2
		out[c] = { (right and 1 or -1) * (C + wc / 2), back }
		if right then
			lastR = { c, back }
		else
			lastL = { c, back }
		end
	end
	return out
end

-- the slots of every pet of one follower from their measured widths (unmeasured: F5.DEFAULT_W)
local function assignSlots(f)
	local n = f.n
	local widths = {}
	for i = 1, n do
		widths[i] = f.pets[i].width or F5.DEFAULT_W
	end
	local slots = formationFor(widths)
	local ups = F5.UP[n]
	for i = 1, n do
		local p = f.pets[i]
		local s = slots[i]
		p.slot = i
		p.side, p.back, p.ahead = s[1], s[2], 0
		p.up = (ups and ups[i]) or (1.9 + (i % 3) * 0.5)
		p.r = (p.width or F5.DEFAULT_W) / 2
		p.rateH = F5.RATE_H + F5.RATE_STEP * (i - 1)
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
		width = nil, -- the measured model width (studs, FormationFor); nil until the model is built
		r = F5.DEFAULT_W / 2, -- half the width: the pet's circle for the separation
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
		swayAmp = 0.1 + rnd() * 0.08, -- small: the camera channel and the gaps hold while it sways
		rateH = F5.RATE_H, -- set by assignSlots from the slot
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
	-- the model's height and width, measured once per key|stage: taller pets hover a little higher, the card
	-- floats over the head, and the width decides the pet's slot (FormationFor) and its separation circle
	local hkey = tostring(p.key) .. "|" .. stage
	local h, wd = P4.heights[hkey], P4.widths[hkey]
	if not h or not wd then
		local okSize, size = pcall(model.GetExtentsSize, model)
		if okSize and typeof(size) == "Vector3" then
			h = size.Y
			wd = math.max(size.X, size.Z)
			P4.heights[hkey] = h
			P4.widths[hkey] = wd
		end
	end
	h = h or 2.7
	p.height = h
	-- bug batch 2 #7: the lying low point, measured on the fresh model (wings / tail at rest), once per key|stage
	local lo = SIT.lows[hkey]
	if lo == nil then
		lo = SIT.lieLow(model)
		SIT.lows[hkey] = lo
	end
	p.lieLo, p.lieModel = lo, model
	p.lift = clamp((h - 2.7) * 0.35, -0.4, 0.6)
	wd = wd or F5.DEFAULT_W
	if p.width ~= wd then
		p.width = wd
		assignSlots(f) -- a new width moves every slot of this follower (the filter eases the pets there)
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
		-- bug batch 2 #7: the owner's Humanoid and the sitting row (SIT)
		hum = nil,
		sitPlanned = false,
		sitPx = 0,
		sitPy = 0,
		sitPz = 0,
		sitFx = 0,
		sitFz = -1,
		sitUntil = 0,
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
	f.hum = nil
	f.sitPlanned = false
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
	-- wave 5 (bug #26): a dungeon fight ended (InFight true -> nil): the hand-over (the fighter model goes first)
	f.inFight = player:GetAttribute(ATTR_IN_FIGHT) == true
	conns[#conns + 1] = player:GetAttributeChangedSignal(ATTR_IN_FIGHT):Connect(function()
		local on = player:GetAttribute(ATTR_IN_FIGHT) == true
		if f.inFight and not on then
			f.handoverUntil = os.clock() + HANDOVER
			f.handoverCap = os.clock() + HANDOVER_MAX
		elseif on then
			f.handoverUntil = nil
			f.handoverCap = nil
		end
		f.inFight = on
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

-- the stored evolution stage of an own pet (State), never below a stage PlayEvolution announced while that stage is
-- fresh (the park + P4K.OVERRIDE_GRACE): an override State never confirmed is dropped then (State wins)
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
		-- State caught up, or never did long after the animation (a /reset, a pet that came back fresh): State wins
		local untilAt = P4.overrideUntil[p.key]
		local stale = untilAt ~= nil and os.clock() > untilAt and P4.parks[p.key] == nil
		if stored >= over or stale then
			P4.overrides[p.key] = nil
			P4.overrideUntil[p.key] = nil
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
-- Wave 5 (bug #26): the dungeon hand-over
----------------------------------------------------------------------
-- a dungeon run id ("D12"), not a battle id ("B7"; BattleService.Enc.isRunId)
function P4.isRunId(v)
	return type(v) == "string" and v:sub(1, 1) == "D"
end

-- true = the follower is parked now: InBattle set, unless it is a dungeon run id with no fight on (InFight) and no
-- hand-over running; the hand-over's end shows the follower again (P4.emerge)
function P4.parkWanted(f)
	local inBattle = f.player:GetAttribute("InBattle")
	if inBattle ~= nil and (f.player:GetAttribute(ATTR_IN_FIGHT) == true or not P4.isRunId(inBattle)) then
		return true
	end
	if f.handoverUntil then
		local now = os.clock()
		if now < f.handoverUntil or (now < (f.handoverCap or 0) and P4.fighterDrawn(f)) then
			return true
		end
		f.handoverUntil = nil
		f.handoverCap = nil
		if not f.visible then
			setVisible(f, true)
			P4.emerge(f)
		end
	end
	return false
end

-- BattleController still draws this player's dungeon fighter (a lost room's KO'd models linger)
function P4.fighterDrawn(f)
	if P4.BC == nil then
		P4.BC = optionalModule(script.Parent, "BattleController") or false
	end
	local BC = P4.BC
	if not BC or type(BC.FighterDrawn) ~= "function" then
		return false
	end
	local ok, drawn = pcall(BC.FighterDrawn, f.userId)
	return ok and drawn == true
end

-- the followers reappear after a dungeon fight: the fighter pet starts where BattleController last drew it
function P4.emerge(f)
	if P4.BC == nil then
		P4.BC = optionalModule(script.Parent, "BattleController") or false
	end
	local BC = P4.BC
	if not BC or type(BC.LastDrawn) ~= "function" then
		return
	end
	local ok, pos, key = pcall(BC.LastDrawn, f.userId)
	if not ok or typeof(pos) ~= "Vector3" then
		return
	end
	local target = nil
	for i = 1, f.n do
		local p = f.pets[i]
		if key ~= nil and p.key == key then
			target = p
			break
		end
	end
	target = target or f.pets[1]
	if target then
		target.emergeFrom = pos
	end
end

----------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------
-- Advances one follower by dt seconds. `viewPos` is where the viewer is (Vector3 or nil).
----------------------------------------------------------------------
-- bug batch 2 #7: settle while the owner sits (SIT)
----------------------------------------------------------------------
-- the owner sits on any seat (Humanoid.Sit, or a SeatPart: both replicate)
function SIT.isSitting(f)
	local hum = f.hum
	if not hum or hum.Parent ~= f.char then
		hum = f.char and f.char:FindFirstChildOfClass("Humanoid") or nil
		f.hum = hum
	end
	return hum ~= nil and (hum.Sit == true or hum.SeatPart ~= nil)
end

-- lays the row out across the owner's front (once per sit, again when the owner moved REPLAN studs): every pet gets
-- its lateral offset; its ground spot is found on its next update (SIT.place)
function SIT.plan(f, root, px, py, pz)
	local look = root.CFrame.LookVector
	local lx, lz = look.X, look.Z
	local m = sqrt(lx * lx + lz * lz)
	if m < 1e-3 then
		lx, lz, m = -sin(f.headYaw), -cos(f.headYaw), 1
	end
	f.sitFx, f.sitFz = lx / m, lz / m
	f.sitPx, f.sitPy, f.sitPz = px, py, pz
	local n = f.n
	local total = SIT.GAP * math.max(0, n - 1)
	for i = 1, n do
		total = total + 2 * f.pets[i].r
	end
	local cursor = -total / 2
	for i = 1, n do
		local p = f.pets[i]
		p.sitLat = cursor + p.r
		cursor = cursor + 2 * p.r + SIT.GAP
		p.sitModel = nil
	end
	f.sitPlanned = true
end

-- the lowest point of `model` below its pivot once it lies rolled SIT.LIE_ANGLE about its forward axis (HomeFx's
-- LieLo, with every part's own rotation): the corners' y after Rz(LIE_ANGLE) is x sin + y cos. The body only: the
-- wing / tail parts that Animate moves are left out (the body rests on the ground, the lower wing folds into it)
function SIT.lieLow(model)
	local okPivot, pivot = pcall(model.GetPivot, model)
	if not okPivot then
		return -1
	end
	local inv = pivot:Inverse()
	local ls, lc = sin(SIT.LIE_ANGLE), cos(SIT.LIE_ANGLE)
	local lo = nil
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 and not isAnimatedPart(part) then
			local rel = inv * part.CFrame
			local c, s = rel.Position, part.Size
			local ax, ay, az = rel.RightVector, rel.UpVector, rel.LookVector
			local y = c.X * ls + c.Y * lc - (abs(ax.X * ls + ax.Y * lc) * s.X + abs(ay.X * ls + ay.Y * lc) * s.Y + abs(az.X * ls + az.Y * lc) * s.Z) / 2
			if not lo or y < lo then
				lo = y
			end
		end
	end
	return lo or -1
end

-- the pet's spot in the row: the ground under it (a ray, the owner and every pet excluded) and the lying height
function SIT.place(f, p, model)
	local fx, fz = f.sitFx, f.sitFz
	local ahead = SIT.AHEAD + p.r
	local lat = p.sitLat or 0
	local x = f.sitPx + fx * ahead - fz * lat -- the owner's right = (-fz, fx)
	local z = f.sitPz + fz * ahead + fx * lat
	local ground = f.sitPy - SIT.FALLBACK_DROP
	local params = SIT.params
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		SIT.params = params
	end
	params.FilterDescendantsInstances = { f.char, petsFolder }
	local ok, hit = pcall(workspace.Raycast, workspace, Vector3.new(x, f.sitPy + 1, z), Vector3.new(0, -SIT.DROP, 0), params)
	if ok and hit then
		ground = hit.Position.Y
	end
	if p.lieModel ~= model then
		p.lieLo = SIT.lieLow(model)
		p.lieModel = model
	end
	p.sitX, p.sitY, p.sitZ = x, ground - p.lieLo + 0.05, z
	p.sitYaw = atan2(fx, fz) -- forward (-sin, -cos) = towards the owner
	p.sitModel = model
end

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
	-- Phase 3: the team fights (BattleController draws it): park the followers. Wave 5 (bug #26): a dungeon run id
	-- parks only during a room's fight (InFight) and the hand-over after it (P4.parkWanted)
	if P4.parkWanted(f) then
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

	-- 4b. bug batch 2 #7: the owner sits -> the pets settle on the ground in front of them (SIT)
	local sitting = SIT.isSitting(f)
	if sitting then
		local mx, my, mz = px - f.sitPx, py - f.sitPy, pz - f.sitPz
		if not f.sitPlanned or mx * mx + my * my + mz * mz > SIT.REPLAN * SIT.REPLAN then
			SIT.plan(f, root, px, py, pz)
		end
		f.sitUntil = now + SIT.EASE_OUT
	elseif f.sitPlanned then
		f.sitPlanned = false
	end
	local settling = now < f.sitUntil

	-- 5. pets: (a) build + the filter toward the slot, (b) the separation, (c) facing + the pose write --------
	local pets = f.pets
	local n = f.n
	for i = 1, n do
		local p = pets[i]
		local model = p.model
		p.live = false
		-- Phase 6 (runtime-pets): a Part-built pet whose Blender mesh keys became usable here is rebuilt as a mesh pet
		if model and p.meshVer ~= meshVerNow then
			p.meshVer = meshVerNow
			if not p.rebuildAt and PetBuilder.NeedsMeshRebuild and PetBuilder.NeedsMeshRebuild(model) then
				p.rebuildAt = now
			end
		end
		-- review3 runtime-4: the old model goes only when this frame still has a build slot for its replacement (the same
		-- gate as the build below), so a MeshVersion change that marks every pet in the lobby keeps each one on screen
		-- until its turn comes (no lobby-wide blink; at most BUILD_MAX swaps per frame, built in the same frame)
		if p.rebuildAt and now >= p.rebuildAt and not p.parked and now >= p.retryAt and buildsThisFrame < BUILD_MAX
			and (buildsThisFrame == 0 or os.clock() - buildStart < BUILD_BUDGET) then
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
			local fwd = -p.back * compact
			local tx = px + rx * side + fx * fwd + leadX
			local tz = pz + rz * side + fz * fwd + leadZ
			local ty = py + p.up * (1 - 0.2 * downK) + p.lift + bob + 1.2 * RUN_RISE * runK + leadY
			if sitting then
				if p.sitModel ~= model then
					SIT.place(f, p, model)
				end
				tx, ty, tz = p.sitX, p.sitY, p.sitZ
			end

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
			local kvv = 1 - exp(-(settling and SIT.RATE_V or p.rateV) * dt)
			if settling then
				-- bug batch 2 #7: glide to / from the ground spot instead of zooming across (the filter alone starts at
				-- ~80 studs/s over the ~16 studs from a back slot to the front row)
				local cap = (SIT.MAX_SPEED + hs) * dt
				local mh = sqrt(ex * ex + ez * ez) * kh
				if mh > cap then
					kh = kh * cap / mh
				end
			end
			p.x, p.y, p.z = ox + ex * kh, oy + ey * kvv, oz + ez * kh
			p.lastX, p.lastZ = ox, oz
			p.live = true
		end
	end

	-- (b) Phase 5 separation (contract 3.8): 2 passes over the pets of this owner (n <= 3, so <= 3 pairs); two
	-- overlapping circles (centre distance < ra + rb + gap) are pushed apart half each, then a pet inside the
	-- owner's circle (OwnerRadius + r + gap) is put on it. Horizontal only; no tables, no allocations.
	local gap = F5.SEP_GAP
	for _ = 1, 2 do
		for i = 1, n - 1 do
			local a = pets[i]
			if a.live then
				for j = i + 1, n do
					local b = pets[j]
					if b.live then
						local ddx, ddz = b.x - a.x, b.z - a.z
						local d = sqrt(ddx * ddx + ddz * ddz)
						local need = a.r + b.r + gap
						if d < need then
							local ux, uz
							if d > 1e-4 then
								ux, uz = ddx / d, ddz / d
							else
								ux, uz = rx, rz -- exactly on top of each other: apart along the owner's right
							end
							local push = (need - d) / 2
							a.x, a.z = a.x - ux * push, a.z - uz * push
							b.x, b.z = b.x + ux * push, b.z + uz * push
						end
					end
				end
			end
		end
		for i = 1, n do
			local q = pets[i]
			if q.live then
				local ddx, ddz = q.x - px, q.z - pz
				local d = sqrt(ddx * ddx + ddz * ddz)
				local need = F5.OWNER_R + q.r + gap
				if d < need then
					if d > 1e-4 then
						q.x, q.z = px + ddx / d * need, pz + ddz / d * need
					else
						q.x, q.z = px - fx * need, pz - fz * need -- on the owner: straight behind
					end
				end
			end
		end
	end

	-- (c) facing, banking, pitch and the one pose write per pet
	for i = 1, n do
		local p = pets[i]
		local model = p.model
		if p.live and model then
			local nx, ny, nz = p.x, p.y, p.z
			local pvx, pvz = (nx - p.lastX) / dt, (nz - p.lastZ) / dt

			local yawOld = p.yaw
			local wobble = 0.1 * sin(now * 0.9 + p.phase2)
			local aim = face + p.yawBias + wobble
			if sitting and p.sitModel == model then
				aim = p.sitYaw + p.yawBias -- lying in front of the owner, looking at them
			end
			local yawStep = wrapAngle(aim - yawOld) * (1 - exp(-FACE_RATE * dt))
			local yaw = wrapAngle(yawOld + yawStep)
			p.yaw = yaw
			local syw, cyw = sin(yaw), cos(yaw)
			local forwardSpeed = -pvx * syw - pvz * cyw
			local lateralSpeed = pvx * cyw - pvz * syw
			local pitchT = -clamp(forwardSpeed * PITCH_GAIN, -0.28, 0.42)
			local rollT = clamp(yawStep / dt * BANK_GAIN, -BANK_MAX, BANK_MAX)
				- clamp(lateralSpeed * 0.015, -0.3, 0.3)
				+ 0.05 * sin(now * 1.3 + p.phase)
			if sitting then
				pitchT, rollT = 0, SIT.LIE_ANGLE -- HomeFx's nap pose: rolled onto the side
			end
			local kt = 1 - exp(-(settling and SIT.TILT_RATE or TILT_RATE) * dt)
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
					o.Flap = sitting and SIT.ANIM_FLAP or flapBase * p.flapVar
					o.Excited = sitting and 0 or excited
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
	meshVerNow = PetBuilder.MeshVersion and PetBuilder.MeshVersion() or 0
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
-- the formation slots for pets of these widths (pure; contract 3.8; see formationFor)
function PetController.FormationFor(widths)
	return formationFor(widths)
end

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
	P4.overrideUntil[key] = os.clock() + seconds + P4K.OVERRIDE_GRACE
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
			Card = p.card and p.card.Gui or nil, Parked = p.parked, Diving = f.dive, Back = p.back,
			Side = p.side, Width = p.width, Slot = p.slot,
			Sitting = f.sitPlanned and p.model ~= nil and p.sitModel == p.model,
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
	P4.overrideUntil = {}
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
