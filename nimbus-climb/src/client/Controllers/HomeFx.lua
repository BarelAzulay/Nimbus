-- HomeFx (client, Phase 2 homeworld + Phase 4 "pets make the money"): brings the tycoon homes that
-- server/Services/HomeBuilder builds to life on THIS client only (ARCHITECTURE_V3.md "Phase 4 build contract" 3.1-3.3,
-- 3.7, 3.9, 6; Replication rule: the server never animates and creates no Instance per coin).
--
--   HomeFx.Init()
--   HomeFx.Count() -> number of home plots tracked
--   HomeFx.Stats() -> { Homes, Near, Stations, Plants, Pops, HiddenPrompts, HiddenSigns, SignsShown, SignsCrowded,
--                       SignsUnderHud, SignsAway, GardenPets, TrainingPets (GymPets: the same), Sleeping, Props, Heaps,
--                       HeapParts, HeapsMade, Bowls, Coins, CoinPool, Fruit, FruitPool, FruitFlights, Drops, Zips,
--                       Labels, LastLabel, LastLabelAt, Hint, Ring, Cards, PetBuilds, PetColdBuilds, PetPoolHits,
--                       PetPool, PetFrameMost }   (Coins / Fruit: flying now, CoinPool / FruitPool: parts ever made;
--                       Drops / Zips / Labels: coins popped by eating pets, scooped piles, "+$" labels so far;
--                       Pet*: models built / first-time builds / taken from the pool, models waiting in the pool now,
--                       the most garden / training pets placed in one frame)
--   HomeFx.Garden(plotOrHomeFolder) -> { Heaps = { [slot | "W"] = { Model, Point, Stage, Dim, Lucky, Parts } },
--                       Bowls, Pets = { [slot] = { Key, Model, Sleep, Zzz, Card, Stage, Seat } }, Training =
--                       { [mat] = { Key, Model, Stat, Prop, Card, Seat } }, Open, Dim, Radius }   (tests / debugging)
--   HomeFx.SignState(padSign) -> "Shown" | "Crowded" | "Away" | "Pending" | "Locked" | "Other" | nil (see SignState)
--
-- Every Folder tagged "NC_Home" (HomeBuilder's per-plot `Home` folder; the plot folder above it carries TycoonService's
-- attributes GardenPets, GardenInfo, GardenSlots, CoinPiles, CollectorCash and PetCareService's TrainingPets) gets:
--   * a voxel pop-in when a `Station_*` (or a buy pad `Pad_*`) appears while the game runs: its blocks spring up from
--     the ground bottom-to-top in under a second, then everything is put back exactly where the server built it
--   * the Pet Garden (contract 3.2 / 3.3): the pets of GardenPets on their cushions (Spot<n>), each looking at a food
--     bowl (2 client parts per open place, toward its pile); twice per meal (TycoonCatalog.Coins.MealSeconds) an eating
--     pet dips into the bowl, a rainbow coin pops out and hops onto its pile, the pet wiggles. The piles are heaps of
--     rainbow coins at TycoonCatalog.CoinPoint(n) (the Welcome-back pile "W" at Garden.Slot.WelcomePile) that follow
--     CoinPiles: heap stage 1-5 (<= 35 parts, the Welcome-back heap <= 53), '*' a turning golden Lucky star, 'F' = the
--     pet naps (lies down, a voxel "Zzz"); a pet on a place above GardenSlots sleeps on its closed bed. Another
--     player's heaps are dimmed and never move. Fruit of every built plant (FruitPoint / FruitColor) flies into a
--     bowl every ~3 s, the Food Machine drops one from its chute (ChuteMouth -> Tray), the Coin Magnet's head
--     (MagnetHead about MagnetCenter) turns.
--   * the scoop (only the owner's coins are ever collectable): when the local player's own piles vanish from
--     CoinPiles while they stand within the Magnet's radius (TycoonCatalog.ScoopRadius), coins zip from each pile to
--     them, and when the bank (CollectorCash) dropped and their Cash rose in the same moment, a "+$1,234" pixel label
--     floats up AT THE PILE (never over the player's head: in third person that is the screen centre). A faint ring
--     of the scoop radius follows the owner while they stand in their garden. A visitor next to another player's pile
--     sees the hint "Only the owner can pick these up" once (at the pile).
--   * the Training Place (3.7): the pets of TrainingPets ("mat=key:Stat:Ends") on their mats (Spot<mat>), each with a
--     pooled voxel prop of its skill (Speed: treadmill, Physique: dumbbell, Ability: orb, Defense: shield dummy;
--     <= 8 parts) and a pose (running, lifting, floating, bumping the dummy).
--   * pet cards (3.9, client/UI/PetCard): own garden pets "Lv n" + XP (+ the EVOLVE! pill, which opens the Pets
--     panel), own training pets + the purple timer "2:10", other players' garden pets the level only (GardenInfo);
--     only pets within K.CARD_NEAR studs of the local player carry one; values written only on change.
--   * owner-only prompts: every ProximityPrompt inside a home that is not the local player's (BuyPrompt,
--     GardenSpotPrompt, FusionPrompt, ... by their OwnerUserId attribute, else the home's) is disabled locally, and the
--     pad signs (`PadSign`) of other players' pads are hidden; the "Claim Home" prompts of other plots are disabled
--     while the local player owns a home (one home per player). The server still checks everything. The signs of
--     the player's own LOCKED pads (their lock reason) only show within K.LOCKED_SIGN_NEAR studs, so the yard is not
--     a field of lock signs: from afar it shows what can be bought now, like a classic tycoon.
--   * readable pad signs (World text rule): the pad signs are pixel-sized billboards, so from the gate path a full
--     yard used to stack them into a pile nobody could read (worse on phones). Every K.SIGN_CHECK the local player's
--     own signs are laid out on the screen: projected through the camera (Camera:WorldToViewportPoint of the
--     adornee + studs offsets, plate size from the sign's Plate), taken nearest-to-the-player first (lock reasons
--     after what can be bought now, unless the player stands at that pad), and a sign whose plate would reach into
--     the text of a sign already shown is hidden ("Crowded") until there is room for it again; signs Roblox does not
--     draw or that are mostly off the screen take no room. The HUD is drawn OVER every billboard, so where this
--     game's own HUD covers the screen (the menu column, the currency pills and the rest of NimbusHud, the hotbar,
--     the touch buttons, the tutorial card) counts as signs already shown: a sign that would land under it is hidden
--     the same way and its room goes to another sign (measured every K.SIGN_HUD_CHECK seconds and when the screen
--     size changes, see measureHud). The pads keep their glow and pulse. A sign the layout has
--     not placed yet starts hidden (one frame), a rebuilt sign keeps its pad's last answer, and hysteresis
--     (K.SIGN_CLEAR px, K.SIGN_KEEP studs, K.SIGN_HOLD seconds) keeps signs from flickering while the camera moves.
--   * the local player's own pads glow when the Cash attribute can pay their Price and dim (price in red) when not.
-- Budgets (contract 6): pets, heaps, bowls, props and cards only for homes within K.PET_NEAR studs of the camera;
-- the 12 garden + 5 training pets of a home are built under a per-frame budget like every other pet builder (at most
-- K.PET_BUILD_MAX per frame and only while the frame has spent under K.PET_BUILD_BUDGET seconds building; a
-- first-time build alone in its frame); pets that leave wait unparented in a small pool (K.PET_POOL) for the way back;
-- heaps are clones of one template per look (at most K.HEAP_BUILD_MAX a frame) and pooled; flying coins (<= 40) and
-- fruit (<= 24) are pooled parts; poses are written at most 20 times a second and only when they changed.
-- Cheap: one RenderStepped connection; homes farther than K.NEAR studs from the camera are frozen; no collisions,
-- queries, touches or shadows on anything HomeFx makes. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local function optionalShared(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local TycoonCatalog = optionalShared("TycoonCatalog")
local Util = optionalShared("Util")
local PetBuilder = optionalShared("PetBuilder")
local PetKeys = optionalShared("PetKeys")
local PetCatalog = optionalShared("PetCatalog")
local Theme = optionalShared("Theme")

local HomeFx = {}

local HOME_TAG = "NC_Home"
local CASH_ATTR = (Config.Attr and Config.Attr.Cash) or "Cash"

local K = {
	NEAR = 230, -- studs from the camera: homes farther away are frozen (no coins, fruit, swirls)
	NEAR_CHECK = 0.5, -- seconds between distance checks
	POP_WINDOW = 6, -- a station whose BuiltAt is younger than this pops in
	POP_LIVE_AFTER = 1.5, -- children without BuiltAt pop when they arrive this long after the home was found
	POP_PART = 0.3, -- one block's spring
	POP_SPREAD = 0.6, -- bottom-to-top spread of one model's blocks
	POP_STAGGER = 0.1, -- between models that appear together (a claim rebuilds a whole home)
	POP_LIFT = 1.2, -- studs a block rises while it pops
	MAX_POP_PARTS = 3000, -- blocks animated at once (anything beyond simply appears)
	GLOW_RATE = 2.2, -- radians per second of the breathing glow
	GLOW_SWING = 0.3, -- transparency swing of a breathing glow
	SWIRL_SPEED = 1.4, -- radians per second of the Fusion Machine's swirl
	SWIRL_BOB = 0.25,
	PAD_PULSE = 3.2,
	PAD_DIM = 0.6, -- glow transparency of a pad the local player cannot pay for yet
	LOCKED_SIGN_NEAR = 30, -- studs: the sign of one of the local player's LOCKED pads (its lock reason) shows only
	LOCKED_SIGN_FAR = 34, -- this close (hidden again beyond FAR), so from afar the yard shows what can be bought now
	SIGN_CHECK = 0.1, -- seconds between two sign passes (those distance checks + the on-screen layout)
	SIGN_INSET_X = 8, -- px two plates may overlap side by side (only padding: HomeBuilder pads the text 14 px)...
	SIGN_INSET_Y = 2, -- ...and above / below each other (6 px top padding, 8 px bottom, a 3.5 px edge)
	SIGN_CLEAR = 6, -- px of extra room a hidden sign needs before it comes back (no flicker at the edge)
	SIGN_KEEP = 4, -- studs: a shown sign keeps its place unless a hidden one is this much nearer the player
	SIGN_HOLD = 0.35, -- seconds: a sign the layout hid stays hidden at least this long, one it showed stays (unless
	--                   it would overlap a sign shown just as recently): no flashes while the player walks
	SIGN_LOCKED_BACK = 15, -- studs: a locked pad's sign (its lock reason) yields to the pads that can be bought now...
	SIGN_LOCKED_CLOSE = 8, -- ...except up close (no penalty this near, the full one from twice as far): standing at a
	--                        locked pad shows why it is locked (its prompt is off, the sign is the only place to read it)
	SIGN_RANGE_SLACK = 2, -- studs past a sign's MaxDistance it still counts as drawn (Roblox measures to the adornee)
	SIGN_ONSCREEN = 0.85, -- share of a plate inside the screen to keep showing it (a cut-off plate reads as nothing)...
	SIGN_ONSCREEN_BACK = 0.95, -- ...and to show it again
	SIGN_HUD_GAP = 6, -- px kept between a plate and the HUD (the plate's 3.5 px outline, the HUD's strokes and coins)
	SIGN_HUD_CLEAR = 24, -- px at 1080p (scaled with the screen height): a sign hidden next to the HUD comes back only
	--                      this much farther from it. Signs move together, but against the HUD a sign moves as much
	--                      as the camera turns (0.5 degrees = ~7 px at 1080p), so K.SIGN_CLEAR is not enough there
	SIGN_HUD_CHECK = 1, -- seconds between two measurements of where the HUD is (not every pass: it rarely moves)...
	SIGN_HUD_SETTLE = 0.25, -- ...and after a screen size change, once more this soon (the HUD lays itself out again)
	PET_NEAR = 110, -- garden / training pets, heaps, bowls and props are shown for homes this close (hysteresis +20)
	PET_SCALE = 0.85,
	PET_ANIM_STEP = 0.125, -- seconds between two PetBuilder.Animate calls of the garden / training pets
	PET_ANIM_NEAR = 80, -- ...only this close (also the eating dips, the coins they pop out and the props' motion)
	PET_HOVER = 0.08, -- studs between a pet's lowest block and its cushion
	MAX_GARDEN_SLOTS = 12, -- the Pet Garden's places (contract 3.3)
	MAX_TRAIN_SLOTS = 5, -- the Training Place's mats (contract 3.7)
	PET_BUILD_MAX = 3, -- garden / training pet models built (or taken from the pool) in one frame at most...
	PET_BUILD_BUDGET = 0.004, -- ...and only while the frame has spent less than this building (the first always runs)
	PET_POOL = 20, -- pet models of homes gone out of range kept for the way back (oldest destroyed first)
	EVO_MAX = 6, -- evolved garden models of the local player's own home at most (the rest: the plain look + stars)
	MOTION_STEP = 0.05, -- seconds between two pose writes of a dipping / training pet (20 Hz, never per frame)
	MEAL = 8, -- seconds of one meal (TycoonCatalog.Coins.MealSeconds wins)
	DIP_START = 6.2, -- phase of the meal when the pet dips into its bowl (twice, DIP_TIME seconds)...
	DIP_TIME = 1.1,
	POP_AT = 7.35, -- ...a coin pops out onto the pile...
	WIGGLE_TIME = 0.45, -- ...and the pet wiggles
	COIN_FLIGHT = 0.55, -- seconds of a coin's hop from the pet onto its pile
	MAX_COINS = 40, -- flying coins alive at once over all homes (pooled parts)
	ZIP_COINS = 8, -- coins that zip from one scooped pile to the owner
	ZIP_TIME = 0.42,
	MAX_FRUIT = 24, -- flying fruit alive at once (pooled parts)
	FRUIT_EVERY = 3, -- seconds (+-0.5) between two fruits of one plant
	MACHINE_EVERY = 4, -- seconds between two fruits out of the Food Machine's chute
	HEAP_BUILD_MAX = 2, -- heaps cloned in one frame at most (the rest the next frames)
	HEAP_POOL = 6, -- idle heap models kept per look
	CARD_NEAR = 40, -- studs: garden / training pets this close to the local player carry a PetCard (hysteresis +6)
	CARD_CHECK = 0.5, -- seconds between two card passes (the timers tick in whole seconds)
	LABEL_TIME = 1.5, -- seconds the "+$1,234" label floats above a scooped pile
	MAX_LABELS = 3,
	LABEL_PAIR = 0.5, -- seconds: a CollectorCash drop and the piles that vanished belong to one scoop
	HINT_NEAR = 4.5, -- studs from another player's pile: the one-time hint "Only the owner can pick these up"
	HINT_TIME = 3.5,
	RING_SEGMENTS = 16, -- the owner's scoop ring (the Coin Magnet's radius) while standing in the garden
	MAGNET_SPIN = 1.1, -- radians per second of the Coin Magnet's head (x3 for a moment after a scoop)
}

local COLORS = {
	PriceOk = Color3.fromRGB(170, 244, 140),
	PriceShort = Color3.fromRGB(255, 132, 120),
	Gold = Color3.fromRGB(255, 206, 84),
	GoldDark = Color3.fromRGB(214, 150, 46),
	Grass = Color3.fromRGB(150, 214, 104), -- the food in the bowls before any plant is built
	Ring = Color3.fromRGB(150, 236, 255),
	Zzz = Color3.fromRGB(236, 240, 255),
	ZzzEdge = Color3.fromRGB(120, 132, 200),
	Coins = { -- the rainbow coins
		Color3.fromRGB(255, 104, 120),
		Color3.fromRGB(255, 164, 72),
		Color3.fromRGB(255, 218, 74),
		Color3.fromRGB(112, 216, 120),
		Color3.fromRGB(92, 172, 255),
		Color3.fromRGB(178, 124, 255),
	},
	Bowls = { Color3.fromRGB(246, 140, 170), Color3.fromRGB(120, 190, 246), Color3.fromRGB(250, 214, 110) },
}

local localPlayer = Players.LocalPlayer
local localUid = 0
local homes = {} -- [folder] = rec
local homeList = {} -- array of recs (iteration order)
local pops = {} -- array of pop records
local popParts = 0
local fxFolder = nil
local petFolder = nil
local petLows = {} -- [key|scale|stage] = height of the pet's lowest block under its pivot (studs), or false (cannot build)
local petDims = {} -- [key|scale|stage] = { Hw = half width, Hi = top above the pivot } (studs)
-- the stations whose pets HomeFx shows, by Kind: the plot attribute that lists them, how lively they look, how big
local PET_STATIONS = {
	Garden = { Attr = "GardenPets", Anim = { Flap = 0.6 }, Scale = 1, Slots = K.MAX_GARDEN_SLOTS }, -- 5 studs apart
	Training = { Attr = "TrainingPets", Anim = { Flap = 1.4, Excited = 1 }, Scale = 0.85, Slots = K.MAX_TRAIN_SLOTS }, -- 3 studs apart
}
local overrides = setmetatable({}, { __mode = "k" }) -- [ProximityPrompt] = state
local signs = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = home rec
local signNear = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = true while a locked pad's sign is close enough
local signLayout = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = the on-screen layout's answer (layoutSigns)
local signSince = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = clock when that answer last changed
local signState = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = why it shows or not (HomeFx.SignState)
local signKeys = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = the StationId of its pad
local plateSizes = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = Vector2, its plate's last laid-out size (px)
local signUnderHud = setmetatable({}, { __mode = "k" }) -- [BillboardGui] = true while the HUD covers its place
local signFocus = nil -- where the local player is (character, else camera), refreshed every K.SIGN_CHECK
local nextSignCheck = 0
local hudRects = {} -- where the HUD covers the screen (viewport px, grown by K.SIGN_HUD_GAP), see hudObstacles
local hudNext = 0 -- clock of the next HUD measurement
local hudViewX, hudViewY = 0, 0 -- the viewport size it was measured at
local hudWarned = false
local petPool = {} -- pet models put away (Parent = nil), oldest first: { Key = "<key>|<scale>|<stage>", Model, Lo }
local petFrameBuilds = 0 -- pet models built or taken from the pool in this frame (a first-time sculpt counts as full)
local petFramePlaced = 0 -- pet models really placed in this frame
local petFrameStart = 0 -- os.clock() when this frame's first one started
local petStats = { Builds = 0, Cold = 0, PoolHits = 0, FrameMost = 0 }
local clock = 0
local nextPopStart = 0
local loopConn = nil
local initialized = false
local frameWarned = false
local ownsHome = false

-- the garden / training helpers and their pools (one table keeps the file under the locals limit), see "Garden"
local G = {
	coinPool = {}, -- idle flying coin parts
	coinsAlive = 0,
	coinsMade = 0,
	fruitPool = {}, -- idle fruit parts
	fruitAlive = 0,
	fruitMade = 0,
	flying = {}, -- { Part, Rec, A, B, T, Dur, Arc, Pool = "coin" | "fruit", Spin }
	heapTpl = {}, -- [look] = template model (built once, cloned)
	heapPool = {}, -- [look] = { idle models }
	heapsMade = 0,
	heapFrame = 0, -- heaps cloned in this frame
	sparkPool = {}, -- idle Lucky sparkles (2 parts)
	zzzPool = {}, -- idle "Zzz" (2 voxel letters, 6 parts)
	bowlPool = {}, -- idle bowls { Dish, Food }
	propPool = {}, -- [stat] = { idle training props }
	labels = {}, -- live "+$" labels { Anchor, Gui, Text, T, From }
	labelPool = {},
	ring = nil, -- the owner's scoop ring parts
	ringShown = false,
	hinted = false, -- the one-time "Only the owner can pick these up" hint was shown
	nextCards = 0,
	cardCount = 0,
	stats = { Drops = 0, Zips = 0, Fruit = 0, Labels = 0, LastLabel = nil, LastLabelAt = nil, Hint = nil },
	PetCard = nil, -- client/UI/PetCard (lazy)
	State = nil, -- client/State (lazy)
	Menu = nil, -- MenuController (lazy, for the EVOLVE! pill)
}

local floor, max, min, abs, sin, pi = math.floor, math.max, math.min, math.abs, math.sin, math.pi

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function serverNow()
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local function commas(n)
	if Util and type(Util.Commas) == "function" then
		local ok, s = pcall(Util.Commas, n)
		if ok and type(s) == "string" then
			return s
		end
	end
	local s = tostring(floor(n))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return out
end

local function formatCash(n)
	n = tonumber(n) or 0
	if n ~= n then
		n = 0
	end
	if TycoonCatalog and type(TycoonCatalog.FormatCash) == "function" then
		local ok, s = pcall(TycoonCatalog.FormatCash, n)
		if ok and type(s) == "string" then
			return s
		end
	end
	return "$" .. commas(max(0, floor(n)))
end

local function vecAttr(inst, name)
	local v = inst and inst:GetAttribute(name)
	if typeof(v) == "Vector3" then
		return v
	end
	return nil
end

local function numAttr(inst, name, default)
	local v = inst and tonumber(inst:GetAttribute(name))
	if v == nil or v ~= v then
		return default
	end
	return v
end

local function ensureFolder()
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local root = Workspace:FindFirstChild("ClientFx")
	if not root then
		root = Instance.new("Folder")
		root.Name = "ClientFx"
		root.Parent = Workspace
	end
	local f = root:FindFirstChild("HomeFx")
	if not f then
		f = Instance.new("Folder")
		f.Name = "HomeFx"
		f.Parent = root
	end
	fxFolder = f
	return f
end

local function ensurePetFolder()
	if petFolder and petFolder.Parent then
		return petFolder
	end
	local root = ensureFolder().Parent
	local f = root:FindFirstChild("HomePets")
	if not f then
		f = Instance.new("Folder")
		f.Name = "HomePets"
		f.Parent = root
	end
	petFolder = f
	return f
end

local function collectParts(model, out)
	out = out or {}
	if model:IsA("BasePart") then
		out[#out + 1] = model
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

-- the nearest ancestor (or self) that carries `attr`
local function ancestorWith(inst, attr, stop)
	local node = inst
	for _ = 1, 8 do
		if not node or node == stop then
			return nil
		end
		if node:GetAttribute(attr) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

----------------------------------------------------------------------
-- Owner-only prompts and signs
----------------------------------------------------------------------
local function homeOwner(rec)
	return rec and tonumber(rec.Folder:GetAttribute("OwnerUserId")) or 0
end

local function promptOwner(prompt, rec)
	local uid = tonumber(prompt:GetAttribute("OwnerUserId"))
	if uid == nil then
		local holder = ancestorWith(prompt.Parent, "OwnerUserId", rec and rec.Folder.Parent)
		uid = holder and tonumber(holder:GetAttribute("OwnerUserId")) or nil
	end
	if uid == nil then
		uid = homeOwner(rec)
	end
	return uid or 0
end

-- what the server would have this prompt show (HomeBuilder's rules), used when HomeFx stops hiding it
local function serverEnabled(prompt, state)
	if prompt.Name == "ClaimPrompt" then
		return state.Home ~= nil and homeOwner(state.Home) == 0
	end
	if prompt.Name == "BuyPrompt" then
		local pad = ancestorWith(prompt.Parent, "Locked", state.Home and state.Home.Folder)
		local locked = pad and pad:GetAttribute("Locked")
		return (locked == nil or locked == "") and promptOwner(prompt, state.Home) ~= 0
	end
	return state.Server
end

local function shouldHide(prompt, state)
	if prompt.Name == "ClaimPrompt" then
		-- one home per player: the other plots' claim prompts go away while the local player owns one
		return ownsHome and homeOwner(state.Home) ~= localUid
	end
	return promptOwner(prompt, state.Home) ~= localUid
end

local function applyPrompt(prompt)
	local state = overrides[prompt]
	if not state or not prompt.Parent then
		return
	end
	local hide = shouldHide(prompt, state)
	if hide then
		state.Hidden = true
		if prompt.Enabled then
			state.Wrote = false
			prompt.Enabled = false
		end
	elseif state.Hidden then
		state.Hidden = false
		local want = serverEnabled(prompt, state) and true or false
		if prompt.Enabled ~= want then
			state.Wrote = want
			prompt.Enabled = want
		end
	end
end

local function trackPrompt(prompt, rec)
	if overrides[prompt] then
		overrides[prompt].Home = rec
		applyPrompt(prompt)
		return
	end
	local state = { Home = rec, Server = prompt.Enabled, Hidden = false, Wrote = nil }
	overrides[prompt] = state
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		local v = prompt.Enabled
		if state.Wrote ~= nil and v == state.Wrote then
			state.Wrote = nil -- the echo of our own write (signals may be deferred)
			return
		end
		state.Server = v
		if state.Hidden and v then
			applyPrompt(prompt)
		end
	end)
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		applyPrompt(prompt)
	end)
	applyPrompt(prompt)
end

-- true when a sign belongs to a locked pad and the local player is not close to it (hysteresis NEAR / FAR)
local function lockedAndFar(gui, rec)
	local pad = ancestorWith(gui.Parent, "Locked", rec.Folder)
	local locked = pad and pad:GetAttribute("Locked")
	if locked == nil or locked == "" or not signFocus then
		signNear[gui] = nil
		return false
	end
	local anchor = gui.Adornee or gui.Parent
	if not anchor or not anchor:IsA("BasePart") then
		return false
	end
	local d = (anchor.Position - signFocus).Magnitude
	local near = d <= (signNear[gui] and K.LOCKED_SIGN_FAR or K.LOCKED_SIGN_NEAR)
	signNear[gui] = near or nil
	return not near
end

-- the StationId of the pad a sign belongs to (its attribute, else the pad model's name "Pad_<Id>": a new pad model
-- gets its attributes only after its sign is built)
local function signKey(gui, rec)
	local key = signKeys[gui]
	if key then
		return key
	end
	local node = gui.Parent
	for _ = 1, 8 do
		if not node or node == rec.Folder then
			break
		end
		local id = node:GetAttribute("StationId")
		if (id == nil or id == "") and node:IsA("Model") and string.sub(node.Name, 1, 4) == "Pad_" then
			id = string.sub(node.Name, 5)
		end
		if id ~= nil and id ~= "" then
			key = tostring(id)
			break
		end
		node = node.Parent
	end
	signKeys[gui] = key
	return key
end

-- why a sign may not show at all: "Other" (not one of the local player's pads), "Locked" (one of their locked pads,
-- far away) or nil (it may show: the on-screen layout decides)
local function signBlock(gui, rec)
	local holder = ancestorWith(gui.Parent, "OwnerUserId", rec.Folder)
	local uid = holder and tonumber(holder:GetAttribute("OwnerUserId")) or homeOwner(rec)
	if uid ~= localUid or uid == 0 then
		return "Other"
	end
	if lockedAndFar(gui, rec) then
		return "Locked"
	end
	return nil
end

local function setSign(gui, show)
	if gui.Enabled ~= show then
		gui.Enabled = show
	end
end

-- a sign that changed (new, rebuilt, its pad locked / unlocked, its home changed hands) between two layout passes
local function applySign(gui)
	local rec = signs[gui]
	if not rec or not gui.Parent then
		return
	end
	local block = signBlock(gui, rec)
	if block then
		signLayout[gui] = nil
		signState[gui] = block
		setSign(gui, false)
		return
	end
	local answer = signLayout[gui]
	if answer == nil then
		-- not laid out yet: HomeBuilder rebuilds a pad's sign on every change, so a rebuilt sign takes its pad's
		-- last answer (no flicker); a new one waits for the layout, which runs on the next frame
		local key = signKey(gui, rec)
		answer = key and rec.SignMemo[key] or nil
		signLayout[gui] = answer
		nextSignCheck = min(nextSignCheck, clock)
	end
	signState[gui] = answer or "Pending"
	setSign(gui, answer == "Shown")
end

local function utf8len(text)
	local _, n = string.gsub(tostring(text or ""), "[^\128-\191]", "")
	return n
end

-- the plate's size when the layout engine has not measured it (yet): its rows of text
local function estimatePlate(plate)
	local w, h = 150, 70
	if not plate then
		return w, h
	end
	local widest, total, rows = 0, 0, 0
	for _, row in ipairs(plate:GetChildren()) do
		if row:IsA("GuiObject") then
			local rw, rh, n = 0, 0, 0
			for _, label in ipairs(row:GetChildren()) do
				if label:IsA("TextLabel") then
					local size = tonumber(label.TextSize) or 20
					local tw = label.TextBounds.X
					if not (tw > 0) then
						tw = utf8len(label.Text) * size * 0.56
					end
					rw = rw + tw + ((n > 0) and 8 or 0)
					rh = max(rh, size + 4)
					n = n + 1
				end
			end
			if n > 0 then
				widest = max(widest, rw)
				total = total + rh + ((rows > 0) and 3 or 0)
				rows = rows + 1
			end
		end
	end
	if rows > 0 then
		w, h = max(150, widest + 28), total + 14
	end
	return w, h
end

-- the sign's plate in pixels (it keeps that size on screen at any distance)
local function plateSize(gui)
	local plate = gui:FindFirstChild("Plate")
	if plate and plate:IsA("GuiObject") then
		local s = plate.AbsoluteSize
		if s.X >= 40 and s.Y >= 20 then
			plateSizes[gui] = s
			return s.X, s.Y
		end
	end
	local known = plateSizes[gui]
	if known then
		return known.X, known.Y
	end
	return estimatePlate(plate)
end

-- the world point the billboard hangs from: its adornee plus the studs offsets
local function signPoint(gui, cam)
	local anchor = gui.Adornee or gui.Parent
	local base = nil
	if anchor then
		if anchor:IsA("BasePart") then
			base = anchor.Position
		elseif anchor:IsA("Attachment") then
			base = anchor.WorldPosition
		elseif anchor:IsA("Model") then
			local ok, cf = pcall(anchor.GetPivot, anchor)
			base = ok and cf and cf.Position or nil
		end
	end
	if not base then
		return nil
	end
	local p = base + gui.StudsOffsetWorldSpace
	local so = gui.StudsOffset
	if so.X ~= 0 or so.Y ~= 0 or so.Z ~= 0 then
		p = p + cam.CFrame:VectorToWorldSpace(so)
	end
	return p
end

-- The HUD over the signs: every ScreenGui is drawn on top of every billboard, so a sign laid out where the HUD is
-- would be cut. measureHud returns where this game's own HUD covers the screen as rectangles in viewport px (the
-- space of Camera:WorldToViewportPoint), each grown by K.SIGN_HUD_GAP:
--   * NimbusMenu: the menu column (MenuColumn, left edge)
--   * NimbusHud: every shown panel of its corner holders (the currency pills, the vitals card, the match / party
--     panels, the title card) and the corner blocks HudController publishes on the gui (TopLeftRight x
--     TopLeftBottom; TopRightLeft .. the right edge x TopRightBottom: the currency stack on short screens)
--   * NimbusHotbar: the hotbar; MobileControls: the touch RUN / DASH buttons
--   * NimbusTutorial: the tutorial card, or only its portrait bubble (+ "!" badge, "Tap me!" tag) while it is folded
-- A ScreenGui with IgnoreGuiInset = false is laid out below Roblox's top bar: its AbsolutePosition is shifted by the
-- GUI inset (GuiService:GetGuiInset()) to reach viewport px; an IgnoreGuiInset = true gui (MobileControls) covers
-- the whole screen from its own AbsolutePosition. Every source is optional: a missing, disabled or hidden one covers
-- nothing.
local function guiInset()
	local inset = nil
	pcall(function()
		inset = GuiService:GetGuiInset()
	end)
	if typeof(inset) == "Vector2" then
		return inset.X, inset.Y
	end
	return 0, 0
end

-- true when `inst` is inside `root` and nothing between them is hidden
local function shownIn(inst, root)
	local node = inst
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil
end

-- inst's box in viewport px grown by the gap (nil when it is not a shown GuiObject of `root` with a size)
local function hudBox(inst, root, dx, dy)
	if not (inst and inst:IsA("GuiObject") and shownIn(inst, root)) then
		return nil
	end
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	if not (s.X >= 1 and s.Y >= 1) then
		return nil
	end
	local g = K.SIGN_HUD_GAP
	return { X0 = p.X + dx - g, Y0 = p.Y + dy - g, X1 = p.X + s.X + dx + g, Y1 = p.Y + s.Y + dy + g, Hud = true }
end

local function measureHud(vp)
	local list = {}
	local pg = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return list
	end
	local insetX, insetY = guiInset()
	local function add(r)
		if r then
			list[#list + 1] = r
		end
		return r
	end
	-- a ScreenGui that is drawn now, and the offset from its descendants' AbsolutePosition to viewport px (one that
	-- covers the whole screen starts at its own AbsolutePosition: right whether Roblox counts that from the top of
	-- the screen, as this project's measurements assume, or from below the top bar)
	local function gui(name)
		local g = pg:FindFirstChild(name)
		if not (g and g:IsA("ScreenGui") and g.Enabled) then
			return nil, 0, 0
		end
		if g.IgnoreGuiInset then
			local origin = g.AbsolutePosition
			return g, -origin.X, -origin.Y
		end
		return g, insetX, insetY
	end
	local menu, mx, my = gui("NimbusMenu")
	if menu then
		add(hudBox(menu:FindFirstChild("MenuColumn"), menu, mx, my))
	end
	local hud, hx, hy = gui("NimbusHud")
	if hud then
		for _, holder in ipairs(hud:GetChildren()) do
			if holder:IsA("GuiObject") and holder.Visible then
				for _, panel in ipairs(holder:GetChildren()) do
					add(hudBox(panel, hud, hx, hy))
				end
			end
		end
		local function attr(name)
			local v = tonumber(hud:GetAttribute(name))
			if v == nil or v ~= v then
				return 0
			end
			return v
		end
		local g = K.SIGN_HUD_GAP
		local right, bottom = attr("TopLeftRight"), attr("TopLeftBottom")
		if right > 0 and bottom > 0 then
			add({ X0 = hx - g, Y0 = hy - g, X1 = hx + right + g, Y1 = hy + bottom + g, Hud = true })
		end
		local left = attr("TopRightLeft")
		bottom = attr("TopRightBottom")
		if left > 0 and bottom > 0 then
			add({ X0 = hx + left - g, Y0 = hy - g, X1 = vp.X + g, Y1 = hy + bottom + g, Hud = true })
		end
	end
	local hotbar, bx, by = gui("NimbusHotbar")
	if hotbar then
		add(hudBox(hotbar:FindFirstChild("Hotbar"), hotbar, bx, by))
	end
	local mobile, tx, ty = gui("MobileControls")
	if mobile then
		for _, d in ipairs(mobile:GetDescendants()) do
			if d:IsA("GuiButton") then
				add(hudBox(d, mobile, tx, ty))
			end
		end
	end
	local tutorial, ux, uy = gui("NimbusTutorial")
	local card = tutorial and tutorial:FindFirstChild("TutorialPanel")
	if card then
		local main = card:FindFirstChild("Main", true)
		if main and shownIn(main, tutorial) then
			add(hudBox(card, tutorial, ux, uy))
		else
			local portrait = card:FindFirstChild("Portrait", true)
			local bubble = add(hudBox(portrait, tutorial, ux, uy))
			if bubble then
				for _, c in ipairs(portrait:GetChildren()) do
					local r = hudBox(c, tutorial, ux, uy)
					if r and (r.X0 < bubble.X0 or r.Y0 < bubble.Y0 or r.X1 > bubble.X1 or r.Y1 > bubble.Y1) then
						add(r) -- the badge / tag sticking out of the bubble
					end
				end
			end
		end
	end
	return list
end

-- the HUD rectangles for this layout pass: measured again every K.SIGN_HUD_CHECK seconds, and at once (then once
-- more K.SIGN_HUD_SETTLE later) when the viewport changes size
local function hudObstacles(vp)
	local resized = vp.X ~= hudViewX or vp.Y ~= hudViewY
	if resized or clock >= hudNext then
		hudViewX, hudViewY = vp.X, vp.Y
		hudNext = clock + (resized and K.SIGN_HUD_SETTLE or K.SIGN_HUD_CHECK)
		local ok, result = pcall(measureHud, vp)
		if ok and type(result) == "table" then
			hudRects = result
		else
			hudRects = {}
			if not hudWarned then
				hudWarned = true
				warn("[HomeFx] could not measure the HUD: " .. tostring(result))
			end
		end
	end
	return hudRects
end

-- The on-screen layout (World text rule: a pile of overlapping plates is unreadable). Every sign in `list` may show;
-- each is projected through the camera, the plate (bottom-centred on the billboard's bottom edge, like HomeBuilder's
-- tags) becomes a screen rectangle, and the signs nearest the player go first (a locked pad's sign, unless the player
-- stands right at it, as if K.SIGN_LOCKED_BACK studs farther: what can be bought now first): a sign is "Shown" when
-- its plate leaves the text of every plate shown before it alone (an overlap of at most K.SIGN_INSET_X px side by side
-- or K.SIGN_INSET_Y px above / below only covers padding), else "Crowded". The HUD (hudObstacles) is placed before
-- every sign and no plate may reach into it at all (its rectangles carry their own gap): a sign under the HUD is
-- "Crowded" as well (signUnderHud) and takes no room. A sign behind the camera, past its MaxDistance (Roblox does
-- not draw it) or mostly off the screen (less than K.SIGN_ONSCREEN of its plate inside: cut off, it reads as
-- nothing) is "Away" and takes no room. Hysteresis: a shown sign counts K.SIGN_KEEP studs nearer and is placed
-- before all others in its first K.SIGN_HOLD seconds; a hidden one needs K.SIGN_CLEAR px of extra room (from the
-- HUD: K.SIGN_HUD_CLEAR, scaled with the screen height) and K.SIGN_ONSCREEN_BACK of its plate on the screen, and
-- stays hidden at least K.SIGN_HOLD seconds, keeping the room it would get meanwhile.
local function layoutSigns(list)
	local cam = Workspace.CurrentCamera
	if not cam then
		for _, gui in ipairs(list) do
			signLayout[gui] = "Shown"
			signUnderHud[gui] = nil
		end
		return
	end
	local vp = cam.ViewportSize
	local eye = cam.CFrame.Position
	local focus = signFocus or eye
	local hud = hudObstacles(vp)
	local items = {}
	for _, gui in ipairs(list) do
		local item = nil
		local answer = signLayout[gui]
		local fresh = signSince[gui] ~= nil and clock - signSince[gui] < K.SIGN_HOLD
		local pos = signPoint(gui, cam)
		if pos then
			local maxD = tonumber(gui.MaxDistance) or 0
			if maxD <= 0 or (pos - eye).Magnitude <= maxD + K.SIGN_RANGE_SLACK then
				local ok, p = pcall(cam.WorldToViewportPoint, cam, pos)
				if ok and typeof(p) == "Vector3" and p.Z > 0 then
					local w, h = plateSize(gui)
					local size, off = gui.Size, gui.SizeOffset
					local bw, bh = size.X.Offset, size.Y.Offset
					local cx = p.X + off.X * bw
					local bottom = p.Y - off.Y * bh + bh / 2
					local x0, y0 = cx - w / 2, bottom - h
					local shown = answer == "Shown"
					local inside = max(0, min(vp.X, x0 + w) - max(0, x0)) * max(0, min(vp.Y, y0 + h) - max(0, y0))
					if inside >= w * h * (shown and K.SIGN_ONSCREEN or K.SIGN_ONSCREEN_BACK) then
						local dist = (pos - focus).Magnitude
						local d = dist
						if shown then
							d = d - K.SIGN_KEEP
						end
						local pad = ancestorWith(gui.Parent, "Locked", signs[gui].Folder)
						local locked = pad and pad:GetAttribute("Locked")
						if locked ~= nil and locked ~= "" then
							local near = K.SIGN_LOCKED_CLOSE
							d = d + K.SIGN_LOCKED_BACK * clamp01((dist - near) / near)
						end
						item = {
							Gui = gui,
							D = d,
							Key = signKey(gui, signs[gui]) or "",
							Shown = shown,
							Pinned = fresh and shown, -- shown a moment ago: placed first, it stays
							Held = fresh and not shown and answer ~= nil, -- hidden a moment ago: holds its room, not shown yet
							X0 = x0,
							Y0 = y0,
							X1 = x0 + w,
							Y1 = y0 + h,
						}
					end
				end
			end
		end
		if item then
			items[#items + 1] = item
		else
			signLayout[gui] = "Away"
			signUnderHud[gui] = nil
		end
	end
	table.sort(items, function(a, b)
		if a.Pinned ~= b.Pinned then
			return a.Pinned
		end
		if a.D ~= b.D then
			return a.D < b.D
		end
		return a.Key < b.Key
	end)
	local placed = {}
	for i, r in ipairs(hud) do
		placed[i] = r
	end
	-- the first thing already placed (the HUD first) that the plate of `it` runs into when it is grown by `grow` px
	-- against the other plates and by `hudGrow` px against the HUD; nil when there is room
	local function blocker(it, grow, hudGrow)
		for _, o in ipairs(placed) do
			local g, sx, sy = grow, K.SIGN_INSET_X, K.SIGN_INSET_Y
			if o.Hud then
				g, sx, sy = hudGrow, 0, 0
			end
			if min(it.X1 + g, o.X1) - max(it.X0 - g, o.X0) > sx and min(it.Y1 + g, o.Y1) - max(it.Y0 - g, o.Y0) > sy then
				return o
			end
		end
		return nil
	end
	local hudClear = max(K.SIGN_CLEAR, K.SIGN_HUD_CLEAR * vp.Y / 1080)
	for _, it in ipairs(items) do
		local hit = blocker(it, 0, 0)
		signUnderHud[it.Gui] = (hit ~= nil and hit.Hud == true) or nil
		if hit then
			signLayout[it.Gui] = "Crowded"
		elseif it.Shown or (not it.Held and not blocker(it, K.SIGN_CLEAR, hudClear)) then
			placed[#placed + 1] = it
			signLayout[it.Gui] = "Shown"
		else
			-- it fits but stays hidden for now: its hold keeps the room (no farther sign flashes up there until it
			-- comes back); one only short of K.SIGN_CLEAR keeps none (in a still view it would block for good)
			if it.Held then
				placed[#placed + 1] = it
			end
			signLayout[it.Gui] = "Crowded"
		end
	end
end

-- the local player's position for the locked-pad signs: the character, else the camera
local function focusPos()
	local character = localPlayer and localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

-- every K.SIGN_CHECK: the signs of the local player's own home (locked pads show their reason only up close), laid
-- out on the screen so none covers the text of another
local function stepSigns()
	if clock < nextSignCheck then
		return
	end
	nextSignCheck = clock + K.SIGN_CHECK
	if not ownsHome then
		return
	end
	signFocus = focusPos()
	local list = {}
	for gui, rec in pairs(signs) do
		if gui.Parent and homeOwner(rec) == localUid then
			local block = signBlock(gui, rec)
			if block then
				signLayout[gui] = nil
				signState[gui] = block
				setSign(gui, false)
				local key = signKey(gui, rec)
				if key then
					rec.SignMemo[key] = nil
				end
			else
				list[#list + 1] = gui
			end
		end
	end
	local before = {}
	for i, gui in ipairs(list) do
		before[i] = signLayout[gui] == "Shown"
	end
	layoutSigns(list)
	for i, gui in ipairs(list) do
		local rec = signs[gui]
		local answer = signLayout[gui]
		if (answer == "Shown") ~= before[i] or signSince[gui] == nil then
			signSince[gui] = clock
		end
		signState[gui] = answer
		setSign(gui, answer == "Shown")
		local key = signKey(gui, rec)
		if key then
			rec.SignMemo[key] = answer
		end
	end
end

local function refreshHome(rec)
	for prompt, state in pairs(overrides) do
		if state.Home == rec then
			applyPrompt(prompt)
		end
	end
	for gui, r in pairs(signs) do
		if r == rec then
			applySign(gui)
		end
	end
end

-- recomputes "the local player owns a home" and refreshes every claim prompt when it changed
local function refreshOwnership()
	local owns = false
	for _, rec in ipairs(homeList) do
		if localUid ~= 0 and homeOwner(rec) == localUid then
			owns = true
		end
	end
	if owns ~= ownsHome then
		ownsHome = owns
		for prompt in pairs(overrides) do
			if prompt.Name == "ClaimPrompt" then
				applyPrompt(prompt)
			end
		end
	end
end

----------------------------------------------------------------------
-- Pop-in
----------------------------------------------------------------------
local function cameraPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

local function easeBack(p)
	local s = 1.7
	local q = p - 1
	return 1 + q * q * ((s + 1) * q + s)
end

-- returns the pop record (nil when the model simply appears: too far, too much popping already, nothing visible)
local function startPop(model, rec)
	if popParts >= K.MAX_POP_PARTS then
		return nil
	end
	local parts = {}
	for _, p in ipairs(collectParts(model)) do
		if p.Transparency < 1 then
			parts[#parts + 1] = p
		end
	end
	if #parts == 0 then
		return nil
	end
	-- near enough to be seen?
	local eye = cameraPos()
	if eye and rec and rec.Center and (rec.Center - eye).Magnitude > K.NEAR + 60 then
		return nil
	end
	local bottoms = {}
	local lo, hi = math.huge, -math.huge
	for i, p in ipairs(parts) do
		local b = p.Position.Y - p.Size.Y / 2
		bottoms[i] = b
		lo, hi = min(lo, b), max(hi, b)
	end
	local span = max(0.001, hi - lo)
	local start = max(clock, nextPopStart)
	nextPopStart = start + K.POP_STAGGER
	local pop = { Model = model, Parts = parts, CF = {}, Size = {}, Trans = {}, Delay = {}, Start = start, Done = false }
	for i, p in ipairs(parts) do
		pop.CF[i] = p.CFrame
		pop.Size[i] = p.Size
		pop.Trans[i] = p.Transparency
		pop.Delay[i] = (bottoms[i] - lo) / span * K.POP_SPREAD
		p.Transparency = 1
	end
	pop.End = start + K.POP_SPREAD + K.POP_PART
	popParts = popParts + #parts
	pops[#pops + 1] = pop
	return pop
end

local function finishPop(pop)
	if pop.Done then
		return
	end
	pop.Done = true
	popParts = max(0, popParts - #pop.Parts)
	for i, p in ipairs(pop.Parts) do
		if p.Parent then
			p.Size = pop.Size[i]
			p.CFrame = pop.CF[i]
			p.Transparency = pop.Trans[i]
		end
	end
end

local function stepPops()
	local i = 1
	while i <= #pops do
		local pop = pops[i]
		if pop.Done or not pop.Model.Parent or clock >= pop.End then
			finishPop(pop)
			table.remove(pops, i)
		else
			local t = clock - pop.Start
			if t >= 0 then
				for j, p in ipairs(pop.Parts) do
					local q = (t - pop.Delay[j]) / K.POP_PART
					if q > 0 then
						if q >= 1 then
							if p.Transparency ~= pop.Trans[j] then
								p.Size = pop.Size[j]
								p.CFrame = pop.CF[j]
								p.Transparency = pop.Trans[j]
							end
						else
							local s = max(0.05, easeBack(q))
							p.Size = pop.Size[j] * s
							p.CFrame = pop.CF[j] + Vector3.new(0, -K.POP_LIFT * (1 - q), 0)
							local base = pop.Trans[j]
							p.Transparency = base + (1 - base) * (1 - clamp01(q * 2.5))
						end
					end
				end
			end
			i = i + 1
		end
	end
end

local function cancelPopOf(model)
	for _, pop in ipairs(pops) do
		if pop.Model == model then
			finishPop(pop)
		end
	end
end

----------------------------------------------------------------------
-- Pads (the local player's own: glow when affordable)
----------------------------------------------------------------------
local function localCash()
	local v = localPlayer and localPlayer:GetAttribute(CASH_ATTR)
	return tonumber(v)
end

local function padAffordable(pad)
	local model = pad.Model
	local locked = model:GetAttribute("Locked")
	if locked ~= nil and locked ~= "" then
		return nil -- locked pads keep the server's look
	end
	local cash = localCash()
	if cash == nil then
		return true
	end
	return cash >= numAttr(model, "Price", 0)
end

local function refreshPad(rec, pad)
	local ok = nil -- true = can pay, false = cannot yet, nil = not ours / locked / unknown
	if localUid ~= 0 and homeOwner(rec) == localUid then
		ok = padAffordable(pad)
	end
	pad.Afford = ok
	if not pad.PriceLabel or not pad.PriceLabel.Parent then
		pad.PriceLabel = pad.Model:FindFirstChild("PriceLabel", true)
		pad.PriceColor = pad.PriceLabel and pad.PriceLabel.TextColor3 or nil
	end
	local label = pad.PriceLabel
	if label and label.Parent and pad.PriceColor then
		label.TextColor3 = (ok == false) and COLORS.PriceShort or pad.PriceColor
	end
	if ok ~= true then
		for i, p in ipairs(pad.Glows) do
			if p.Parent then
				p.Transparency = (ok == false) and max(pad.GlowBase[i], K.PAD_DIM) or pad.GlowBase[i]
			end
		end
	end
end

local function registerPad(rec, model)
	if rec.Pads[model] then
		return
	end
	local pad = { Model = model, Glows = {}, GlowBase = {}, Wave = 0 }
	for _, p in ipairs(collectParts(model)) do
		if p.Name == "Glow" then
			pad.Glows[#pad.Glows + 1] = p
			pad.GlowBase[#pad.GlowBase + 1] = p.Transparency
		end
	end
	rec.Pads[model] = pad
	model:GetAttributeChangedSignal("Price"):Connect(function()
		refreshPad(rec, pad)
	end)
	model:GetAttributeChangedSignal("Locked"):Connect(function()
		refreshPad(rec, pad)
		local sign = model:FindFirstChild("PadSign", true)
		if sign then
			applySign(sign)
		end
	end)
	refreshPad(rec, pad)
end

local function stepPads(rec, dt)
	for _, pad in pairs(rec.Pads) do
		if pad.Popping and pad.Popping.Done then
			pad.Popping = nil
			refreshPad(rec, pad) -- the pop put back the look the pad had when it started
		end
		if pad.Afford == true and not pad.Popping then
			pad.Wave = pad.Wave + dt * K.PAD_PULSE
			local swing = (0.5 + 0.5 * sin(pad.Wave)) * 0.35
			for i, p in ipairs(pad.Glows) do
				if p.Parent then
					p.Transparency = min(0.9, pad.GlowBase[i] + swing)
				end
			end
		end
	end
end


----------------------------------------------------------------------
-- Pets at work (GardenPets on the Garden's cushions, TrainingPets on the Training Place's mats)
----------------------------------------------------------------------
local function parseSlots(text, maxSlot)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	maxSlot = maxSlot or K.MAX_GARDEN_SLOTS
	for slot, key in string.gmatch(text, "(%d+)=([%w_%-@:]+)") do
		local n = tonumber(slot)
		if n and n >= 1 and n <= maxSlot and n == floor(n) then
			out[n] = key
		end
	end
	return out
end

-- the attribute on the plot folder (TycoonService / PetCareService write it there), else on the Home folder
local function slotText(rec, attr)
	local folder = rec.Folder
	local v = folder.Parent and folder.Parent:GetAttribute(attr)
	if v == nil then
		v = folder:GetAttribute(attr)
	end
	return v
end

local function petDefOf(key)
	if PetKeys and type(PetKeys.DefOf) == "function" then
		local ok, def = pcall(PetKeys.DefOf, key)
		if ok and type(def) == "table" then
			return def
		end
	end
	if PetCatalog and type(PetCatalog.Get) == "function" then
		local ok, def = pcall(PetCatalog.Get, key)
		if ok and type(def) == "table" then
			return def
		end
	end
	return nil
end

-- a fresh Low-detail model of the pet (PetBuilder caches the sculpt and clones; stage > 0: its evolved form),
-- anchored and inert, plus the height of its lowest block under the pivot
local function buildPet(key, scale, stage)
	scale = tonumber(scale) or K.PET_SCALE
	stage = tonumber(stage) or 0
	local lowKey = key .. "|" .. scale .. "|" .. stage
	if not PetBuilder or petLows[lowKey] == false then
		return nil
	end
	local def = petDefOf(key)
	if not def then
		petLows[lowKey] = false
		return nil
	end
	local opts = { Detail = "Low", Scale = scale }
	if stage > 0 then
		opts.Evolved = stage
	end
	local ok, model = pcall(PetBuilder.Build, def, opts)
	if not ok or typeof(model) ~= "Instance" then
		petLows[lowKey] = false
		return nil
	end
	petStats.Builds = petStats.Builds + 1
	if petLows[lowKey] == nil then
		petStats.Cold = petStats.Cold + 1
	end
	model.Name = "HomePet"
	model:SetAttribute("PetKey", key)
	local list = collectParts(model)
	for _, part in ipairs(list) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	local lo = petLows[lowKey]
	if lo == nil then
		model:PivotTo(CFrame.new())
		lo = 0
		local hi, hw, lieLo = 0, 0.5, 0
		local first = true
		local ls, lc = sin(G.LIE_ANGLE), math.cos(G.LIE_ANGLE)
		for _, part in ipairs(list) do
			if part.Transparency < 1 then
				local p, s = part.Position, part.Size
				local bottom = p.Y - s.Y / 2
				-- the lowest point once the pet lies on its side (rolled G.LIE_ANGLE about its forward axis)
				local lying = p.X * ls + p.Y * lc - (abs(ls) * s.X + abs(lc) * s.Y) / 2
				if first or bottom < lo then
					lo, first = bottom, false
				end
				lieLo = min(lieLo, lying)
				hi = max(hi, p.Y + s.Y / 2)
				hw = max(hw, abs(p.X) + s.X / 2)
			end
		end
		petLows[lowKey] = lo
		petDims[lowKey] = { Hi = hi, Hw = min(hw, 2.5), LieLo = lieLo }
	end
	return model, lo
end

-- puts a pet model away (unparented) for the way back; the oldest beyond K.PET_POOL are destroyed
local function poolPet(lowKey, model, lo)
	local ok = lowKey ~= nil and lo ~= nil and pcall(function()
		model.Parent = nil
	end)
	if not ok then
		pcall(model.Destroy, model)
		return
	end
	petPool[#petPool + 1] = { Key = lowKey, Model = model, Lo = lo }
	while #petPool > K.PET_POOL do
		local old = table.remove(petPool, 1)
		pcall(old.Model.Destroy, old.Model)
	end
end

local function pooledPet(lowKey)
	for i = #petPool, 1, -1 do
		if petPool[i].Key == lowKey then
			return i
		end
	end
	return nil
end

local function dropPet(pk, slot)
	local entry = pk.Pets[slot]
	if entry then
		pk.Pets[slot] = nil
		G.releaseEntry(entry)
		if entry.Model then
			poolPet(entry.LowKey, entry.Model, entry.Lo)
		end
	end
end

-- may this frame still build (or take from the pool) a pet model? The first always may; a first-time build
-- (`cold`: a new sculpt or template, many times a clone's cost) only as the frame's first; then at most
-- K.PET_BUILD_MAX and only while the frame has spent less than K.PET_BUILD_BUDGET seconds on them
local function petBudget(cold)
	if petFrameBuilds == 0 then
		return true
	end
	if cold or petFrameBuilds >= K.PET_BUILD_MAX then
		return false
	end
	return os.clock() - petFrameStart < K.PET_BUILD_BUDGET
end

-- a pet model sitting on `seat` (a cushion / mat CFrame, already turned the way the pet looks): from the pool when
-- one waits there, else built; nil when it cannot be built
local function placePet(key, scale, stage, seat)
	local lowKey = key .. "|" .. scale .. "|" .. stage
	local i = pooledPet(lowKey)
	if i then
		local entry = table.remove(petPool, i)
		local ok = pcall(function()
			entry.Model:PivotTo(seat * CFrame.new(0, K.PET_HOVER - entry.Lo, 0))
			entry.Model.Parent = ensurePetFolder()
		end)
		if ok then
			petStats.PoolHits = petStats.PoolHits + 1
			return entry.Model, lowKey, entry.Lo
		end
		pcall(entry.Model.Destroy, entry.Model) -- destroyed while it waited: build a new one
	end
	local model, lo = buildPet(key, scale, stage)
	if not model then
		return nil
	end
	model:PivotTo(seat * CFrame.new(0, K.PET_HOVER - lo, 0))
	model.Parent = ensurePetFolder()
	return model, lowKey, lo
end

local function clearPets(rec)
	for _, pk in pairs(rec.Pet) do
		for slot in pairs(pk.Pets) do
			dropPet(pk, slot)
		end
	end
end

-- brings the pets of one station in line with its attribute (only while the home is near and the station stands)
local function syncPets(rec, kind)
	local pk = rec.Pet[kind]
	pk.Dirty = false
	local info = PET_STATIONS[kind]
	local st = pk.Station
	local want, stages = {}, {}
	if rec.PetsNear and st and st.Model.Parent then
		want, stages = G.wantPets(rec, kind)
	elseif kind == "Training" then
		G.wantPets(rec, kind) -- keeps the jobs (timers) current
	end
	for slot, entry in pairs(pk.Pets) do
		if want[slot] ~= entry.Key or (stages[slot] or 0) ~= entry.Stage or not st or entry.Station ~= st.Model
			or not entry.Model.Parent or entry.Pose ~= G.poseId(rec, kind, slot) then
			dropPet(pk, slot)
		end
	end
	-- slot by slot under the frame's build budget: what does not fit waits for the next frame (still Dirty)
	local scale = info.Scale
	for slot = 1, info.Slots do
		local key = want[slot]
		if key and not pk.Pets[slot] then
			local att = st.Model:FindFirstChild("Spot" .. slot, true)
			local stage = stages[slot] or 0
			local lowKey = key .. "|" .. scale .. "|" .. stage
			if att and att:IsA("Attachment") and petLows[lowKey] ~= false then
				local cold = petLows[lowKey] == nil and pooledPet(lowKey) == nil
				if not petBudget(cold) then
					pk.Dirty = true
					return
				end
				if petFrameBuilds == 0 then
					petFrameStart = os.clock()
				end
				petFrameBuilds = cold and K.PET_BUILD_MAX or (petFrameBuilds + 1)
				local seat = G.seat(rec, kind, slot, att)
				local model, lk, lo = placePet(key, scale, stage, seat)
				if model then
					model.Name = kind .. "Pet"
					local dims = petDims[lk] or {}
					local entry = {
						Key = key,
						Model = model,
						Station = st.Model,
						LowKey = lk,
						Lo = lo,
						Stage = stage,
						Seat = seat,
						Att = att,
						Base = seat * CFrame.new(0, K.PET_HOVER - lo, 0),
						Hw = dims.Hw or 0.8,
						Hi = dims.Hi or 1.6,
						Pose = G.poseId(rec, kind, slot),
						Slot = slot,
						Phase = G.noise(slot, clock + #homeList) * G.mealSeconds(),
					}
					entry.Lie = lo - (dims.LieLo or lo)
					entry.Top = K.PET_HOVER - lo + entry.Hi -- the pet's top above its seat
					pk.Pets[slot] = entry
					G.placed(rec, kind, slot, entry)
					petFramePlaced = petFramePlaced + 1
					if petFramePlaced > petStats.FrameMost then
						petStats.FrameMost = petFramePlaced
					end
				elseif stage > 0 then
					pk.Dirty = true -- the evolved form cannot be built: the plain look next frame (wantPets skips it)
				end
			end
		end
	end
end

local function syncAllPets(rec)
	for kind in pairs(rec.Pet) do
		syncPets(rec, kind)
	end
end

local function stepPetStations(rec)
	for kind, pk in pairs(rec.Pet) do
		if pk.Dirty then
			local st = pk.Station
			if not (st and st.Popping and not st.Popping.Done) then
				syncPets(rec, kind)
			end
		end
	end
	if not PetBuilder or not rec.PetsAnimate or clock < (rec.PetAnimAt or 0) then
		return
	end
	rec.PetAnimAt = clock + K.PET_ANIM_STEP
	for kind, pk in pairs(rec.Pet) do
		local anim = PET_STATIONS[kind].Anim
		for _, entry in pairs(pk.Pets) do
			if entry.Model.Parent then
				pcall(PetBuilder.Animate, entry.Model, clock, entry.Sleep and G.SLEEP_ANIM or anim)
			end
		end
	end
end

local function anyPetsDirty(rec)
	for _, pk in pairs(rec.Pet) do
		if pk.Dirty then
			return true
		end
	end
	return rec.Garden.HeapsDirty or rec.Garden.BowlsDirty
end

----------------------------------------------------------------------
-- Garden (contract 3.2 / 3.3 / 3.7 / 6): coin heaps from CoinPiles, bowls, eating pets, fruit, the Coin Magnet,
-- the scoop zip + "+$" label, the Training Place props, the pet cards. Every part here is a CLIENT part: pooled,
-- built only for homes within K.PET_NEAR, nothing created per coin or per frame, fills / texts written on change.
----------------------------------------------------------------------
G.HEAP_Y = 0.62 -- the sand walks' top in the Garden's station frame (the piles lie on the walks)
G.SLEEP_ANIM = { Flap = 0.15 }
G.LIE_ANGLE = 1.35 -- radians a napping pet rolls onto its side
-- coins / mound radius / height per heap stage (CoinPiles 1..5) and the Welcome-back pile ("W"): <= 40 / 60 parts
G.HEAP = {
	{ N = 3, R = 0.34, H = 0.22 },
	{ N = 7, R = 0.48, H = 0.42 },
	{ N = 13, R = 0.6, H = 0.66 },
	{ N = 22, R = 0.72, H = 0.95 },
	{ N = 33, R = 0.84, H = 1.25 },
	W = { N = 46, R = 1.0, H = 1.6 },
}
G.FRUIT = { -- the flying fruit of each plant look (HomeBuilder's Fruit attribute)
	Berry = Vector3.new(0.42, 0.42, 0.42),
	Carrot = Vector3.new(0.3, 0.66, 0.3),
	Melon = Vector3.new(0.66, 0.56, 0.66),
	Starfruit = Vector3.new(0.6, 0.6, 0.18),
}
G.GREY = Color3.fromRGB(118, 122, 140)

function G.mix(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- deterministic 0..1 noise
function G.noise(a, b)
	local x = sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - floor(x)
end

function G.part(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Size = size
	if color then
		p.Color = color
	end
	return p
end

function G.mealSeconds()
	local c = TycoonCatalog and TycoonCatalog.Coins
	local v = c and tonumber(c.MealSeconds)
	return (v and v > 0) and v or K.MEAL
end

function G.gardenDef()
	if TycoonCatalog and type(TycoonCatalog.Get) == "function" then
		local ok, def = pcall(TycoonCatalog.Get, "Garden")
		if ok and type(def) == "table" then
			return def
		end
	end
	return nil
end

function G.coinPoint(slot)
	if TycoonCatalog and type(TycoonCatalog.CoinPoint) == "function" then
		local ok, p = pcall(TycoonCatalog.CoinPoint, slot)
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	return nil
end

function G.localRoot()
	local char = localPlayer and localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- another player's home: their coins are drawn dimmed and never move
function G.dimmed(rec)
	local owner = homeOwner(rec)
	return owner ~= 0 and owner ~= localUid
end

-- the local player's own home record (or nil)
function G.ownRec()
	if localUid == 0 then
		return nil
	end
	for _, rec in ipairs(homeList) do
		if homeOwner(rec) == localUid and rec.Folder.Parent then
			return rec
		end
	end
	return nil
end

-- "1=3;2=5F;4=2*;W=5" -> { [slot] = { Stage, Full, Lucky }, W = { Stage } } (TycoonService's CoinPiles)
function G.parsePiles(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for slot, stage, flags in string.gmatch(text, "(%w+)=(%d+)([F%*]*)") do
		local n = tonumber(stage)
		local key = (slot == "W") and "W" or tonumber(slot)
		local okKey = key == "W" or (key ~= nil and key >= 1 and key <= K.MAX_GARDEN_SLOTS and key == floor(key))
		if okKey and n and n >= 1 then
			out[key] = { Stage = min(5, floor(n)), Full = string.find(flags, "F", 1, true) ~= nil, Lucky = string.find(flags, "*", 1, true) ~= nil }
		end
	end
	return out
end

-- "1=12:0;3=20:1" -> { [slot] = { Level, Stage } } (GardenInfo)
function G.parseInfo(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for slot, level, stage in string.gmatch(text, "(%d+)=(%d+):(%d+)") do
		local n = tonumber(slot)
		if n and n >= 1 and n <= K.MAX_GARDEN_SLOTS then
			out[n] = { Level = max(1, tonumber(level) or 1), Stage = min(2, tonumber(stage) or 0) }
		end
	end
	return out
end

-- "1=cat:Physique:1760000000;2=fox@Golden:Speed:1760000420" -> keys { [mat] = key }, jobs { [mat] = { Key, Stat, Ends } }
function G.parseTraining(text)
	local keys, jobs = {}, {}
	if type(text) ~= "string" then
		return keys, jobs
	end
	for item in string.gmatch(text, "[^;]+") do
		local slot, key, stat, ends = string.match(item, "^%s*(%d+)=(.+):(%a+):(%d+)%s*$")
		if not slot then
			slot, key = string.match(item, "^%s*(%d+)=([%w_%-@:]+)%s*$")
		end
		local n = tonumber(slot)
		if n and n >= 1 and n <= K.MAX_TRAIN_SLOTS and n == floor(n) and key and key ~= "" then
			keys[n] = key
			jobs[n] = { Key = key, Stat = stat or "Speed", Ends = tonumber(ends) or 0 }
		end
	end
	return keys, jobs
end

-- the open garden places (GardenSlots on the plot, else the Garden model's Open attribute, else 3)
function G.openCount(rec)
	local v = tonumber(slotText(rec, "GardenSlots"))
	if v == nil then
		local st = rec.Pet.Garden.Station
		v = st and st.Model.Parent and tonumber(st.Model:GetAttribute("Open")) or nil
	end
	return max(0, min(K.MAX_GARDEN_SLOTS, floor(v or 3)))
end

-- the Garden's station frame (its Lawn sits on it), re-read when the Garden is rebuilt
function G.frame(rec)
	local gd = rec.Garden
	local st = rec.Pet.Garden.Station
	if not st or not st.Model.Parent then
		return nil
	end
	if gd.FrameModel ~= st.Model then
		gd.FrameModel = st.Model
		gd.Frame = nil
		-- the plot frame first: the Lawn may be mid pop-in (its blocks spring up from below)
		local plot = rec.Folder:GetAttribute("PlotCFrame")
		local def = G.gardenDef()
		local lawn = st.Model:FindFirstChild("Lawn")
		if typeof(plot) == "CFrame" and def and def.Slot and typeof(def.Slot.CFrame) == "CFrame" then
			gd.Frame = plot * def.Slot.CFrame
		elseif lawn and lawn:IsA("BasePart") and not (st.Popping and not st.Popping.Done) then
			gd.Frame = lawn.CFrame * CFrame.new(0, -lawn.Size.Y / 2, 0)
		else
			gd.FrameModel = nil -- try again next time
		end
	end
	return gd.Frame
end

-- the world point a pile lies on: place n -> its CoinPoint on the walk; "W" -> the Welcome-back pile (plot-local)
function G.pilePoint(rec, slot)
	if slot == "W" then
		local plot = rec.Folder:GetAttribute("PlotCFrame")
		local def = G.gardenDef()
		local w = def and def.Slot and def.Slot.WelcomePile
		if typeof(plot) == "CFrame" and typeof(w) == "Vector3" then
			return plot:PointToWorldSpace(Vector3.new(w.X, w.Y + 0.02, w.Z))
		end
		return nil
	end
	local frame = G.frame(rec)
	local cp = G.coinPoint(slot)
	if not frame or not cp then
		return nil
	end
	return frame:PointToWorldSpace(Vector3.new(cp.X, G.HEAP_Y, cp.Z))
end

-- the scoop radius of a home: TycoonCatalog.ScoopRadius from the Coin Magnet's level (6 studs without one)
function G.scoopRadius(rec)
	local lv = rec.Magnet and rec.Magnet.Level or 0
	if TycoonCatalog and type(TycoonCatalog.ScoopRadius) == "function" then
		local ok, r = pcall(TycoonCatalog.ScoopRadius, { Stations = { Collector = lv } })
		if ok and type(r) == "number" and r > 0 then
			return r
		end
	end
	return 6
end

-- the food in the bowls: the fruit of the best plant built (Starfruit > Melons > Carrots > Berries), else grass
function G.foodColor(rec)
	local best, color = -1, COLORS.Grass
	for _, st in ipairs(rec.Plants) do
		local n = tonumber(string.match(st.Id, "%d+")) or 0
		local c = st.Model:GetAttribute("FruitColor")
		if n > best and typeof(c) == "Color3" then
			best, color = n, c
		end
	end
	return color
end

----------------------------------------------------------------------
-- pools: flying coins (<= K.MAX_COINS), fruit (<= K.MAX_FRUIT), heaps (cloned templates), sparkles, Zzz, bowls
----------------------------------------------------------------------
function G.takeCoin(i)
	if G.coinsAlive >= K.MAX_COINS then
		return nil
	end
	local p = table.remove(G.coinPool)
	if not p then
		p = G.part("FlyingCoin", Vector3.new(0.5, 0.12, 0.5), COLORS.Gold)
		G.coinsMade = G.coinsMade + 1
	end
	p.Color = COLORS.Coins[((i or 1) - 1) % #COLORS.Coins + 1]
	G.coinsAlive = G.coinsAlive + 1
	return p
end

function G.giveCoin(p)
	G.coinsAlive = max(0, G.coinsAlive - 1)
	p.Parent = nil
	G.coinPool[#G.coinPool + 1] = p
end

function G.takeFruit(look, color)
	if G.fruitAlive >= K.MAX_FRUIT then
		return nil
	end
	local p = table.remove(G.fruitPool)
	if not p then
		p = G.part("FlyingFruit", Vector3.new(0.4, 0.4, 0.4), COLORS.Grass)
		G.fruitMade = G.fruitMade + 1
	end
	p.Size = G.FRUIT[look] or G.FRUIT.Berry
	p.Color = color or COLORS.Grass
	G.fruitAlive = G.fruitAlive + 1
	return p
end

function G.giveFruit(p)
	G.fruitAlive = max(0, G.fruitAlive - 1)
	p.Parent = nil
	G.fruitPool[#G.fruitPool + 1] = p
end

-- a part flying from a to b (b follows `follow` when given) in an arc, back to its pool when it lands
function G.fly(rec, part, a, b, dur, arc, poolName, follow)
	part.CFrame = CFrame.new(a)
	part.Parent = ensureFolder()
	G.flying[#G.flying + 1] = { Part = part, Rec = rec, A = a, B = b, T = 0, Dur = max(0.05, dur), Arc = arc or 0, Pool = poolName,
		Follow = follow, Spin = G.noise(#G.flying, clock) * 6 }
end

function G.land(f)
	if f.Pool == "fruit" then
		G.giveFruit(f.Part)
	else
		G.giveCoin(f.Part)
	end
end

function G.stepFlying(dt)
	local list = G.flying
	local i = 1
	while i <= #list do
		local f = list[i]
		f.T = f.T + dt
		local q = f.T / f.Dur
		if q >= 1 then
			G.land(f)
			table.remove(list, i)
		else
			local b = f.B
			if f.Follow and f.Follow.Parent then
				b = f.Follow.Position
			end
			local pos = f.A:Lerp(b, q) + Vector3.new(0, f.Arc * 4 * q * (1 - q), 0)
			f.Part.CFrame = CFrame.new(pos) * CFrame.Angles(0.5, f.Spin + f.T * 9, 0)
			i = i + 1
		end
	end
end

-- the flying parts of one home go back to their pools (the home froze or went away)
function G.recycle(rec)
	local list = G.flying
	for i = #list, 1, -1 do
		if list[i].Rec == rec then
			G.land(list[i])
			table.remove(list, i)
		end
	end
end

function G.lookOf(slot, stage, dim)
	return ((slot == "W") and "W" or tostring(stage)) .. (dim and "d" or "")
end

-- a heap of rainbow coins: a golden core with coins piled into a dome (golden-angle spiral), built at the origin
function G.buildHeap(look)
	local stage, d = string.match(look, "^(%w)(d?)$")
	local spec = (stage == "W") and G.HEAP.W or G.HEAP[tonumber(stage) or 1] or G.HEAP[1]
	local dim = d == "d"
	local model = Instance.new("Model")
	model.Name = (stage == "W") and "WelcomeHeap" or "CoinHeap"
	local function tone(c)
		return dim and G.mix(c, G.GREY, 0.55) or c
	end
	-- the golden mass under the coins: a wide low block and a narrower tall one (a dome in two steps)
	local lowH, topH = max(0.08, spec.H * 0.42), max(0.1, spec.H * 0.8)
	local core = G.part("Core", Vector3.new(spec.R * 1.55, lowH, spec.R * 1.55), tone(COLORS.GoldDark))
	core.CFrame = CFrame.new(0, lowH / 2, 0)
	core.Parent = model
	local top = G.part("CoreTop", Vector3.new(spec.R * 0.95, topH, spec.R * 0.95), tone(COLORS.Gold))
	top.CFrame = CFrame.new(0, topH / 2, 0) * CFrame.Angles(0, pi / 4, 0)
	top.Parent = model
	model.PrimaryPart = core
	for i = 1, spec.N do
		local u = (i - 0.5) / spec.N
		local r = spec.R * math.sqrt(u)
		local a = i * 2.39996
		local y = spec.H * (1 - u) ^ 0.75 + 0.03
		local c = (i % 4 == 0) and COLORS.Gold or COLORS.Coins[(i % #COLORS.Coins) + 1]
		local coin = G.part("Coin", Vector3.new(0.56, 0.13, 0.56), tone(c))
		-- flat coins with a small tilt down the slope of the pile, every one turned a little
		coin.CFrame = CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, 0.08 + 0.22 * u)
			* CFrame.Angles(0, G.noise(i, 2) * 1.5, 0)
		if dim then
			coin.Transparency = 0.3
		end
		coin.Parent = model
	end
	if dim then
		core.Transparency = 0.3
		top.Transparency = 0.3
	end
	model:SetAttribute("Lift", lowH / 2)
	model:SetAttribute("Top", spec.H + 0.1)
	return model
end

function G.takeHeap(look)
	local list = G.heapPool[look]
	if list and #list > 0 then
		return table.remove(list)
	end
	if G.heapFrame >= K.HEAP_BUILD_MAX then
		return nil
	end
	G.heapFrame = G.heapFrame + 1
	local tpl = G.heapTpl[look]
	if not tpl then
		tpl = G.buildHeap(look)
		G.heapTpl[look] = tpl
	end
	G.heapsMade = G.heapsMade + 1
	return tpl:Clone()
end

function G.giveHeap(look, model)
	model.Parent = nil
	local list = G.heapPool[look]
	if not list then
		list = {}
		G.heapPool[look] = list
	end
	if #list < K.HEAP_POOL then
		list[#list + 1] = model
	else
		model:Destroy()
	end
end

-- the Lucky coin's sparkle: a golden four-point star (2 neon bars) that turns above the heap
function G.takeSpark()
	local s = table.remove(G.sparkPool)
	if not s then
		local a = G.part("LuckyStar", Vector3.new(0.7, 0.16, 0.16), COLORS.Gold, Enum.Material.Neon)
		local b = G.part("LuckyStar", Vector3.new(0.16, 0.7, 0.16), COLORS.Gold, Enum.Material.Neon)
		s = { a, b }
	end
	return s
end

function G.giveSpark(s)
	for _, p in ipairs(s) do
		p.Parent = nil
	end
	G.sparkPool[#G.sparkPool + 1] = s
end

-- "Zzz": two voxel Z letters (3 bars each) over a napping pet
function G.takeZzz()
	local z = table.remove(G.zzzPool)
	if not z then
		z = { Parts = {}, Local = {} }
		for li, s in ipairs({ 1, 0.65 }) do
			local ox, oy = (li - 1) * 0.42, (li - 1) * 0.5
			local bars = {
				{ Vector3.new(0.5 * s, 0.1 * s, 0.1), CFrame.new(ox, oy + 0.25 * s, 0) },
				{ Vector3.new(0.5 * s, 0.1 * s, 0.1), CFrame.new(ox, oy - 0.25 * s, 0) },
				{ Vector3.new(0.1 * s, 0.68 * s, 0.1), CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, -pi / 4) },
			}
			for _, b in ipairs(bars) do
				local p = G.part("Zzz", b[1], COLORS.Zzz)
				z.Parts[#z.Parts + 1] = p
				z.Local[#z.Local + 1] = b[2]
			end
		end
	end
	return z
end

function G.giveZzz(z)
	for _, p in ipairs(z.Parts) do
		p.Parent = nil
	end
	G.zzzPool[#G.zzzPool + 1] = z
end

-- a food bowl: a pastel dish and the food in it (2 parts)
function G.takeBowl()
	local b = table.remove(G.bowlPool)
	if not b then
		b = {
			Dish = G.part("Bowl", Vector3.new(0.8, 0.3, 0.8), COLORS.Bowls[1]),
			Food = G.part("BowlFood", Vector3.new(0.56, 0.12, 0.56), COLORS.Grass),
		}
	end
	return b
end

function G.giveBowl(b)
	b.Dish.Parent = nil
	b.Food.Parent = nil
	G.bowlPool[#G.bowlPool + 1] = b
end

----------------------------------------------------------------------
-- heaps and bowls of one home
----------------------------------------------------------------------
function G.dropHeap(gd, slot)
	local h = gd.Heaps[slot]
	if not h then
		return
	end
	gd.Heaps[slot] = nil
	if h.Spark then
		G.giveSpark(h.Spark)
	end
	G.giveHeap(h.Look, h.Model)
end

-- the heaps follow CoinPiles (stage -> look; '*' -> the sparkle); others' heaps dimmed and still
function G.syncHeaps(rec)
	local gd = rec.Garden
	gd.HeapsDirty = false
	local want = {}
	if rec.PetsNear and G.frame(rec) then
		want = gd.Piles
	end
	local dim = G.dimmed(rec)
	for slot, h in pairs(gd.Heaps) do
		local p = want[slot]
		if not p or h.Look ~= G.lookOf(slot, p.Stage, dim) or h.Frame ~= gd.Frame or not h.Model.Parent then
			G.dropHeap(gd, slot)
		end
	end
	for slot, p in pairs(want) do
		local h = gd.Heaps[slot]
		if not h then
			local point = G.pilePoint(rec, slot)
			local look = G.lookOf(slot, p.Stage, dim)
			local model = point and G.takeHeap(look) or nil
			if point and not model then
				gd.HeapsDirty = true -- over this frame's budget: the next frame
			elseif model then
				local lift = tonumber(model:GetAttribute("Lift")) or 0
				local seed = (slot == "W") and 13 or slot
				model:PivotTo(CFrame.new(point + Vector3.new(0, lift, 0)) * CFrame.Angles(0, G.noise(seed, 5) * 6.28, 0))
				model.Parent = ensureFolder()
				h = { Look = look, Model = model, Point = point, Frame = gd.Frame, Top = tonumber(model:GetAttribute("Top")) or 0.5, Dim = dim, Stage = p.Stage }
				gd.Heaps[slot] = h
			end
		end
		if h then
			local lucky = p.Lucky and not dim
			if lucky and not h.Spark then
				h.Spark = G.takeSpark()
				for _, part in ipairs(h.Spark) do
					part.CFrame = CFrame.new(h.Point + Vector3.new(0, h.Top + 0.45, 0))
					part.Parent = ensureFolder()
				end
			elseif not lucky and h.Spark then
				G.giveSpark(h.Spark)
				h.Spark = nil
			end
		end
	end
end

-- a bowl in front of every open place, toward its pile (the walk); the food is the best plant's fruit
function G.syncBowls(rec)
	local gd = rec.Garden
	gd.BowlsDirty = false
	local frame = rec.PetsNear and G.frame(rec) or nil
	local def = G.gardenDef()
	local spots = def and def.Slot and def.Slot.Spots
	local open = (frame and spots) and min(gd.Open, #spots) or 0
	if gd.BowlFrame ~= frame then
		for slot, b in pairs(gd.Bowls) do
			G.giveBowl(b)
			gd.Bowls[slot] = nil
		end
		gd.BowlFrame = frame
	end
	for slot, b in pairs(gd.Bowls) do
		if slot > open then
			G.giveBowl(b)
			gd.Bowls[slot] = nil
		end
	end
	local color = G.foodColor(rec)
	for slot = 1, open do
		local b = gd.Bowls[slot]
		if not b then
			local p = spots[slot]
			local cp = G.coinPoint(slot) or p
			local dir = (cp.Z > p.Z) and 1 or -1
			local c = frame * CFrame.new(p.X, 1.0, p.Z + dir * 1.25)
			b = G.takeBowl()
			b.Dish.CFrame = c * CFrame.new(0, 0.15, 0)
			b.Food.CFrame = c * CFrame.new(0, 0.36, 0)
			b.Dish.Color = COLORS.Bowls[(slot - 1) % #COLORS.Bowls + 1]
			b.Top = c.Position + Vector3.new(0, 0.45, 0)
			b.Dish.Parent = ensureFolder()
			b.Food.Parent = ensureFolder()
			gd.Bowls[slot] = b
		end
		b.Food.Color = color
	end
end

-- a bowl for a fruit: one of a pet's (random), else any
function G.pickBowl(rec)
	local gd = rec.Garden
	local withPet, any = {}, {}
	for slot, b in pairs(gd.Bowls) do
		any[#any + 1] = b
		if rec.Pet.Garden.Pets[slot] then
			withPet[#withPet + 1] = b
		end
	end
	local list = (#withPet > 0) and withPet or any
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

----------------------------------------------------------------------
-- pets: seats, poses, eating, napping, training props
----------------------------------------------------------------------
-- what a placed pet depends on besides its key (a training pet's skill decides its seat and prop)
function G.poseId(rec, kind, slot)
	if kind == "Training" then
		local job = rec.Train.Jobs[slot]
		return job and job.Stat or ""
	end
	return ""
end

function G.wantPets(rec, kind)
	local stages = {}
	if kind == "Training" then
		local keys, jobs = G.parseTraining(slotText(rec, "TrainingPets"))
		rec.Train.Jobs = jobs
		return keys, stages
	end
	local keys = parseSlots(slotText(rec, "GardenPets"), K.MAX_GARDEN_SLOTS)
	if localUid ~= 0 and homeOwner(rec) == localUid then
		-- the local player's own evolved garden pets show their evolved form (at most K.EVO_MAX of them)
		local n = 0
		for slot = 1, K.MAX_GARDEN_SLOTS do
			local info = rec.Garden.Info[slot]
			if keys[slot] and info and info.Stage > 0 and n < K.EVO_MAX then
				local lk = keys[slot] .. "|" .. PET_STATIONS.Garden.Scale .. "|" .. info.Stage
				if petLows[lk] ~= false then
					stages[slot] = info.Stage
					n = n + 1
				end
			end
		end
	end
	return keys, stages
end

-- the CFrame a pet sits on: garden pets look at their bowl, training pets by skill (a treadmill lifts them, the
-- shield dummy stands beside them)
function G.seat(rec, kind, slot, att)
	local cf = att.WorldCFrame
	if kind == "Garden" then
		local def = G.gardenDef()
		local spot = def and def.Slot and def.Slot.Spots and def.Slot.Spots[slot]
		local cp = G.coinPoint(slot)
		if spot and cp and cp.Z > spot.Z then
			cf = cf * CFrame.Angles(0, pi, 0)
		end
		return cf
	end
	local job = rec.Train.Jobs[slot]
	local stat = job and job.Stat
	if stat == "Speed" then
		return cf * CFrame.new(0, 0.26, 0)
	elseif stat == "Defense" then
		return cf * CFrame.Angles(0, -pi / 2, 0)
	end
	return cf
end

-- writes a pet's pose only when it changed (dip into the bowl, wiggle, lift, a push forward)
function G.pose(entry, dip, wig, lift, push)
	local qd = floor(dip * 20 + 0.5)
	local qw = floor(wig * 50 + 0.5)
	local ql = floor((lift or 0) * 50 + 0.5)
	local qp = floor((push or 0) * 50 + 0.5)
	local key = qd + 32 * (qw + 64) + 4096 * (ql + 64) + 524288 * (qp + 64)
	if entry.PoseKey == key then
		return
	end
	entry.PoseKey = key
	local cf = entry.Base
	if qd ~= 0 then
		cf = cf * CFrame.new(0, -0.22 * dip, -0.32 * dip) * CFrame.Angles(-0.38 * dip, 0, 0)
	end
	if qw ~= 0 then
		cf = cf * CFrame.Angles(0, wig, 0)
	end
	if ql ~= 0 or qp ~= 0 then
		cf = cf * CFrame.new(0, lift or 0, -(push or 0))
	end
	entry.Model:PivotTo(cf)
end

-- napping (a full pile, or a place above the open count): the pet lies on its side with a "Zzz"
function G.setSleep(entry, sleep)
	entry.PoseKey = nil
	entry.Sleep = sleep
	if sleep then
		entry.Model:PivotTo(entry.Base * CFrame.new(0, entry.Lie or 0, 0) * CFrame.Angles(0, 0, G.LIE_ANGLE))
		if not entry.Zzz then
			entry.Zzz = G.takeZzz()
			for _, p in ipairs(entry.Zzz.Parts) do
				p.Parent = ensureFolder()
			end
			G.stepZzz(entry, true)
		end
	else
		entry.Model:PivotTo(entry.Base)
		if entry.Zzz then
			G.giveZzz(entry.Zzz)
			entry.Zzz = nil
		end
	end
end

function G.stepZzz(entry, force)
	local z = entry.Zzz
	if not z then
		return
	end
	local t = clock + (entry.Slot or 0) * 0.7
	local q = (t * 0.5) % 1
	local pos = entry.Seat.Position + Vector3.new(0.3, (entry.Hw or 0.8) * 1.4 + 0.5 + q * 0.6, 0)
	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.Position or (pos + Vector3.new(0, 0, -1))
	local flat = Vector3.new(look.X, pos.Y, look.Z)
	if (flat - pos).Magnitude < 0.01 then
		flat = pos + Vector3.new(0, 0, -1)
	end
	local base = CFrame.lookAt(pos, flat)
	for i, p in ipairs(z.Parts) do
		p.CFrame = base * z.Local[i]
	end
end

-- a pet just placed: a training pet gets its prop
function G.placed(rec, kind, slot, entry)
	if kind == "Training" then
		local job = rec.Train.Jobs[slot]
		entry.Stat = job and job.Stat or "Speed"
		G.attachProp(entry)
	end
end

-- a pet going away: its card, Zzz and prop are put away
function G.releaseEntry(entry)
	if entry.Card then
		pcall(entry.Card.Destroy, entry.Card)
		entry.Card = nil
	end
	if entry.Zzz then
		G.giveZzz(entry.Zzz)
		entry.Zzz = nil
	end
	if entry.Prop then
		G.giveProp(entry.Prop)
		entry.Prop = nil
	end
end

-- one coin hops from an eating pet onto its pile (only while the home is near: purely a look)
function G.dropCoin(rec, slot, entry)
	local h = rec.Garden.Heaps[slot]
	local target = (h and (h.Point + Vector3.new(0, h.Top, 0))) or G.pilePoint(rec, slot)
	if not target then
		return
	end
	local part = G.takeCoin(slot)
	if not part then
		return
	end
	local from = (entry.Base * CFrame.new(0, (entry.Hi or 1.6) * 0.6, 0)).Position
	G.fly(rec, part, from, target, K.COIN_FLIGHT, 1.8, "coin")
	G.stats.Drops = G.stats.Drops + 1
end

-- every garden pet: the meal rhythm (dip, dip, a coin pops out, a wiggle), naps on a full pile or a closed bed
function G.stepGarden(rec, dt)
	local gd = rec.Garden
	local pk = rec.Pet.Garden
	local meal = G.mealSeconds()
	local motion = clock >= (gd.MotionAt or 0)
	if motion then
		gd.MotionAt = clock + K.MOTION_STEP
	end
	for slot, entry in pairs(pk.Pets) do
		if entry.Model.Parent then
			local pile = gd.Piles[slot]
			local sleep = slot > gd.Open or (pile ~= nil and pile.Full)
			if sleep ~= (entry.Sleep == true) then
				G.setSleep(entry, sleep)
			end
			if sleep then
				if motion and rec.PetsAnimate then
					G.stepZzz(entry)
				end
			else
				local prev = entry.Phase or 0
				local ph = prev + dt
				local dip, wig = 0, 0
				if rec.PetsAnimate then
					if ph >= K.DIP_START and ph < K.DIP_START + K.DIP_TIME then
						local s = sin((ph - K.DIP_START) / K.DIP_TIME * 2 * pi)
						dip = s * s
					elseif ph >= K.POP_AT and ph < K.POP_AT + K.WIGGLE_TIME then
						wig = 0.18 * sin((ph - K.POP_AT) / K.WIGGLE_TIME * pi * 4)
					end
					if prev < K.POP_AT and ph >= K.POP_AT then
						G.dropCoin(rec, slot, entry)
					end
				end
				if ph >= meal then
					ph = ph - meal
				end
				entry.Phase = ph
				if motion then
					G.pose(entry, dip, wig)
				end
			end
		end
	end
	if gd.HeapsDirty then
		G.syncHeaps(rec)
	end
	if gd.BowlsDirty then
		G.syncBowls(rec)
	end
	if motion and rec.PetsAnimate then
		for _, h in pairs(gd.Heaps) do
			if h.Spark then
				local cf = CFrame.new(h.Point + Vector3.new(0, h.Top + 0.45 + 0.12 * sin(clock * 2.5), 0)) * CFrame.Angles(0, clock * 2, 0)
				h.Spark[1].CFrame = cf
				h.Spark[2].CFrame = cf
			end
		end
	end
end

----------------------------------------------------------------------
-- the Training Place props: treadmill (Speed), dumbbell (Physique), orb (Ability), shield dummy (Defense)
----------------------------------------------------------------------
G.PROPS = {
	-- { name, size, local CFrame (mat frame, the pet looks at -Z), colour, material, moves? }
	Speed = {
		{ "Deck", Vector3.new(1.7, 0.2, 2.3), CFrame.new(0, 0.1, 0), Color3.fromRGB(78, 84, 104) },
		{ "Belt", Vector3.new(1.45, 0.06, 2.1), CFrame.new(0, 0.23, 0), Color3.fromRGB(40, 42, 54) },
		{ "Stripe", Vector3.new(1.45, 0.03, 0.18), CFrame.new(0, 0.27, 0), Color3.fromRGB(140, 148, 176), nil, "Belt" },
		{ "Stripe", Vector3.new(1.45, 0.03, 0.18), CFrame.new(0, 0.27, 0), Color3.fromRGB(140, 148, 176), nil, "Belt2" },
		{ "Post", Vector3.new(0.16, 1.1, 0.16), CFrame.new(-0.72, 0.75, -1.1), Color3.fromRGB(206, 212, 228) },
		{ "Post", Vector3.new(0.16, 1.1, 0.16), CFrame.new(0.72, 0.75, -1.1), Color3.fromRGB(206, 212, 228) },
		{ "Console", Vector3.new(1.6, 0.28, 0.34), CFrame.new(0, 1.36, -1.1), Color3.fromRGB(92, 152, 232) },
		{ "Screen", Vector3.new(0.62, 0.14, 0.04), CFrame.new(0, 1.39, -1.28), Color3.fromRGB(120, 255, 170), Enum.Material.Neon },
	},
	Physique = {
		{ "Bar", Vector3.new(1.9, 0.12, 0.12), CFrame.new(0, 0, 0), Color3.fromRGB(196, 202, 216), nil, "Lift" },
		{ "Grip", Vector3.new(0.5, 0.17, 0.17), CFrame.new(0, 0, 0), Color3.fromRGB(250, 214, 92), nil, "Lift" },
		{ "Plate", Vector3.new(0.16, 0.7, 0.7), CFrame.new(-0.6, 0, 0), Color3.fromRGB(62, 66, 84), nil, "Lift" },
		{ "Plate", Vector3.new(0.16, 0.7, 0.7), CFrame.new(0.6, 0, 0), Color3.fromRGB(62, 66, 84), nil, "Lift" },
		{ "Plate", Vector3.new(0.12, 0.5, 0.5), CFrame.new(-0.78, 0, 0), Color3.fromRGB(230, 84, 100), nil, "Lift" },
		{ "Plate", Vector3.new(0.12, 0.5, 0.5), CFrame.new(0.78, 0, 0), Color3.fromRGB(230, 84, 100), nil, "Lift" },
		{ "Rack", Vector3.new(0.5, 0.12, 0.5), CFrame.new(1.05, 0.06, 0.85), Color3.fromRGB(62, 66, 84) },
		{ "Rack", Vector3.new(0.38, 0.1, 0.38), CFrame.new(1.05, 0.17, 0.85), Color3.fromRGB(230, 84, 100) },
	},
	Ability = {
		{ "Rune", Vector3.new(2.0, 0.04, 0.14), CFrame.new(0, 0.03, 0) * CFrame.Angles(0, pi / 4, 0), Color3.fromRGB(176, 120, 255), Enum.Material.Neon },
		{ "Rune", Vector3.new(2.0, 0.04, 0.14), CFrame.new(0, 0.03, 0) * CFrame.Angles(0, -pi / 4, 0), Color3.fromRGB(176, 120, 255), Enum.Material.Neon },
		{ "Core", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0, 0), Color3.fromRGB(196, 126, 255), Enum.Material.Neon, "Orb" },
		{ "Shell", Vector3.new(0.82, 0.82, 0.82), CFrame.new(0, 0, 0), Color3.fromRGB(220, 196, 255), nil, "Shell" },
		{ "Spark", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0, 0), Color3.fromRGB(255, 232, 140), Enum.Material.Neon, "Spark1" },
		{ "Spark", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0, 0), Color3.fromRGB(255, 232, 140), Enum.Material.Neon, "Spark2" },
		{ "Spark", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0, 0), Color3.fromRGB(255, 232, 140), Enum.Material.Neon, "Spark3" },
	},
	Defense = {
		{ "Base", Vector3.new(0.8, 0.14, 0.8), CFrame.new(1.3, 0.07, 0), Color3.fromRGB(150, 104, 70) },
		{ "Post", Vector3.new(0.16, 0.9, 0.16), CFrame.new(1.3, 0.55, 0), Color3.fromRGB(120, 84, 56) },
		{ "Body", Vector3.new(0.45, 0.75, 0.66), CFrame.new(1.3, 1.25, 0), Color3.fromRGB(232, 198, 122), nil, "Wobble" },
		{ "Rope", Vector3.new(0.48, 0.1, 0.68), CFrame.new(1.3, 1.05, 0), Color3.fromRGB(150, 104, 70), nil, "Wobble" },
		{ "Head", Vector3.new(0.42, 0.42, 0.42), CFrame.new(1.3, 1.85, 0), Color3.fromRGB(242, 214, 142), nil, "Wobble" },
		{ "Shield", Vector3.new(0.1, 0.86, 0.76), CFrame.new(1.02, 1.25, 0), Color3.fromRGB(84, 142, 232), nil, "Wobble" },
		{ "Boss", Vector3.new(0.06, 0.3, 0.3), CFrame.new(0.95, 1.25, 0), COLORS.Gold, Enum.Material.Neon, "Wobble" },
	},
}

function G.takeProp(stat)
	local spec = G.PROPS[stat] or G.PROPS.Speed
	local list = G.propPool[stat]
	if list and #list > 0 then
		return table.remove(list)
	end
	local prop = { Stat = stat, Parts = {}, Local = {}, Move = {} }
	for i, row in ipairs(spec) do
		local p = G.part("Train" .. row[1], row[2], row[4], row[5])
		prop.Parts[i] = p
		prop.Local[i] = row[3]
		prop.Move[i] = row[6]
	end
	return prop
end

function G.giveProp(prop)
	for _, p in ipairs(prop.Parts) do
		p.Parent = nil
	end
	local list = G.propPool[prop.Stat]
	if not list then
		list = {}
		G.propPool[prop.Stat] = list
	end
	list[#list + 1] = prop
end

function G.attachProp(entry)
	local prop = G.takeProp(entry.Stat)
	entry.Prop = prop
	prop.Mat = entry.Att.WorldCFrame
	for i, p in ipairs(prop.Parts) do
		p.CFrame = prop.Mat * prop.Local[i]
		p.Parent = ensureFolder()
	end
	G.stepProp(entry, 0)
end

-- a training pet's motion and its prop's moving parts (20 Hz, only homes within K.PET_ANIM_NEAR)
function G.stepProp(entry, t)
	local prop = entry.Prop
	if not prop then
		return
	end
	local stat = prop.Stat
	local lift, push = 0, 0
	local mat = prop.Mat
	local hi = entry.Top or 1.6
	local orbY = hi * 0.75 + 0.35
	for i, p in ipairs(prop.Parts) do
		local mv = prop.Move[i]
		if mv then
			local cf
			if mv == "Belt" or mv == "Belt2" then
				local z = (((t * 1.6) + ((mv == "Belt2") and 0.5 or 0)) % 1 - 0.5) * 2.0
				cf = mat * CFrame.new(0, 0, z) * prop.Local[i]
			elseif mv == "Lift" then
				local c = 0.5 + 0.5 * sin(t * 3)
				cf = mat * CFrame.new(0, hi + 0.35 + 0.4 * c, 0.05) * prop.Local[i]
			elseif mv == "Orb" or mv == "Shell" then
				local spin = (mv == "Orb") and t * 1.6 or -t * 0.9
				cf = mat * CFrame.new(0.95, orbY + 0.12 * sin(t * 2), -0.25) * CFrame.Angles(spin * 0.6, spin, pi / 4)
			elseif string.sub(mv, 1, 5) == "Spark" then
				local k = tonumber(string.sub(mv, 6)) or 1
				local a = t * 2.4 + k * 2.094
				cf = mat * CFrame.new(0.95 + math.cos(a) * 0.62, orbY + 0.18 * sin(a * 1.5), -0.25 + sin(a) * 0.62)
			elseif mv == "Wobble" then
				local ph = (t % 1.4) / 1.4
				local w = 0
				if ph >= 0.18 then
					w = 0.28 * math.exp(-(ph - 0.18) * 5) * math.cos((ph - 0.18) * 24)
				end
				local pivot = CFrame.new(1.3, 0.6, 0)
				cf = mat * pivot * CFrame.Angles(0, 0, -w) * pivot:Inverse() * prop.Local[i]
			end
			if cf then
				p.CFrame = cf
			end
		end
	end
	if stat == "Speed" then
		lift = 0.07 * abs(sin(t * 9))
	elseif stat == "Physique" then
		lift = -0.05 * (0.5 + 0.5 * sin(t * 3))
	elseif stat == "Ability" then
		lift = 0.08 * sin(t * 1.8)
	elseif stat == "Defense" then
		local ph = (t % 1.4) / 1.4
		if ph < 0.18 then
			push = ph / 0.18 * 0.32
		elseif ph < 0.4 then
			push = 0.32 * (1 - (ph - 0.18) / 0.22)
		end
	end
	G.pose(entry, 0, 0, lift, push)
end

function G.stepTraining(rec)
	if not rec.PetsAnimate then
		return
	end
	local tr = rec.Train
	if clock < (tr.MotionAt or 0) then
		return
	end
	tr.MotionAt = clock + K.MOTION_STEP
	for slot, entry in pairs(rec.Pet.Training.Pets) do
		if entry.Prop and entry.Model.Parent then
			G.stepProp(entry, clock + slot * 0.37)
		end
	end
end

----------------------------------------------------------------------
-- plants, the Food Machine and the Coin Magnet
----------------------------------------------------------------------
-- every plant sends its fruit into a bowl every ~3 s; the Food Machine drops one from its chute onto the tray
function G.stepPlants(rec)
	if not rec.PetsNear then
		return
	end
	for i, st in ipairs(rec.Plants) do
		if clock >= (st.NextFruit or 0) then
			st.NextFruit = clock + K.FRUIT_EVERY + (G.noise(clock, i) - 0.5)
			local bowl = G.pickBowl(rec)
			local from = vecAttr(st.Model, "FruitPoint")
			if bowl and from and st.Model.Parent and not (st.Popping and not st.Popping.Done) then
				local c = st.Model:GetAttribute("FruitColor")
				local part = G.takeFruit(st.Model:GetAttribute("Fruit"), typeof(c) == "Color3" and c or nil)
				if part then
					local d = (bowl.Top - from).Magnitude
					G.fly(rec, part, from, bowl.Top, 0.9 + d / 32, 2.5 + d * 0.2, "fruit")
					G.stats.Fruit = G.stats.Fruit + 1
				end
			end
		end
	end
	local m = rec.Machine
	if m and m.Model.Parent and not (m.Popping and not m.Popping.Done) and clock >= (m.NextFruit or 0) then
		m.NextFruit = clock + K.MACHINE_EVERY
		local a, b = vecAttr(m.Model, "ChuteMouth"), vecAttr(m.Model, "Tray")
		if a and b then
			local part = G.takeFruit("Berry", G.foodColor(rec))
			if part then
				G.fly(rec, part, a, b + Vector3.new(0, 0.2, 0), 0.45, 0.4, "fruit")
			end
		end
	end
end

function G.addMagnet(rec, st)
	local head = st.Model:FindFirstChild("MagnetHead")
	local center = vecAttr(st.Model, "MagnetCenter")
	st.Parts, st.Local, st.Angle, st.Boost = {}, {}, 0, 0
	if head and center then
		local inv = CFrame.new(center):Inverse()
		for i, p in ipairs(collectParts(head)) do
			st.Parts[i] = p
			st.Local[i] = inv * p.CFrame
		end
		st.Center = center
	end
	rec.Magnet = st
end

-- the Coin Magnet's head turns (faster for a moment after a scoop)
function G.stepMagnet(rec, dt)
	local st = rec.Magnet
	if not st or not st.Center or #st.Parts == 0 or not st.Model.Parent then
		return
	end
	if st.Popping then
		if st.Popping.Done then
			st.Popping = nil
		else
			return
		end
	end
	local speed = K.MAGNET_SPIN * ((st.Boost > 0) and 3 or 1)
	st.Boost = max(0, st.Boost - dt)
	st.Angle = (st.Angle + dt * speed) % (2 * pi)
	local rot = CFrame.new(st.Center) * CFrame.Angles(0, st.Angle, 0)
	for i, p in ipairs(st.Parts) do
		if p.Parent then
			p.CFrame = rot * st.Local[i]
		end
	end
end

-- the owner's scoop ring: a faint circle of the Magnet's radius around the owner while they stand in the garden
function G.stepRing(rec)
	local show, root, frame = false, nil, nil
	if rec and rec.Near and rec.PetsNear then
		frame = G.frame(rec)
		root = G.localRoot()
		if frame and root then
			local lp = frame:PointToObjectSpace(root.Position)
			show = abs(lp.X) <= 12 and abs(lp.Z) <= 11 and lp.Y > -2 and lp.Y < 9
		end
	end
	if not show then
		if G.ringShown then
			for _, p in ipairs(G.ring) do
				p.Parent = nil
			end
			G.ringShown = false
		end
		return
	end
	if not G.ring then
		G.ring = {}
		for i = 1, K.RING_SEGMENTS do
			local p = G.part("ScoopRing", Vector3.new(1, 0.06, 0.16), COLORS.Ring, Enum.Material.Neon)
			p.Transparency = 0.55
			G.ring[i] = p
		end
	end
	local r = G.scoopRadius(rec)
	local y = frame:PointToWorldSpace(Vector3.new(0, G.HEAP_Y + 0.05, 0)).Y
	local c = root.Position
	local len = 2 * pi * r / K.RING_SEGMENTS * 0.8
	for i, p in ipairs(G.ring) do
		local a = (i - 0.5) / K.RING_SEGMENTS * 2 * pi
		if G.ringR ~= r then
			p.Size = Vector3.new(len, 0.06, 0.16)
		end
		p.CFrame = CFrame.new(c.X + math.cos(a) * r, y, c.Z + sin(a) * r) * CFrame.Angles(0, -a - pi / 2, 0)
		if not G.ringShown then
			p.Parent = ensureFolder()
		end
	end
	G.ringR = r
	G.ringShown = true
end

----------------------------------------------------------------------
-- the scoop: coins zip from the piles to the owner, a "+$1,234" label at the pile (never over the player's head)
----------------------------------------------------------------------
function G.zip(rec, slot, point, stage)
	local root = G.localRoot()
	if not root then
		return
	end
	local n = min(K.ZIP_COINS, 2 + (stage or 1))
	for i = 1, n do
		local part = G.takeCoin(i)
		if not part then
			break
		end
		local off = Vector3.new((G.noise(i, clock) - 0.5) * 0.8, 0.3 + i * 0.05, (G.noise(clock, i) - 0.5) * 0.8)
		G.fly(rec, part, point + off, root.Position, K.ZIP_TIME + i * 0.035, 1.2, "coin", root)
	end
	G.stats.Zips = G.stats.Zips + 1
	local gd = rec.Garden
	if not gd.ZipAt or clock - gd.ZipAt > K.LABEL_PAIR or (stage or 0) > (gd.ZipStage or 0) then
		gd.ZipPoint, gd.ZipStage = point, stage or 0
	end
	gd.ZipAt = clock
	if rec.Magnet then
		rec.Magnet.Boost = 1
	end
end

-- a scoop is the piles that vanished near the owner + the bank (CollectorCash) dropping + the owner's Cash rising,
-- all within K.LABEL_PAIR seconds (the attributes may arrive in any order): then the label shows the drop
function G.pairLabel(rec)
	local gd = rec.Garden
	if not (gd.ZipAt and gd.DropAt and (gd.Drop or 0) >= 1) then
		return
	end
	if clock - gd.ZipAt > K.LABEL_PAIR or clock - gd.DropAt > K.LABEL_PAIR then
		return
	end
	local cashKnown = localPlayer and localPlayer:GetAttribute(CASH_ATTR) ~= nil
	if cashKnown and not (G.gainAt and clock - G.gainAt <= K.LABEL_PAIR) then
		return
	end
	local text = "+" .. formatCash(gd.Drop)
	G.showLabel(gd.ZipPoint, text, "cash")
	G.stats.Labels = G.stats.Labels + 1
	G.stats.LastLabel, G.stats.LastLabelAt = text, gd.ZipPoint
	gd.DropAt, gd.Drop, gd.ZipAt, gd.ZipPoint, gd.ZipStage = nil, nil, nil, nil, nil
	G.gainAt = nil
end

function G.onPiles(rec)
	local gd = rec.Garden
	local old = gd.Piles
	gd.Piles = G.parsePiles(slotText(rec, "CoinPiles"))
	gd.HeapsDirty = true
	if localUid == 0 or homeOwner(rec) ~= localUid or not rec.PetsNear then
		return
	end
	local root = G.localRoot()
	if not root then
		return
	end
	local reach = G.scoopRadius(rec) + 2.5
	local any = false
	for slot, p in pairs(old) do
		local q = gd.Piles[slot]
		if not q or q.Stage < p.Stage then
			local h = gd.Heaps[slot]
			local pt = (h and h.Point) or G.pilePoint(rec, slot)
			if pt then
				local d = root.Position - pt
				if Vector3.new(d.X, 0, d.Z).Magnitude <= reach and abs(d.Y) <= 12 then
					G.zip(rec, slot, pt, p.Stage)
					any = true
				end
			end
		end
	end
	if any then
		G.pairLabel(rec)
	end
end

function G.onCash(rec)
	local gd = rec.Garden
	local v = tonumber(slotText(rec, "CollectorCash")) or 0
	if gd.Cash ~= nil and v < gd.Cash then
		gd.Drop = gd.Cash - v
		gd.DropAt = clock
		G.pairLabel(rec)
	end
	gd.Cash = v
end

function G.onLocalCash()
	local v = localPlayer and tonumber(localPlayer:GetAttribute(CASH_ATTR))
	if v and G.lastCash and v > G.lastCash then
		G.gainAt = clock
		local rec = G.ownRec()
		if rec then
			G.pairLabel(rec)
		end
	end
	G.lastCash = v
end

function G.newLabel()
	local anchor = G.part("ScoopLabel", Vector3.new(0.2, 0.2, 0.2), COLORS.Gold)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "ScoopPop"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Size = UDim2.fromOffset(240, 44)
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.TextStrokeTransparency = 0
	text.TextStrokeColor3 = Color3.fromRGB(46, 30, 12)
	text.Parent = gui
	if Theme then
		text.Font = Theme.Fonts.Display
		Theme.TextOutline(text, 2, Color3.fromRGB(46, 30, 12), 0)
	end
	return { Anchor = anchor, Gui = gui, Text = text }
end

-- a pixel-sized label floating up from a pile: "+$1,234" (gold, 30 px at 1080p) or the visitor hint (20 px)
function G.showLabel(point, text, style)
	if not point then
		return
	end
	local lab = table.remove(G.labelPool)
	if not lab and #G.labels >= K.MAX_LABELS then
		lab = table.remove(G.labels, 1)
	end
	lab = lab or G.newLabel()
	local hint = style == "hint"
	local px = hint and 20 or 30
	local size = px
	if Theme and type(Theme.ScaledSize) == "function" then
		local ok, s = pcall(Theme.ScaledSize, px)
		if ok and type(s) == "number" then
			size = s
		end
	end
	lab.Text.Text = text
	lab.Text.TextSize = size
	lab.Text.TextColor3 = hint and Color3.fromRGB(255, 255, 255) or COLORS.Gold
	lab.Text.TextTransparency = 0
	lab.Gui.Size = UDim2.fromOffset(hint and floor(size * 0.56 * #text + 24) or floor(size * 0.62 * #text + 28), floor(size * 1.5))
	lab.Gui.Name = hint and "OwnerHint" or "ScoopPop"
	lab.From = point + Vector3.new(0, hint and 1.6 or 1.0, 0)
	lab.T = 0
	lab.Dur = hint and K.HINT_TIME or K.LABEL_TIME
	lab.Rise = hint and 0.3 or 1.6
	lab.Anchor.CFrame = CFrame.new(lab.From)
	lab.Anchor.Parent = ensureFolder()
	G.labels[#G.labels + 1] = lab
end

function G.stepLabels(dt)
	local i = 1
	while i <= #G.labels do
		local lab = G.labels[i]
		lab.T = lab.T + dt
		local q = lab.T / lab.Dur
		if q >= 1 then
			lab.Anchor.Parent = nil
			table.remove(G.labels, i)
			G.labelPool[#G.labelPool + 1] = lab
		else
			lab.Anchor.CFrame = CFrame.new(lab.From + Vector3.new(0, lab.Rise * q, 0))
			if q > 0.65 then
				lab.Text.TextTransparency = (q - 0.65) / 0.35
			end
			i = i + 1
		end
	end
end

-- the one-time visitor hint at another player's pile
function G.checkHint(rec, focus)
	if G.hinted or not focus or not rec.PetsNear or not G.dimmed(rec) then
		return
	end
	for _, h in pairs(rec.Garden.Heaps) do
		local d = h.Point - focus
		if Vector3.new(d.X, 0, d.Z).Magnitude <= K.HINT_NEAR and abs(d.Y) < 8 then
			G.hinted = true
			G.stats.Hint = "Only the owner can pick these up"
			G.showLabel(h.Point, G.stats.Hint, "hint")
			return
		end
	end
end

----------------------------------------------------------------------
-- pet cards (client/UI/PetCard): own garden pets level + XP (+ EVOLVE!), own training pets + the timer, other
-- players' garden pets level only; only pets within K.CARD_NEAR studs of the local player carry one
----------------------------------------------------------------------
function G.lazy(field, path)
	if G[field] == nil then
		G[field] = false
		local node = script.Parent
		for _, name in ipairs(path) do
			if name == ".." then
				node = node and node.Parent
			else
				node = node and node:FindFirstChild(name)
			end
		end
		if node then
			local ok, mod = pcall(require, node)
			if ok and type(mod) == "table" then
				G[field] = mod
			end
		end
	end
	return G[field] or nil
end

function G.openPets(key)
	local MC = G.lazy("Menu", { "MenuController" })
	if MC and type(MC.Open) == "function" then
		pcall(MC.Open, "Pets", { Tab = "Pets", Key = key, Action = "Evolve" })
	end
end

function G.cardInfo(rec, kind, slot, entry)
	local own = localUid ~= 0 and homeOwner(rec) == localUid
	local key = entry.Key
	local level, stage = 1, 0
	local info = (kind == "Garden") and rec.Garden.Info[slot] or nil
	if info then
		level, stage = info.Level, info.Stage
	end
	if not own then
		if not info then
			return nil
		end
		return "Other", level, stage
	end
	local S = G.lazy("State", { "..", "State" })
	local xp = nil
	if S and type(S.Get) == "function" then
		local okG, data = pcall(S.Get)
		if okG and type(data) == "table" and type(data.PetLevels) == "table" and data.PetLevels[key] then
			local okL, l, x = pcall(S.PetLevel, key)
			if okL then
				level, xp = tonumber(l) or level, tonumber(x) or 0
			end
		end
		local okE, growth = pcall(S.PetGrowth, key)
		if okE and type(growth) == "table" and tonumber(growth.Evo) and growth.Evo > stage then
			stage = growth.Evo
		end
	end
	local def = petDefOf(key)
	local frac = 0
	local cap = nil
	if def and PetCatalog and type(PetCatalog.LevelCap) == "function" then
		local ok, c = pcall(PetCatalog.LevelCap, def)
		cap = ok and tonumber(c) or nil
	end
	local need = nil
	if TycoonCatalog and type(TycoonCatalog.XpToNext) == "function" then
		local ok, n = pcall(TycoonCatalog.XpToNext, level)
		need = ok and tonumber(n) or nil
	end
	if cap and level >= cap then
		frac = 1
	elseif xp and need and need > 0 then
		frac = clamp01(xp / need)
	end
	local ready = false
	if def and PetCatalog and type(PetCatalog.CanEvolve) == "function" then
		local ok, nxt = pcall(PetCatalog.CanEvolve, def, level, stage)
		ready = ok and nxt ~= nil
	end
	if kind == "Training" then
		local job = rec.Train.Jobs[slot]
		local left = job and max(0, (job.Ends or 0) - serverNow()) or 0
		local rank = 1
		if S and type(S.PetGrowth) == "function" then
			local ok, growth = pcall(S.PetGrowth, key)
			if ok and type(growth) == "table" and type(growth.Job) == "table" then
				rank = tonumber(growth.Job.Rank) or 1
			end
		end
		local total = 60 * max(1, rank)
		if TycoonCatalog and type(TycoonCatalog.TrainSeconds) == "function" then
			local ok, s = pcall(TycoonCatalog.TrainSeconds, rank)
			if ok and tonumber(s) and s > 0 then
				total = s
			end
		end
		total = max(total, left)
		local whole = floor(left + 0.999)
		local text = string.format("%d:%02d", floor(whole / 60), whole % 60)
		return "Training", level, stage, frac, ready, clamp01(1 - left / max(1, total)), text
	end
	return "Garden", level, stage, frac, ready
end

function G.updateCard(rec, kind, slot, entry)
	local PC = G.lazy("PetCard", { "..", "UI", "PetCard" })
	if not PC or type(PC.New) ~= "function" then
		return false
	end
	local mode, level, stage, xp, ready, tfrac, ttext = G.cardInfo(rec, kind, slot, entry)
	if not mode then
		return false
	end
	local adornee = entry.Model.PrimaryPart or entry.Model:FindFirstChildWhichIsA("BasePart")
	if not adornee then
		return false
	end
	local card = entry.Card
	if card and card.mode ~= mode then
		pcall(card.SetMode, card, mode)
	end
	if not card then
		local key = entry.Key
		local ok, c = pcall(PC.New, adornee, mode, (entry.Hi or 1.6) * 0.6 + 0.9, {
			Name = "HomePetCard",
			OnEvolve = function()
				G.openPets(key)
			end,
		})
		if not ok or type(c) ~= "table" then
			return false
		end
		card = c
		entry.Card = c
	end
	pcall(card.SetLevel, card, level, stage, ready)
	if xp then
		pcall(card.SetXp, card, xp)
	end
	if tfrac then
		pcall(card.SetTimer, card, tfrac, ttext)
	end
	return true
end

function G.stepCards()
	if clock < G.nextCards then
		return
	end
	G.nextCards = clock + K.CARD_CHECK
	local focus = focusPos()
	local count = 0
	for _, rec in ipairs(homeList) do
		for kind, pk in pairs(rec.Pet) do
			for slot, entry in pairs(pk.Pets) do
				local want = false
				if focus and rec.PetsNear and entry.Model.Parent then
					local d = (entry.Seat.Position - focus).Magnitude
					want = d <= (entry.Card and (K.CARD_NEAR + 6) or K.CARD_NEAR)
				end
				if want and not G.updateCard(rec, kind, slot, entry) then
					want = false
				end
				if not want and entry.Card then
					pcall(entry.Card.Destroy, entry.Card)
					entry.Card = nil
				end
				if entry.Card then
					count = count + 1
				end
			end
		end
		G.checkHint(rec, focus)
	end
	G.cardCount = count
end

-- one home's garden / training state (attributes changed)
function G.onInfo(rec)
	rec.Garden.Info = G.parseInfo(slotText(rec, "GardenInfo"))
	rec.Pet.Garden.Dirty = true
	G.nextCards = 0
end

function G.onOpen(rec)
	local open = G.openCount(rec)
	if open ~= rec.Garden.Open then
		rec.Garden.Open = open
		rec.Garden.BowlsDirty = true
	end
end

-- everything client-made of one home goes away (frozen, far, removed)
function G.clearHome(rec)
	G.recycle(rec)
	local gd = rec.Garden
	for slot in pairs(gd.Heaps) do
		G.dropHeap(gd, slot)
	end
	for slot, b in pairs(gd.Bowls) do
		G.giveBowl(b)
		gd.Bowls[slot] = nil
	end
	gd.HeapsDirty = true
	gd.BowlsDirty = true
end

function G.stepHome(rec, dt)
	G.stepGarden(rec, dt)
	G.stepTraining(rec)
	G.stepPlants(rec)
	if rec.PetsAnimate then
		G.stepMagnet(rec, dt)
	end
end

----------------------------------------------------------------------
-- Stations
----------------------------------------------------------------------
local function stepSwirl(sw, dt)
	if sw.Popping then
		if sw.Popping.Done then
			sw.Popping = nil
		else
			return
		end
	end
	sw.Angle = (sw.Angle + dt * K.SWIRL_SPEED) % (2 * pi)
	local c = sw.Center
	local rot = CFrame.new(c.X, c.Y + sin(sw.Angle * 1.5) * K.SWIRL_BOB, c.Z) * CFrame.Angles(0, sw.Angle, 0)
	for i, p in ipairs(sw.Parts) do
		if p.Parent then
			p.CFrame = rot * sw.Local[i]
		end
	end
	sw.Wave = sw.Wave + dt * K.GLOW_RATE
	local swing = (0.5 + 0.5 * sin(sw.Wave)) * K.GLOW_SWING
	for i, p in ipairs(sw.Glows) do
		if p.Parent then
			p.Transparency = min(0.95, sw.GlowBase[i] + swing)
		end
	end
end

-- the station kind (HomeBuilder writes Kind; older builds only the id)
local STATION_KINDS = { Collector = "Magnet", Kitchen = "FoodMachine", Gym = "Training", Garden = "Garden", FusionMachine = "Fusion" }

local function registerStation(rec, model)
	if rec.Stations[model] then
		return rec.Stations[model]
	end
	local id = tostring(model:GetAttribute("StationId") or string.sub(model.Name, 9))
	local kind = model:GetAttribute("Kind")
	if kind == nil or kind == "Gym" then
		kind = STATION_KINDS[id] or ((string.sub(id, 1, 5) == "Press") and "Plant" or kind)
	end
	local st = { Model = model, Id = id, Kind = kind, Level = numAttr(model, "Level", 1) }
	rec.Stations[model] = st
	if kind == "Plant" then
		rec.Plants[#rec.Plants + 1] = st
		rec.Garden.BowlsDirty = true -- the food colour
	elseif kind == "Magnet" then
		G.addMagnet(rec, st)
	elseif kind == "FoodMachine" then
		rec.Machine = st
	elseif PET_STATIONS[kind] then
		local pk = rec.Pet[kind]
		pk.Station = st
		pk.Dirty = true
		if kind == "Garden" then
			rec.Garden.FrameModel = nil
			rec.Garden.HeapsDirty = true
			rec.Garden.BowlsDirty = true
			G.onOpen(rec)
		end
	elseif kind == "Fusion" then
		local swirl = model:FindFirstChild("Swirl")
		local center = vecAttr(model, "SwirlCenter")
		if swirl and center then
			local parts = collectParts(swirl)
			local loc = {}
			local base = CFrame.new(center)
			for i, p in ipairs(parts) do
				loc[i] = base:Inverse() * p.CFrame
			end
			st.Parts, st.Local, st.Center, st.Angle, st.Wave = parts, loc, center, 0, 0
			st.Glows, st.GlowBase = {}, {}
			for _, p in ipairs(collectParts(model)) do
				if p.Name == "Glow" and p.Material == Enum.Material.Neon then
					st.Glows[#st.Glows + 1] = p
					st.GlowBase[#st.GlowBase + 1] = p.Transparency
				end
			end
			rec.Swirls[#rec.Swirls + 1] = st
		end
	end
	return st
end

local function removeFrom(list, item)
	for i = #list, 1, -1 do
		if list[i] == item then
			table.remove(list, i)
		end
	end
end

local function unregisterStation(rec, model)
	local st = rec.Stations[model]
	if not st then
		return
	end
	rec.Stations[model] = nil
	removeFrom(rec.Swirls, st)
	removeFrom(rec.Plants, st)
	if rec.Magnet == st then
		rec.Magnet = nil
	end
	if rec.Machine == st then
		rec.Machine = nil
	end
	for kind, pk in pairs(rec.Pet) do
		if pk.Station == st then
			pk.Station = nil
			pk.Dirty = true
			if kind == "Garden" then
				rec.Garden.HeapsDirty = true
				rec.Garden.BowlsDirty = true
			end
		end
	end
end

----------------------------------------------------------------------
-- Homes
----------------------------------------------------------------------
local function isNew(rec, inst)
	local built = tonumber(inst:GetAttribute("BuiltAt"))
	if built then
		return serverNow() - built < K.POP_WINDOW
	end
	return clock - rec.Found > K.POP_LIVE_AFTER
end

local function onDescendant(rec, d)
	if d:IsA("ProximityPrompt") then
		if d.Name ~= "ClaimPrompt" then
			trackPrompt(d, rec)
		end
	elseif d:IsA("BillboardGui") and d.Name == "PadSign" then
		signs[d] = rec
		applySign(d)
		local pad = ancestorWith(d.Parent, "StationId", rec.Folder)
		local entry = pad and rec.Pads[pad]
		if entry then
			entry.PriceLabel = nil
			refreshPad(rec, entry)
		end
	end
end

local function onHomeChild(rec, child, live)
	local name = child.Name
	if string.sub(name, 1, 8) == "Station_" and child:IsA("Model") then
		local st = registerStation(rec, child)
		if live and isNew(rec, child) then
			st.Popping = startPop(child, rec)
		end
	elseif name == "Pads" then
		rec.PadFolder = child
		for _, pad in ipairs(child:GetChildren()) do
			if pad:IsA("Model") then
				registerPad(rec, pad)
			end
		end
		rec.Conns[#rec.Conns + 1] = child.ChildAdded:Connect(function(pad)
			if pad:IsA("Model") then
				registerPad(rec, pad)
				if isNew(rec, pad) and rec.Pads[pad] then
					rec.Pads[pad].Popping = startPop(pad, rec)
				end
			end
		end)
		rec.Conns[#rec.Conns + 1] = child.ChildRemoved:Connect(function(pad)
			rec.Pads[pad] = nil
		end)
	end
end

local function plotCenter(folder)
	local cf = folder:GetAttribute("PlotCFrame")
	if typeof(cf) == "CFrame" then
		return cf.Position
	end
	local v = folder:GetAttribute("PlotCenter")
	if typeof(v) == "Vector3" then
		return v
	end
	return nil
end

-- the plot attributes HomeFx follows (on the plot folder, also read on the Home folder): what each one changes
local HOME_ATTRS = {
	GardenPets = function(rec)
		rec.Pet.Garden.Dirty = true
	end,
	TrainingPets = function(rec)
		rec.Pet.Training.Dirty = true
		G.nextCards = 0
	end,
	GardenInfo = function(rec)
		G.onInfo(rec)
	end,
	GardenSlots = function(rec)
		G.onOpen(rec)
	end,
	CoinPiles = function(rec)
		G.onPiles(rec)
	end,
	CollectorCash = function(rec)
		G.onCash(rec)
	end,
}

local function addHome(folder)
	if homes[folder] or not folder:IsA("Folder") and not folder:IsA("Model") then
		return
	end
	local rec = {
		Folder = folder,
		Found = clock,
		Center = plotCenter(folder),
		Near = false,
		NextNear = 0,
		Stations = {},
		Swirls = {},
		Plants = {},
		Magnet = nil,
		Machine = nil,
		Pads = {},
		Conns = {},
		SignMemo = {}, -- [StationId] = the layout's last answer for that pad's sign (a rebuilt sign starts with it)
		Pet = { -- by station Kind: { Station = record | nil, Pets = { [slot] = entry }, Dirty }
			Garden = { Station = nil, Pets = {}, Dirty = false },
			Training = { Station = nil, Pets = {}, Dirty = false },
		},
		-- CoinPiles / GardenInfo parsed, the client heaps / bowls, the scoop pairing (see "Garden")
		Garden = { Piles = {}, Info = {}, Heaps = {}, Bowls = {}, Open = 3, HeapsDirty = true, BowlsDirty = true },
		Train = { Jobs = {} },
		PetsNear = false,
		PetsAnimate = false,
	}
	homes[folder] = rec
	homeList[#homeList + 1] = rec
	rec.Garden.Piles = G.parsePiles(slotText(rec, "CoinPiles"))
	rec.Garden.Info = G.parseInfo(slotText(rec, "GardenInfo"))
	rec.Garden.Cash = tonumber(slotText(rec, "CollectorCash"))
	for _, child in ipairs(folder:GetChildren()) do
		onHomeChild(rec, child, false)
	end
	for _, d in ipairs(folder:GetDescendants()) do
		onDescendant(rec, d)
	end
	G.onOpen(rec)
	rec.Conns[#rec.Conns + 1] = folder.ChildAdded:Connect(function(child)
		onHomeChild(rec, child, true)
	end)
	rec.Conns[#rec.Conns + 1] = folder.ChildRemoved:Connect(function(child)
		if rec.Stations[child] then
			cancelPopOf(child)
			unregisterStation(rec, child)
		end
	end)
	rec.Conns[#rec.Conns + 1] = folder.DescendantAdded:Connect(function(d)
		onDescendant(rec, d)
	end)
	rec.Conns[#rec.Conns + 1] = folder:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshHome(rec)
		for _, pad in pairs(rec.Pads) do
			refreshPad(rec, pad)
		end
		refreshOwnership()
		-- the owner changed: the heaps' look (dimmed or not), the evolved forms and the cards follow
		rec.Garden.HeapsDirty = true
		rec.Pet.Garden.Dirty = true
		G.nextCards = 0
	end)
	rec.Conns[#rec.Conns + 1] = folder:GetAttributeChangedSignal("PlotCFrame"):Connect(function()
		rec.Center = plotCenter(folder)
	end)
	-- the plot folder's (TycoonService / PetCareService) attributes; the gate (a sibling of the Home folder): its
	-- Claim Home prompt
	local spot = folder.Parent
	for attr, fn in pairs(HOME_ATTRS) do
		local function changed()
			local ok, err = pcall(fn, rec)
			if not ok and not frameWarned then
				frameWarned = true
				warn("[HomeFx] " .. attr .. ": " .. tostring(err))
			end
		end
		rec.Conns[#rec.Conns + 1] = folder:GetAttributeChangedSignal(attr):Connect(changed)
		if spot then
			rec.Conns[#rec.Conns + 1] = spot:GetAttributeChangedSignal(attr):Connect(changed)
		end
	end
	if spot then
		for _, d in ipairs(spot:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				trackPrompt(d, rec)
			end
		end
		rec.Conns[#rec.Conns + 1] = spot.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				trackPrompt(d, rec)
			end
		end)
	end
	refreshOwnership()
	refreshHome(rec)
end

local function resetHome(rec)
	clearPets(rec)
	G.clearHome(rec)
end

local function removeHome(folder)
	local rec = homes[folder]
	if not rec then
		return
	end
	homes[folder] = nil
	removeFrom(homeList, rec)
	for _, c in ipairs(rec.Conns) do
		c:Disconnect()
	end
	rec.Conns = {}
	for model in pairs(rec.Stations) do
		cancelPopOf(model)
	end
	resetHome(rec)
	for prompt, state in pairs(overrides) do
		if state.Home == rec then
			overrides[prompt] = nil
		end
	end
	for gui, r in pairs(signs) do
		if r == rec then
			signs[gui] = nil
		end
	end
	refreshOwnership()
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
local function updateNear(rec, eye)
	if clock < rec.NextNear then
		return
	end
	rec.NextNear = clock + K.NEAR_CHECK
	if not rec.Center then
		rec.Center = plotCenter(rec.Folder)
		if not rec.Center then
			for model in pairs(rec.Stations) do
				local ok, pivot = pcall(function()
					return model:GetPivot()
				end)
				if ok and pivot then
					rec.Center = pivot.Position
					break
				end
			end
		end
	end
	local dist = (rec.Center ~= nil and eye ~= nil) and (rec.Center - eye).Magnitude or 0
	local near = rec.Center ~= nil and dist <= K.NEAR
	local petsNear = near and dist <= (rec.PetsNear and (K.PET_NEAR + 20) or K.PET_NEAR)
	rec.PetsAnimate = petsNear and dist <= K.PET_ANIM_NEAR
	if petsNear ~= rec.PetsNear then
		rec.PetsNear = petsNear
		for _, pk in pairs(rec.Pet) do
			pk.Dirty = true
		end
		rec.Garden.HeapsDirty = true
		rec.Garden.BowlsDirty = true
		if not petsNear then
			G.recycle(rec)
		end
	end
	if near ~= rec.Near then
		rec.Near = near
		if not near then
			resetHome(rec)
		end
	end
end

local function step(dt)
	dt = min(tonumber(dt) or 0, 0.1)
	clock = clock + dt
	petFrameBuilds, petFramePlaced = 0, 0
	G.heapFrame = 0
	if #pops > 0 then
		stepPops()
	end
	local eye = cameraPos()
	stepSigns()
	for _, rec in ipairs(homeList) do
		if rec.Folder.Parent then
			updateNear(rec, eye)
			if rec.Near then
				for _, sw in ipairs(rec.Swirls) do
					stepSwirl(sw, dt)
				end
				stepPads(rec, dt)
				stepPetStations(rec)
				G.stepHome(rec, dt)
			elseif anyPetsDirty(rec) then
				syncAllPets(rec)
				G.syncHeaps(rec)
				G.syncBowls(rec)
			end
		end
	end
	if #G.flying > 0 then
		G.stepFlying(dt)
	end
	if #G.labels > 0 then
		G.stepLabels(dt)
	end
	G.stepRing(G.ownRec())
	G.stepCards()
end

local function safeStep(dt)
	local ok, err = pcall(step, dt)
	if not ok and not frameWarned then
		frameWarned = true
		warn("[HomeFx] frame error: " .. tostring(err))
	end
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function HomeFx.Count()
	return #homeList
end

function HomeFx.Stats()
	local stations, near, hidden, hiddenSigns, pets, trainPets = 0, 0, 0, 0, 0, 0
	local heaps, heapParts, bowls, props, sleeping, plants = 0, 0, 0, 0, 0, 0
	for _, rec in ipairs(homeList) do
		for _, entry in pairs(rec.Pet.Garden.Pets) do
			pets = pets + 1
			if entry.Sleep then
				sleeping = sleeping + 1
			end
		end
		for _, entry in pairs(rec.Pet.Training.Pets) do
			trainPets = trainPets + 1
			if entry.Prop then
				props = props + 1
			end
		end
		for _ in pairs(rec.Stations) do
			stations = stations + 1
		end
		for _, h in pairs(rec.Garden.Heaps) do
			heaps = heaps + 1
			heapParts = heapParts + #h.Model:GetChildren() + (h.Spark and 2 or 0)
		end
		for _ in pairs(rec.Garden.Bowls) do
			bowls = bowls + 1
		end
		plants = plants + #rec.Plants
		if rec.Near then
			near = near + 1
		end
	end
	for prompt, state in pairs(overrides) do
		if state.Hidden and prompt.Parent then
			hidden = hidden + 1
		end
	end
	local shownSigns, crowded, underHud, away = 0, 0, 0, 0
	for gui in pairs(signs) do
		if gui.Parent then
			if not gui.Enabled then
				hiddenSigns = hiddenSigns + 1
			end
			local why = signState[gui]
			if why == "Shown" then
				shownSigns = shownSigns + 1
			elseif why == "Crowded" then
				crowded = crowded + 1
				if signUnderHud[gui] then
					underHud = underHud + 1
				end
			elseif why == "Away" then
				away = away + 1
			end
		end
	end
	return {
		Homes = #homeList,
		Near = near,
		Stations = stations,
		Plants = plants,
		Pops = #pops,
		HiddenPrompts = hidden,
		HiddenSigns = hiddenSigns,
		SignsShown = shownSigns,
		SignsCrowded = crowded,
		SignsUnderHud = underHud,
		SignsAway = away,
		GardenPets = pets,
		TrainingPets = trainPets,
		GymPets = trainPets, -- the Phase 3 name of TrainingPets
		Sleeping = sleeping,
		Props = props,
		Heaps = heaps,
		HeapParts = heapParts,
		HeapsMade = G.heapsMade,
		Bowls = bowls,
		Coins = G.coinsAlive, -- flying coins now (pool cap K.MAX_COINS)
		CoinPool = G.coinsMade, -- coin parts ever made
		Fruit = G.fruitAlive,
		FruitPool = G.fruitMade,
		FruitFlights = G.stats.Fruit,
		Drops = G.stats.Drops,
		Zips = G.stats.Zips,
		Labels = G.stats.Labels,
		LastLabel = G.stats.LastLabel,
		LastLabelAt = G.stats.LastLabelAt,
		Hint = G.stats.Hint,
		Ring = G.ringShown,
		Cards = G.cardCount,
		PetBuilds = petStats.Builds,
		PetColdBuilds = petStats.Cold,
		PetPoolHits = petStats.PoolHits,
		PetPool = #petPool,
		PetFrameMost = petStats.FrameMost,
	}
end

-- one home's client garden (tests / debugging): heaps by pile, bowls, pets and their poses, training pets + props
function HomeFx.Garden(folder)
	local rec = typeof(folder) == "Instance" and (homes[folder] or homes[folder:FindFirstChild("Home") or folder]) or nil
	if not rec then
		return nil
	end
	local out = { Heaps = {}, Bowls = {}, Pets = {}, Training = {}, Open = rec.Garden.Open, Dim = G.dimmed(rec), Radius = G.scoopRadius(rec) }
	for slot, h in pairs(rec.Garden.Heaps) do
		out.Heaps[slot] = { Model = h.Model, Point = h.Point, Stage = h.Stage, Dim = h.Dim, Lucky = h.Spark ~= nil, Parts = #h.Model:GetChildren() }
	end
	for slot, b in pairs(rec.Garden.Bowls) do
		out.Bowls[slot] = { Dish = b.Dish, Food = b.Food }
	end
	for slot, e in pairs(rec.Pet.Garden.Pets) do
		out.Pets[slot] = { Key = e.Key, Model = e.Model, Sleep = e.Sleep == true, Zzz = e.Zzz and e.Zzz.Parts or nil, Card = e.Card, Stage = e.Stage, Seat = e.Seat }
	end
	for slot, e in pairs(rec.Pet.Training.Pets) do
		out.Training[slot] = { Key = e.Key, Model = e.Model, Stat = e.Stat, Prop = e.Prop and e.Prop.Parts or nil, Card = e.Card, Seat = e.Seat }
	end
	return out
end

-- why a pad sign shows or not: "Shown"; hidden: "Crowded" (no room on the screen: another sign or the HUD is there;
-- Stats().SignsUnderHud counts the HUD ones), "Away" (behind the camera, off the screen or past its MaxDistance),
-- "Pending" (not laid out yet), "Locked" (a locked pad far away), "Other" (not the local player's pad); nil for
-- anything HomeFx does not track
function HomeFx.SignState(gui)
	if typeof(gui) ~= "Instance" or not signs[gui] then
		return nil
	end
	return signState[gui]
end

function HomeFx.Init()
	if initialized then
		return
	end
	initialized = true
	localPlayer = localPlayer or Players.LocalPlayer
	localUid = localPlayer and localPlayer.UserId or 0
	CollectionService:GetInstanceAddedSignal(HOME_TAG):Connect(function(folder)
		local ok, err = pcall(addHome, folder)
		if not ok then
			warn("[HomeFx] could not track a home: " .. tostring(err))
		end
	end)
	CollectionService:GetInstanceRemovedSignal(HOME_TAG):Connect(removeHome)
	for _, folder in ipairs(CollectionService:GetTagged(HOME_TAG)) do
		local ok, err = pcall(addHome, folder)
		if not ok then
			warn("[HomeFx] could not track a home: " .. tostring(err))
		end
	end
	if localPlayer then
		G.lastCash = tonumber(localPlayer:GetAttribute(CASH_ATTR))
		localPlayer:GetAttributeChangedSignal(CASH_ATTR):Connect(function()
			for _, rec in ipairs(homeList) do
				if homeOwner(rec) == localUid then
					for _, pad in pairs(rec.Pads) do
						refreshPad(rec, pad)
					end
				end
			end
			G.onLocalCash()
		end)
	end
	-- own pets' levels / XP / evolutions: the cards (and an evolved garden pet's form) follow State
	task.spawn(function()
		local S = G.lazy("State", { "..", "State" })
		if S and S.Changed and type(S.Changed.Connect) == "function" then
			S.Changed:Connect(function()
				G.nextCards = 0
				local rec = G.ownRec()
				if rec then
					rec.Pet.Garden.Dirty = true
				end
			end)
		end
	end)
	loopConn = RunService.RenderStepped:Connect(safeStep)
end

return HomeFx
