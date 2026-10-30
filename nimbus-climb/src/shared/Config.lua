-- Config: every tunable number and shared name in Nimbus Climb lives here.
-- Plain Lua 5.1-compatible syntax only (no Luau type annotations, `continue`, `+=`).

local Config = {}

Config.GameName = "Nimbus Climb"
Config.Tagline = "Climb the storm. Together."

----------------------------------------------------------------------
-- Character physics (applied to every Humanoid by PlayerService)
----------------------------------------------------------------------
local P = {
	Gravity = 196.2,
	WalkSpeed = 16,
	RunSpeed = 27,
	JumpPower = 52, -- Humanoid.UseJumpPower must be true
	MaxHealth = 100,
	DashSpeed = 85,
	DashDuration = 0.18,
	DashCooldown = 1.6,
	DashStaminaCost = 35, -- Phase 5 (3.9): 4 dashes from full
	MaxStamina = 150, -- Phase 5 (3.9): was 100
	StaminaRegen = 45, -- per second while not running (Phase 5: was 22; a full refill takes ~3.3 s)
	RunStaminaDrain = 14, -- per second while running (~10.7 s of running from full)
}
-- Derived numbers the course generator relies on (studs).
P.JumpHeight = (P.JumpPower * P.JumpPower) / (2 * P.Gravity) -- ~6.9
P.AirTime = (2 * P.JumpPower) / P.Gravity -- flat jump, ~0.53s
P.MaxRunGap = P.RunSpeed * P.AirTime -- ~14.3 theoretical
P.DashBonus = (P.DashSpeed - P.RunSpeed) * P.DashDuration -- ~10.4 extra
P.MaxDashGap = P.MaxRunGap + P.DashBonus -- ~24.7 theoretical
Config.Physics = P

-- Phase 5 (contract 3.9 / 4.4): inside a battle zone a dash costs no stamina and the character walks / runs at the
-- fighter's legal battle speed. BattleController calls MovementController.SetFreeDash(true) / SetBattleSpeed(walk, run)
-- on Start and resets them on End; MovementController's EXHAUST_RESUME is 22 (15% of MaxStamina).
Config.Movement = {
	FreeDashInBattle = true, -- MovementController.SetFreeDash(true) while a battle runs
	ExhaustResume = 22, -- stamina needed to run again after hitting 0 (15% of MaxStamina)
}

----------------------------------------------------------------------
-- Names shared by server + client
----------------------------------------------------------------------
Config.Tags = {
	Checkpoint = "NC_Checkpoint", -- attr CheckpointIndex (int, 1..N)
	FinishPad = "NC_FinishPad",
	CloudToken = "NC_CloudToken", -- attr Value (int, default 1)
	SpinBar = "NC_SpinBar", -- attrs Speed (deg/s), Damage
	StormCloud = "NC_StormCloud", -- attr DPS (damage per second)
	LightningZone = "NC_LightningZone", -- attrs Damage, Interval, Warning
	VanishCloud = "NC_VanishCloud", -- attrs VanishDelay, ReturnDelay
	MovingCloud = "NC_MovingCloud", -- attrs EndOffset (Vector3), Period
	BouncePad = "NC_BouncePad", -- attrs Power, LaunchSpeed (horizontal studs/s when the player is moving)
	PressurePlate = "NC_PressurePlate", -- attr BridgeId (string)
	PlateBridge = "NC_PlateBridge", -- attr BridgeId (string)
	-- v2 hazards / elements
	Pendulum = "NC_Pendulum", -- the beam part; attrs Hinge (Vector3 world pivot), Axis (Vector3 world unit, swing axis), Period, Arc (deg each side), Damage
	WindGust = "NC_WindGust", -- invisible volume part; attrs Force (studs/s push), Direction (Vector3 unit), Interval, Warning
	CloudCannon = "NC_CloudCannon", -- the pad part; attrs Target (Vector3 world landing point), FlightTime (s)
	GoldenToken = "NC_GoldenToken", -- a CloudToken whose Value is 5 (also carries CloudToken tag)
}

-- Attributes set on Player instances by the server (client HUD reads them).
Config.Attr = {
	Tokens = "CloudTokens", -- lifetime total (persisted)
	MatchTokens = "MatchTokens", -- collected in current match
	InMatch = "InMatch", -- bool
	Downed = "Downed", -- bool (KO'd inside a match)
	Stamina = "Stamina", -- number, written by the client controller only
	EquippedPets = "EquippedPets", -- csv of pet ids, e.g. "cloudy_dragon,pebble_pup" ("" when none)
	SpotIndex = "SpotIndex", -- lobby spot number (1..Config.Lobby.SpotCount), absent when none
	PerkStaminaRegen = "PerkStaminaRegen", -- number, e.g. 0.2 = +20% stamina regen (server writes)
	-- v3 (see ARCHITECTURE_V3.md). Cash and Gems arrive with the tycoon phase; the HUD shows them only once set.
	Cash = "Cash", -- number, tycoon money (server writes)
	Gems = "Gems", -- number, premium currency (server writes)
	-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract", section 5.3)
	EquippedInfo = "EquippedInfo", -- "23:1,5:0" level:evolution stage per EquippedPets entry (PetService writes)
	HomePortal = "HomePortal", -- "x,y,z,yaw,closesAt" while the owner's home portal is open, absent when closed (TycoonService)
	PortalArrived = "PortalArrived", -- server time of the last arrival through the home portal (TycoonService)
	-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract", section 10.2)
	InBattle = "InBattle", -- battle id, or a dungeon RUN id ("D12") for the whole run (BattleService / DungeonService write; C11)
	InFight = "InFight", -- bool: BattleController draws this player's pets now (DungeonService; dungeon fights only, bug #26)
	Berries = "Berries", -- whole berries (DataService only, inside AddBerries / SpendBerries, <= 2 writes/s)
	ObbyLevel = "ObbyLevel", -- the obby difficulty id the player picked at the Obby gate (PortalService writes)
	ProfileLoaded = "ProfileLoaded", -- true once the profile is loaded or provisional (DataService writes; the loading screen reads it)
	-- wave 6 (fight focus): the trainer is locked on the podium (Champion Ring / PvP duel); the client loops the cheer emote
	OnPodium = "OnPodium", -- bool, absent when free (BattleService / Podium write)
}

Config.Remotes = {
	-- server -> client
	"Notify", -- (text:string, kind:string, duration:number)  kind: info|good|bad|token
	"DamageTaken", -- (amount:number, sourceKind:string)
	"PartyState", -- (state:table|nil)  see ARCHITECTURE.md
	"MatchState", -- (state:table|nil)  see ARCHITECTURE.md
	"MatchResult", -- (result:table)
	"DashFx", -- (userId:number)  server -> all clients, for others' trails
	"ProfileSync", -- (snapshot:table)  see ARCHITECTURE_V2.md
	"RouletteResult", -- (result:table)    see ARCHITECTURE_V2.md
	"OpenPanel", -- (panelId:string, args:table|nil)  e.g. ("Shop", {Tab="Roulette", RouletteId="Cloud"})
	"TutorialState", -- (state:table)  v3, see ARCHITECTURE_V3.md
	"DevPetShow", -- (action:string, payload:table)  developer pet showcase for the developer's own client:
	--   Spawn {PetId, Stage} / Lineup {Stage, PetIds} / Evolve {Steps = {{PetId, From, To}...}} / Clear {}
	-- client -> server
	"Dash", -- ()
	"LeaveParty", -- ()
	"LeaveMatch", -- ()
	"RequestProfile", -- ()  asks for a fresh ProfileSync
	"BuyRoulette", -- (rouletteId:string)
	"EquipPet", -- (petId:string)
	"UnequipPet", -- (petId:string)
	"GoToSpot", -- ()
	"TutorialEvent", -- (eventName:string)  v3: client-observed tutorial events (window opened, skip)
	"IndexClaim", -- (groupId:string)  v3: claim a completed Pet Index group reward
	"DevCommand", -- (command:string, arg:any)  developer tools; the server only obeys allowed players (Config.Dev)
	-- Phase 2 (ARCHITECTURE_V3.md "Phase 2 build contract")
	"HomeAction", -- (action:string, arg:any)  Upgrade / GardenSet / Collect / Prestige / GoHome (Phase 4: GoHome opens the home portal)
	"PetCare", -- (action:string, a:any, b:any)  Phase 5: Feed (key) spends berries; Evolve (key) / Train (key, stat) / TrainStop (key); Cook / GymSet are retired (one toast)
	"Fusion", -- (action:string, a:any, b:any)  Upgrade / Mix
	-- Phase 3 (ARCHITECTURE_V3.md "Phase 3 build contract")
	"BattleState", -- server -> client (kind:string, payload:table)  Start / Snapshot / Events / End
	"BattleCommand", -- (action:string, a:any, b:any)  Phase 5: Attack / Element / Special / Dash / Target / Buff / Swap / Forfeit (Retreat is gone)
	"BattleRequest", -- (action:string, a:any, b:any)  TeamSet / TeamSelect / Challenge / ChallengeReply / Queue / Unqueue / JoinRaid / LeaveRaid / Ring (Phase 4: startRound); Phase 5: Trial is gone
	"ArenaState", -- server -> client (state:table)  next event, countdown, raid status, leaderboard
	-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 5.7, 6.3, 7.2)
	"DungeonRequest", -- (action:string, a:any, b:any)  Open / Create (floor) / Join (leaderUserId) / Leave / Ready (bool) / SetFloor (floor) / Start / Solo (floor) / Quit / Chest / Kick (userId)
	"DungeonState", -- server -> client (kind:string, payload:table)  Lobby / Run / Loot / Chest / End (<= 1 KB, <= 1/s per client)
	"ObbyPick", -- (levelId:string)  pick an obby level at the Obby gate (PortalService.PickLevel; unlocked levels only)
	"SettingsSet", -- (key:string, value:any)  Music / Sfx 0..10, Gfx "Auto"|"Low"|"High", Shake / MouseLock bool, SeenNotes int (DataService)
	"MenuPlay", -- ()  the main menu's PLAY: the server spawns the character (PlayerService.SpawnPlayer; first per session, 1/s)
	"QuickTravel", -- (dest:string) "Court" | "Plaza"  HUD cleanup: the pill's Travel drop-down (GateService.Travel)
}

----------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------
Config.Damage = {
	IFrames = 0.6, -- seconds of invulnerability after a hit
	DownedHealth = 1, -- Humanoid.Health a downed player is held at
	ReviveHealthFraction = 0.5, -- revived players come back with 50%
	CheckpointHealFraction = 0.35, -- everyone alive heals this much at a checkpoint
	VoidDamage = { Easy = 10, Medium = 15, Hard = 22, Extreme = 30, Saint = 40 },
	Kinds = { "Void", "Lightning", "SpinBar", "Storm", "Pendulum", "Other" },
}

----------------------------------------------------------------------
-- Lobby (a big floating cloud village high in the sky)
----------------------------------------------------------------------
-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 6.1): a bigger plaza with the Gate Court (the six mode gates on
-- one arc: Home, Obby, Dungeon, Ring, Arena, Altar, left to right at GateFacing - 2.5 .. + 2.5 steps). Plaza-local
-- angles: 0 = +X, 90 = +Z.
Config.Lobby = {
	Origin = Vector3.new(0, 300, 0), -- centre of the main plaza surface
	PlazaRadius = 150, -- was 110
	GateArcRadius = 118, -- the six gates stand on this arc (replaces PortalRingRadius 88); pad centres at r 104
	GateStep = 14.5, -- degrees between gates (29.8 studs)
	GateFacing = 90, -- degrees: the arc's middle (+Z); the spawn looks this way
	SpotRingRadius = 340, -- was 300: the player home plots stand on this ring (spoke bridges stay 130 studs)
	SpotCount = 16, -- one saved spot per player; set the place's Max Players to <= this
	PlotSize = 72, -- flat square buildable area (studs) of each home plot (read by TycoonCatalog)
	ShopOffset = Vector3.new(0, 0, -196), -- shop island centre relative to Origin (was -150)
	KillY = 100, -- fall below this -> teleport back to the plaza
}

----------------------------------------------------------------------
-- Match settings + difficulties
----------------------------------------------------------------------
Config.Match = {
	MinPlayers = 1,
	MaxPlayers = 4,
	PartyCountdown = 15, -- seconds, starts when the first player enters a portal
	FullPartyCountdown = 4, -- shortened countdown once the party is full
	IntroCountdown = 5, -- "3-2-1" on the start platform (players frozen)
	EndScreenSeconds = 10, -- results screen before returning to lobby
	ArenaOrigin = Vector3.new(4000, 800, 0), -- start-platform centre of slot 1
	SlotSpacing = 800, -- studs between concurrent matches along +X
	MaxConcurrent = 6,
	TokenBonusOnWin = { Easy = 10, Medium = 20, Hard = 35, Extreme = 60, Saint = 100 },
}

-- Overall shape of a course, and the stage themes a course is assembled from.
-- (Semantics in ARCHITECTURE_V2.md. CourseBuilder owns the geometry.)
Config.Archetypes = { "Straight", "Zigzag", "Serpent", "Spiral" }
Config.StageThemes = {
	"Stones", -- plain steps of varied size/shape
	"Beams", -- narrow beams to balance on
	"Bounce", -- bounce pads launching to higher steps
	"Moving", -- clouds sliding back and forth
	"Spin", -- spinning-bar platforms
	"Storm", -- dark rain clouds that drizzle damage
	"Lightning", -- warned lightning strike zones
	"Vanish", -- steps that fade after you land
	"Cannon", -- cloud cannons that fling you to the next island
	"Wind", -- periodic wind gusts pushing sideways
	"Pendulum", -- swinging beams over narrow steps
	"Plates", -- co-op pressure-plate bridges
	"DashGap", -- gaps that need a dash
	"Gauntlet", -- short mixed hazard run
}
Config.Course = {
	MaxRadius = 170, -- no step further than this (horizontal) from the start platform centre
	-- Min free headroom above any walkable top surface (no overhanging steps). A full jump needs
	-- JumpHeight (~6.9, Config.Physics) + the character's height (~5.2) = ~12.1 studs of free air, so the
	-- generator keeps the underside of anything overhanging at least Clearance + 0.3 above the top. Do not
	-- lower this below ~12: an overhanging step would make a full jump bonk its head on it.
	Clearance = 13,
}

-- Order here == order of portals around the lobby (easy -> hardest).
-- Course rules are in STUDS. All gaps are edge-to-edge. Physics-safe by construction:
-- run gaps <= ~0.8 * MaxRunGap (14.3); rises <= 0.7 * JumpHeight (~4.8).
-- Archetypes / Themes are weight tables (higher = more likely).
Config.Difficulties = {
	{
		Id = "Easy",
		DisplayName = "Easy",
		Blurb = "Chill clouds and wide steps. Perfect for new climbers.",
		Color = Color3.fromRGB(96, 190, 140),
		Stars = 1,
		Stages = 4, -- each stage = StepsPerStage steps + 1 checkpoint
		StepsPerStage = { 5, 7 },
		GapMin = 4, GapMax = 7.5,
		RiseMax = 3,
		PlatformMin = 11, PlatformMax = 17,
		HazardChance = 0.10,
		DashGapChance = 0,
		TokensPerStage = 4,
		TimeLimit = 540,
		Archetypes = { Straight = 3, Serpent = 2 },
		Themes = { Stones = 4, Bounce = 3, Moving = 1 },
	},
	{
		Id = "Medium",
		DisplayName = "Medium",
		Blurb = "Moving clouds, spinning bars and your first co-op bridge.",
		Color = Color3.fromRGB(96, 160, 224),
		Stars = 2,
		Stages = 5,
		StepsPerStage = { 6, 8 },
		GapMin = 5.5, GapMax = 9,
		RiseMax = 3.8,
		PlatformMin = 8, PlatformMax = 13,
		HazardChance = 0.30,
		DashGapChance = 0,
		TokensPerStage = 4,
		TimeLimit = 720,
		Archetypes = { Straight = 2, Zigzag = 3, Serpent = 2 },
		Themes = { Stones = 3, Bounce = 2, Moving = 3, Spin = 2, Plates = 2, Cannon = 1 },
	},
	{
		Id = "Hard",
		DisplayName = "Hard",
		Blurb = "Vanishing steps, lightning and swinging beams.",
		Color = Color3.fromRGB(226, 150, 74),
		Stars = 3,
		Stages = 6,
		StepsPerStage = { 6, 8 },
		GapMin = 6.5, GapMax = 10,
		RiseMax = 4.3,
		PlatformMin = 6, PlatformMax = 10,
		HazardChance = 0.50,
		DashGapChance = 0.06,
		DashGapMin = 14, DashGapMax = 17,
		TokensPerStage = 5,
		TimeLimit = 900,
		Archetypes = { Zigzag = 3, Serpent = 2, Spiral = 3 },
		Themes = { Stones = 1, Moving = 2, Spin = 2, Vanish = 3, Lightning = 2, Pendulum = 2, Wind = 2, Plates = 2, Cannon = 2, Beams = 2 },
	},
	{
		Id = "Extreme",
		DisplayName = "Extreme",
		Blurb = "Dash-only gaps, storms and narrow beams. Bring friends.",
		Color = Color3.fromRGB(214, 92, 104),
		Stars = 4,
		Stages = 8,
		StepsPerStage = { 7, 9 },
		GapMin = 7.5, GapMax = 11,
		RiseMax = 4.6,
		PlatformMin = 5, PlatformMax = 8,
		HazardChance = 0.70,
		DashGapChance = 0.15,
		DashGapMin = 15, DashGapMax = 19,
		TokensPerStage = 5,
		TimeLimit = 1200,
		Archetypes = { Zigzag = 2, Serpent = 2, Spiral = 4 },
		Themes = { Stones = 1, Beams = 3, Spin = 2, Vanish = 3, Lightning = 3, Storm = 3, Pendulum = 3, Wind = 3, Plates = 2, Cannon = 2, DashGap = 3, Gauntlet = 2 },
	},
	{
		Id = "Saint",
		DisplayName = "Saint",
		Blurb = "Only the saintly finish. Tiny steps, relentless hazards.",
		Color = Color3.fromRGB(150, 110, 220), -- violet: gold stays reserved for stars and tokens (Theme.World.Trim.Saint mirrors it)
		Stars = 5,
		Stages = 10,
		StepsPerStage = { 7, 10 },
		GapMin = 8, GapMax = 11.5,
		RiseMax = 4.7,
		PlatformMin = 4, PlatformMax = 7,
		HazardChance = 0.85,
		DashGapChance = 0.25,
		DashGapMin = 16, DashGapMax = 20,
		TokensPerStage = 6,
		TimeLimit = 1500,
		Archetypes = { Spiral = 4, Serpent = 2, Zigzag = 2 },
		Themes = { Stones = 1, Beams = 3, Vanish = 3, Lightning = 3, Storm = 3, Pendulum = 3, Wind = 3, Plates = 2, Cannon = 2, DashGap = 4, Gauntlet = 4, Spin = 2 },
	},
}

function Config.GetDifficulty(id)
	for _, d in ipairs(Config.Difficulties) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Tokens + persistence
----------------------------------------------------------------------
Config.Tokens = {
	DefaultValue = 1,
	GoldenValue = 5,
	RespawnSeconds = nil, -- tokens are one-shot per match
	DataStoreName = "NimbusClimb_v2",
	LegacyDataStoreName = "NimbusClimb_v1", -- read once to migrate v1 saves ({Tokens=n})
	AutosaveSeconds = 90,
	ClientAnimated = true, -- the client controller TokenFx spins/bobs the coins; the server does not animate them
}

----------------------------------------------------------------------
-- Pets (collectible winged companions), roulettes and items
----------------------------------------------------------------------
Config.Rarities = {
	{ Id = "Common", Order = 1, Color = Color3.fromRGB(168, 178, 194) },
	{ Id = "Uncommon", Order = 2, Color = Color3.fromRGB(104, 196, 128) },
	{ Id = "Rare", Order = 3, Color = Color3.fromRGB(88, 158, 232) },
	{ Id = "Epic", Order = 4, Color = Color3.fromRGB(176, 108, 232) },
	{ Id = "Legendary", Order = 5, Color = Color3.fromRGB(242, 182, 68) },
	{ Id = "Mythic", Order = 6, Color = Color3.fromRGB(238, 98, 140) },
	{ Id = "Secret", Order = 7, Color = Color3.fromRGB(40, 40, 52) }, -- v3: gems-only Secret roulette (phase 2)
}

Config.Pets = {
	MaxEquipped = 3, -- pets flying beside you
	MaxPerStack = 99,
	-- Perks pets can give (fractions, e.g. 0.1 = +10%). Totals are capped so nothing breaks the course physics.
	-- Pets never change run speed or jump power (courses are validated against Config.Physics).
	PerkCaps = { MaxHealth = 0.5, TokenBonus = 1.0, StaminaRegen = 0.6, CheckpointHeal = 1.0 },
}

-- Cost in cloud tokens. Odds are relative weights per rarity (pets inside a rarity are equally likely).
Config.Roulettes = {
	{
		Id = "Cloud",
		DisplayName = "Cloud Roulette",
		Price = 50,
		Color = Color3.fromRGB(120, 190, 235),
		Odds = { Common = 60, Uncommon = 28, Rare = 10, Epic = 2 },
	},
	{
		Id = "Storm",
		DisplayName = "Storm Roulette",
		Price = 250,
		Color = Color3.fromRGB(128, 120, 214),
		Odds = { Uncommon = 35, Rare = 40, Epic = 20, Legendary = 5 },
	},
	{
		Id = "Sky",
		DisplayName = "Sky Roulette",
		Price = 1000,
		Color = Color3.fromRGB(240, 180, 90),
		Odds = { Rare = 35, Epic = 45, Legendary = 17, Mythic = 3 },
	},
	{
		Id = "Celestial",
		DisplayName = "Celestial Roulette",
		Price = 5000,
		Color = Color3.fromRGB(236, 120, 170),
		Odds = { Epic = 45, Legendary = 40, Mythic = 15 },
	},
}

-- v3: Pet Index. One group per rarity; completing a group (discovering every pet in it) unlocks its reward once.
Config.Index = {
	Rewards = {
		Common = { Tokens = 50 },
		Uncommon = { Tokens = 120 },
		Rare = { Tokens = 300 },
		Epic = { Tokens = 800 },
		Legendary = { Tokens = 2000 },
		Mythic = { Tokens = 5000 },
		Secret = { Tokens = 10000 },
	},
}

-- v3: new-player tutorial guided by Nimbus, the Cloudy Dragon (steps live in shared/TutorialSteps.lua).
Config.Tutorial = {
	GiftTokens = 50, -- granted once at the "spin your first roulette" step so a new player can afford it
	FinishReward = { Tokens = 100 },
}

-- v3: pet roles and battle/economy stats (values live per pet in PetCatalog; phases 2 and 3 use them).
Config.PetStats = {
	Roles = { "Economy", "Combat" },
	-- Multiplier applied to a pet's base stats by rarity.
	RarityScale = { Common = 1, Uncommon = 1.5, Rare = 2.3, Epic = 3.5, Legendary = 5.5, Mythic = 8.5, Secret = 13 },
}

-- v3: pet elements (ARCHITECTURE_V3.md section 11). Every pet has one Element (fused hybrids can have two).
-- The wheel: each element is strong against the next one and weak against the previous one:
--   Water > Flame > Frost > Nature > Earth > Storm > Water
-- and Celestial and Shadow are each strong against the other. Anything else is neutral.
Config.Elements = {
	Order = { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" },
	Info = {
		Water = { Color = Color3.fromRGB(64, 148, 236), Blurb = "Douses Flame" },
		Flame = { Color = Color3.fromRGB(240, 108, 56), Blurb = "Melts Frost" },
		Frost = { Color = Color3.fromRGB(150, 222, 248), Blurb = "Freezes Nature" },
		Nature = { Color = Color3.fromRGB(104, 190, 86), Blurb = "Roots crack Earth" },
		Earth = { Color = Color3.fromRGB(178, 128, 80), Blurb = "Grounds Storm" },
		Storm = { Color = Color3.fromRGB(110, 128, 255), Blurb = "Electrifies Water" },
		Celestial = { Color = Color3.fromRGB(255, 212, 104), Blurb = "Shines through Shadow" },
		Shadow = { Color = Color3.fromRGB(128, 72, 178), Blurb = "Swallows Celestial light" },
	},
	-- Strong[attacker] = the defender elements it deals extra damage to.
	Strong = {
		Water = { "Flame" },
		Flame = { "Frost" },
		Frost = { "Nature" },
		Nature = { "Earth" },
		Earth = { "Storm" },
		Storm = { "Water" },
		Celestial = { "Shadow" },
		Shadow = { "Celestial" },
	},
	StrongMultiplier = 1.5, -- attacker strong against the defender
	WeakMultiplier = 0.75, -- the defender's element is strong against the attacker
}

-- Phase 2: Gems (premium currency bought with Robux). The owner creates Developer Products on the Creator Hub and
-- pastes their ids here; id 0 means "not created yet" and the product is hidden.
Config.Gems = {
	Products = {
		{ Id = 0, Gems = 100, Name = "Pouch of Gems" },
		{ Id = 0, Gems = 550, Name = "Bag of Gems" },
		{ Id = 0, Gems = 1200, Name = "Chest of Gems" },
		{ Id = 0, Gems = 6500, Name = "Vault of Gems" },
	},
	-- Gem prices for the token roulettes (a cheaper premium way to roll); the Secret roulette is gems only.
	RouletteGemPrices = { Cloud = 5, Storm = 20, Sky = 75, Celestial = 300 },
	SecretRoulette = {
		Id = "Secret",
		DisplayName = "Secret Roulette",
		GemPrice = 1500,
		Color = Color3.fromRGB(70, 90, 200),
		AllowSecret = true,
		Odds = { Mythic = 85, Secret = 15 },
	},
}

-- Developer tools (owner only). The game's owner (and the extra UserIds in Admins, and everyone while testing in
-- Roblox Studio) gets a small DEV button and chat commands: /allpets, /tokens <n>, /cash <n>, /gems <n>, /reset, /tutorial, /skiptutorial,
-- /devhelp. Nobody else can use them: the server checks every request.
Config.Dev = {
	Enabled = true, -- master switch for the developer tools
	AllowInStudio = true, -- everyone counts as a developer while playing in Roblox Studio
	Admins = {}, -- extra Roblox UserIds allowed in the live game (the game's owner is always allowed)
	StudioAutoGrant = false, -- true: in Studio, start every test with every pet and GrantTokens tokens
	GrantTokens = 1000000, -- tokens added by the "+ tokens" button and by StudioAutoGrant
	GrantCash = 1000000, -- Phase 2: Cash added by the "+ Cash" button (/cash n)
	GrantGems = 1000, -- Phase 2: Gems added by the "+ Gems" button (/gems n)
	GrantBerries = 5000, -- Phase 5: Berries added by the "+ Berries" button (/berries n)
	MaxTokensPerCommand = 100000000,
}

-- v3: 2D artwork the player uploaded to Roblox. Used for Stormfang's Pet Index banner and the Storm Altar poster.
-- The source files live in branding/ (stormfang-art.png has a transparent background). These must be IMAGE ids:
-- an upload's Decal id (here 129423539279679) fails in an ImageLabel ("Asset type does not match"); the Image id is
-- the Decal's Texture (InsertService:LoadAsset(decalId) in Studio).
Config.Art = {
	StormfangImage = "rbxassetid://101827417487186",
}

----------------------------------------------------------------------
-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 6.4-6.5, 7): sky, audio, icons, loading screen, main menu
----------------------------------------------------------------------
-- The painted sky: six Image ids (NOT Decal ids) from branding/sky/*.png, uploaded by the owner through Studio's Asset
-- Manager -> Bulk Import, then pasted here as "rbxassetid://<id>" (Bk Dn Ft Lf Rt Up by file name; left and right swapped =
-- swap the Lf and Rt ids). While any of the six is empty LightingService shows its built-in fallback sky (a pink-lavender
-- haze, a tinted cloud layer and 3000 stars). README "Phase 5: owner checklist", step 2.
-- The living sky (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md): one server-synced 20 minute loop
-- Dawn 2 -> Day 6 -> Sunset 9 -> Night 3 min, each phase blending into the next over its last Blend seconds, plus a
-- server-wide raid sky while a raid boss is up. shared/SkyCycle turns the server time into a phase and a preset; the
-- client re-applies it every Refresh s with a Tween s tween (LightingStack base). Faces stays LightingService's boot sky.
--   Themes / RaidThemes  the painted skybox (blender/sky/sky_themes.py theme id) per phase / per raid boss id; the faces
--                        are TextureIds "sky_<theme>_<Face>" (shared/SkyFaces); a theme without all six = the boot sky
--   Looks[phase | boss]  the world light per LightingStack group + Clock = { from, to } (the ClockTime walked through
--                        the phase, unwrapped: to may pass 24, the Night's 31 = 7 h next morning; on toward the next
--                        phase's from across the blend; a raid look's is fixed). The copper / indigo comes from the world light (ColorShift,
--                        Ambient, Atmosphere, clouds); TintColor stays within Floor.TintMax of white (Amber Burn shows
--                        11 of 20 minutes, the HUD and rarity colours keep their true colours)
--   Floor                the readability floor in every phase and raid (night is indigo, never black)
local skyRgb = Color3.fromRGB
Config.Sky = {
	Faces = { Bk = "", Dn = "", Ft = "", Lf = "", Rt = "", Up = "" },
	Cycle = {
		Order = { "Dawn", "Day", "Sunset", "Night" },
		Seconds = { Dawn = 120, Day = 360, Sunset = 540, Night = 180 }, -- a 1200 s (20 min) loop
		Blend = 75, -- seconds at the end of each phase that blend into the next
		Refresh = 2, -- the client re-applies the sky every Refresh s ...
		Tween = 2, -- ... with a tween this long (no per-frame work)
		EventBlend = 3, -- seconds a raid sky takes to blend in on the raid start and back out on its end
	},
	Speed = { Default = 1, Min = 0.1, Max = 120 }, -- the dev /sky speed clamp (SkySpeed attribute)
	-- the Workspace attributes server/Services/SkyService publishes (the clock: no remote traffic): Epoch = the server
	-- time at boot, Speed / Offset = the dev /sky speed and phase jump (loop seconds), Event = the raid boss id whose sky
	-- is up ("" = none), EventAt = the server time Event last changed (the clients' EventBlend s blend in / out)
	Attr = { Epoch = "SkyEpoch", Speed = "SkySpeed", Offset = "SkyOffset", Event = "SkyEvent", EventAt = "SkyEventAt" },
	EventWatch = 5, -- seconds between the server's checks that a raid sky still has its raid (a missed end never sticks)
	Themes = { Dawn = "dusk_amber", Day = "day_vivid", Sunset = "dusk_amber", Night = "night_aurora" },
	RaidThemes = { storm_titan = "storm_teal", lava_golem = "lava_obsidian", frost_wyrm = "frost_glacial", shadow_hydra = "shadow_eclipse" },
	Floor = {
		Brightness = 1.0, -- Lighting.Brightness never below
		OutdoorAmbientMin = 70, -- every OutdoorAmbient channel (0-255) never below: voxel sides still read
		TintMax = 8, -- ColorCorrection TintColor channels stay within this of 255
	},
	-- client/Controllers/SkyController (the client half; Refresh / Tween above):
	ClockJump = 0.5, -- hours: a ClockTime step bigger than this at a phase / raid change (a raid sky's fixed clock at
	-- mid-blend) is set at once, never tweened through the hours between. The cycle itself never needs it: the
	-- Sunset 17 -> Night 18.4 gap is walked across the Sunset blend and the Night runs on through midnight to Dawn's
	-- 7 h (SkyCycle.Preset); passing midnight (23.9 -> 0.1) is the one other instant set (24 h = 0 h: invisible)
	-- the battle lift: while I am in an outdoor pet battle (Config.Attr.InBattle starts with Prefix: a duel, raid,
	-- Champion Ring run or PvP; a dungeon run "D.." stays under the dungeon preset) and the look is one of Looks, the
	-- LightingStack preset Id lifts my night toward twilight over Seconds and settles back after the fight (me only)
	Lift = {
		Id = "SkyLift",
		Prefix = "B",
		Seconds = 1.5,
		Looks = { Night = true, shadow_hydra = true },
		Preset = {
			Lighting = {
				Brightness = 1.6,
				ExposureCompensation = 0.15,
				Ambient = skyRgb(116, 108, 148),
				OutdoorAmbient = skyRgb(150, 142, 192),
			},
		},
	},
	-- the lobby's lamps (LobbyBuilder pointLight() on these part names, under workspace.<Root>): their PointLight
	-- Brightness x Night under the Looks, their own value otherwise; written on a look change only
	Lamps = {
		Root = "NimbusLobby",
		Names = { LampGlass = true, LanternLight = true, StallLight = true, DomeGlow = true },
		Night = 1.6,
		Looks = { Night = true, shadow_hydra = true },
	},
	-- a few soft fireflies round the lobby trees (models named "...Tree" under workspace.<Root>) under the Looks, on
	-- High graphics only: one local folder, at most Max emitters (one per tree), the default sparkle, pale
	-- yellow-green, slow; Size / Height / Spread in studs, Lifetime / Speed = NumberRange { min, max }
	Fireflies = {
		Root = "NimbusLobby",
		Folder = "NimbusFireflies",
		Looks = { Night = true },
		Max = 6,
		Rate = 1.2,
		Color = skyRgb(212, 255, 150),
		Lifetime = { 4, 7 },
		Speed = { 0.2, 0.6 },
		Size = 0.22,
		Height = 5,
		Spread = 10,
	},
	LowCloudStep = 0.02, -- GraphicsQuality re-pushes its GfxLow cloud cap once the capped density moves this much
	Looks = {
		-- the bright pastel morning (preview A) under the Amber Burn sky: a low warm sun, pink air, peach clouds
		Dawn = {
			Clock = { 7.0, 9.0 },
			Lighting = {
				Brightness = 1.7,
				ExposureCompensation = -0.05,
				Ambient = skyRgb(112, 104, 132),
				OutdoorAmbient = skyRgb(150, 136, 162),
				ColorShift_Top = skyRgb(78, 52, 40),
				ColorShift_Bottom = skyRgb(30, 24, 48),
				EnvironmentDiffuseScale = 0.6,
				EnvironmentSpecularScale = 0.3,
			},
			Atmosphere = { Density = 0.32, Offset = 0.2, Color = skyRgb(236, 206, 214), Decay = skyRgb(246, 190, 150), Glare = 0.35, Haze = 1.4 },
			Clouds = { Cover = 0.55, Density = 0.6, Color = skyRgb(255, 228, 220) },
			ColorCorrection = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.1, TintColor = skyRgb(255, 250, 248) },
			Sky = { StarCount = 0 },
		},
		-- the long bright day = today's Phase 4 light (LightingService p4Light, sky-blue air, white clouds) under Vivid Skylands
		Day = {
			Clock = { 9.0, 16.0 },
			Lighting = {
				Brightness = 2.0,
				ExposureCompensation = -0.15,
				Ambient = skyRgb(98, 106, 132),
				OutdoorAmbient = skyRgb(132, 138, 160),
				ColorShift_Top = skyRgb(66, 50, 26),
				ColorShift_Bottom = skyRgb(14, 20, 40),
				EnvironmentDiffuseScale = 0.6,
				EnvironmentSpecularScale = 0.35,
			},
			Atmosphere = { Density = 0.28, Offset = 0.25, Color = skyRgb(178, 198, 228), Decay = skyRgb(238, 200, 170), Glare = 0.25, Haze = 1.0 },
			Clouds = { Cover = 0.5, Density = 0.6, Color = skyRgb(240, 244, 252) },
			ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.14, TintColor = skyRgb(255, 251, 247) },
			Sky = { StarCount = 0 },
		},
		-- the Copper Sunset (preview B) under Amber Burn: the copper from the sun colour, the air and its orange decay and
		-- warm peach clouds a little fuller; the sun stays at 16-17 h (short shadows), the tint stays near white
		Sunset = {
			Clock = { 16.0, 17.0 },
			Lighting = {
				Brightness = 1.6,
				ExposureCompensation = -0.1,
				Ambient = skyRgb(118, 94, 96),
				OutdoorAmbient = skyRgb(162, 128, 118),
				ColorShift_Top = skyRgb(110, 62, 24),
				ColorShift_Bottom = skyRgb(40, 24, 44),
				EnvironmentDiffuseScale = 0.55,
				EnvironmentSpecularScale = 0.4,
			},
			Atmosphere = { Density = 0.34, Offset = 0.18, Color = skyRgb(230, 170, 128), Decay = skyRgb(226, 120, 64), Glare = 0.5, Haze = 1.8 },
			Clouds = { Cover = 0.6, Density = 0.65, Color = skyRgb(255, 206, 170) },
			ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.12, TintColor = skyRgb(255, 250, 247) },
			Sky = { StarCount = 0 },
		},
		-- the short starry night (preview C) under Aurora Slumber: moonlit indigo ambient (never black), 3000 stars,
		-- sparse thin violet clouds
		Night = {
			Clock = { 18.4, 31.0 }, -- through midnight to Dawn's 7 h (= 31 unwrapped): no backward wrap at Dawn
			Lighting = {
				Brightness = 1.1,
				ExposureCompensation = 0.1,
				Ambient = skyRgb(78, 76, 124),
				OutdoorAmbient = skyRgb(104, 100, 170),
				ColorShift_Top = skyRgb(40, 46, 92),
				ColorShift_Bottom = skyRgb(24, 20, 56),
				EnvironmentDiffuseScale = 0.45,
				EnvironmentSpecularScale = 0.3,
			},
			Atmosphere = { Density = 0.3, Offset = 0.15, Color = skyRgb(96, 92, 160), Decay = skyRgb(130, 92, 170), Glare = 0, Haze = 1.2 },
			Clouds = { Cover = 0.3, Density = 0.35, Color = skyRgb(150, 128, 200) },
			ColorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.06, TintColor = skyRgb(249, 250, 255) },
			Sky = { StarCount = 3000 },
		},
		-- raid skies (BattleCatalog.Bosses ids), fixed clocks near midday so the boss and the telegraphs keep short shadows
		storm_titan = { -- Thunderhead Teal: a heavy teal storm deck
			Clock = { 13.0, 13.0 },
			Lighting = {
				Brightness = 1.4,
				ExposureCompensation = -0.05,
				Ambient = skyRgb(82, 108, 116),
				OutdoorAmbient = skyRgb(110, 142, 148),
				ColorShift_Top = skyRgb(40, 70, 72),
				ColorShift_Bottom = skyRgb(16, 36, 44),
				EnvironmentDiffuseScale = 0.5,
				EnvironmentSpecularScale = 0.4,
			},
			Atmosphere = { Density = 0.38, Offset = 0.2, Color = skyRgb(110, 156, 160), Decay = skyRgb(60, 110, 118), Glare = 0.1, Haze = 2.0 },
			Clouds = { Cover = 0.85, Density = 0.8, Color = skyRgb(130, 160, 165) },
			ColorCorrection = { Brightness = 0, Contrast = 0.14, Saturation = 0.04, TintColor = skyRgb(249, 255, 254) },
			Sky = { StarCount = 0 },
		},
		lava_golem = { -- Obsidian Furnace: dark soot air with an orange glowing decay
			Clock = { 15.5, 15.5 },
			Lighting = {
				Brightness = 1.3,
				ExposureCompensation = 0,
				Ambient = skyRgb(110, 78, 66),
				OutdoorAmbient = skyRgb(140, 96, 80),
				ColorShift_Top = skyRgb(120, 54, 16),
				ColorShift_Bottom = skyRgb(50, 18, 10),
				EnvironmentDiffuseScale = 0.5,
				EnvironmentSpecularScale = 0.45,
			},
			Atmosphere = { Density = 0.42, Offset = 0.15, Color = skyRgb(90, 64, 58), Decay = skyRgb(230, 96, 36), Glare = 0.3, Haze = 2.4 },
			Clouds = { Cover = 0.7, Density = 0.7, Color = skyRgb(96, 72, 66) },
			ColorCorrection = { Brightness = 0, Contrast = 0.14, Saturation = 0.1, TintColor = skyRgb(255, 250, 247) },
			Sky = { StarCount = 0 },
		},
		frost_wyrm = { -- Glacial Void: a bright icy cyan
			Clock = { 12.0, 12.0 },
			Lighting = {
				Brightness = 1.8,
				ExposureCompensation = -0.1,
				Ambient = skyRgb(100, 120, 148),
				OutdoorAmbient = skyRgb(140, 166, 196),
				ColorShift_Top = skyRgb(40, 60, 80),
				ColorShift_Bottom = skyRgb(20, 34, 56),
				EnvironmentDiffuseScale = 0.6,
				EnvironmentSpecularScale = 0.45,
			},
			Atmosphere = { Density = 0.36, Offset = 0.22, Color = skyRgb(186, 222, 240), Decay = skyRgb(120, 190, 230), Glare = 0.2, Haze = 1.6 },
			Clouds = { Cover = 0.65, Density = 0.7, Color = skyRgb(220, 240, 255) },
			ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.04, TintColor = skyRgb(248, 252, 255) },
			Sky = { StarCount = 0 },
		},
		shadow_hydra = { -- Eclipse Shadow: a violet-grey eclipse, a few stars through the dim
			Clock = { 12.0, 12.0 },
			Lighting = {
				Brightness = 1.1,
				ExposureCompensation = 0.05,
				Ambient = skyRgb(90, 82, 110),
				OutdoorAmbient = skyRgb(118, 108, 146),
				ColorShift_Top = skyRgb(60, 44, 84),
				ColorShift_Bottom = skyRgb(24, 18, 40),
				EnvironmentDiffuseScale = 0.5,
				EnvironmentSpecularScale = 0.35,
			},
			Atmosphere = { Density = 0.4, Offset = 0.18, Color = skyRgb(112, 100, 136), Decay = skyRgb(90, 64, 130), Glare = 0.15, Haze = 1.8 },
			Clouds = { Cover = 0.6, Density = 0.6, Color = skyRgb(120, 108, 140) },
			ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0, TintColor = skyRgb(251, 249, 255) },
			Sky = { StarCount = 1500 },
		},
	},
}

-- Music and sounds: the player's ORIGINAL audio (nimbus-climb/audio/, audio/README.md), uploaded by the owner's keyed
-- session with tools/upload_assets.py --audio into shared/AudioIds.lua (audio key -> number; docs/phase6/OWNER_UPLOAD.md
-- section 6b). Config.Audio.Keys names the AudioIds key of every sound; Music / Sfx / Ambient hold the ids that exist
-- (numbers; a missing key = that sound is silent, no error, no warning). client/SoundFx turns them into Sounds:
--   Music[context]  "Lobby" | "Battle" | "Dungeon", looped, crossfaded (SoundFx.Music / SetLayer), at the Music setting
--   Sfx[name]       one-shots (SoundFx.Play): Click Confirm Error Reward Whoosh, Inhale (a Special's charge, its pitch
--                   rising 0.75 -> 1.35 in BattleController) and Shatter (a broken charge), at the Sfx setting
--                   + audio wave 2 (audio/README.md, .superpowers/audio-pitch/wave2/wiring-plan.md): the element
--                   hits Hit<Element>, Crit, KO (4 files in rotation: Variants.KO), Dash, Parry, PortalEnter /
--                   PortalArrive, StationBuild, HouseTier, DialogOpen / DialogBlip / DialogNext, TutorialStep, the
--                   roulette's SpinStart / SpinTick / SpinLand, RevealCommon / RevealRare / RevealLegendary and the NPC
--                   voices Npc<Name>Greet / Hmm / Pleased (NpcController)
--   Ambient[name]   positional loops (SoundFx.Positional): the Champion Ring's CrowdCheer (Sfx setting) and DrumLoop
--                   (Music setting) at the ring pocket's crowd stand (client/Controllers/RingAmbience); the lobby
--                   fountain's water (Fountain = key FountainLoop: no approved take yet, so silent until one is)
-- Volume[key] is THE one place for slot volumes (0..1, times the player's Music / Sfx setting / 10): music lower than
-- the effects (UnderMusic: the frequent quiet ticks / hits allowed at or under it); the ring's crowd and drums under
-- the music (and they fade out with distance). Pitch[key] = { lo, hi } PlaybackSpeed range of a one-shot (default
-- 0.95-1.05); MinGap[key] = seconds a key waits before it plays again; Caps = at most Max plays of a key prefix per
-- Window seconds (the hits of a raid); Variants[name] = the files a name rotates through (never one twice in a row).
local AudioIds = require(script.Parent.AudioIds)
local AUDIO_KEYS = {
	Music = { Lobby = "MusicLobby", Battle = "MusicBattle", Dungeon = "MusicDungeon" },
	Sfx = { Click = "Click", Confirm = "Confirm", Error = "Error", Reward = "Reward", Whoosh = "Whoosh", Inhale = "Inhale", Shatter = "Shatter" },
	Ambient = { CrowdCheer = "CrowdCheer", DrumLoop = "DrumLoop", Fountain = "FountainLoop" },
}
-- audio wave 2: one-shots under their own key names
local AUDIO_WAVE2 = {
	"HitWater", "HitFlame", "HitFrost", "HitNature", "HitEarth", "HitStorm", "HitCelestial", "HitShadow", "Crit",
	"KO", "KO2", "KO3", "KO4", "Dash", "Parry", "PortalEnter", "PortalArrive", "StationBuild", "HouseTier",
	"DialogOpen", "DialogBlip", "DialogNext", "TutorialStep", "SpinStart", "SpinTick", "SpinLand",
	"RevealCommon", "RevealRare", "RevealLegendary",
}
-- the NPC voices (wordless, one voice per NPC): Npc<Name><Kind>, <Name> = the NpcDialog Id in CamelCase
local AUDIO_NPCS = { "SparkyFox", "CaptainPenguin", "GrannyOwl", "CoachCorgi", "MayorPanda", "ProfessorAxolotl" }
local AUDIO_NPC_KINDS = { "Greet", "Hmm", "Pleased" }
-- whose recorded voice an NPC uses (default: its own). The owner swapped Coach Corgi's and Granny Owl's voices (2026-10-30)
local AUDIO_NPC_VOICE = { CoachCorgi = "GrannyOwl", GrannyOwl = "CoachCorgi" }
for _, key in ipairs(AUDIO_WAVE2) do
	AUDIO_KEYS.Sfx[key] = key
end
for _, npc in ipairs(AUDIO_NPCS) do
	for _, kind in ipairs(AUDIO_NPC_KINDS) do
		AUDIO_KEYS.Sfx["Npc" .. npc .. kind] = "Npc" .. (AUDIO_NPC_VOICE[npc] or npc) .. kind
	end
end
Config.Audio = {
	Keys = AUDIO_KEYS,
	Music = {},
	Sfx = {},
	Ambient = {},
	Volume = {
		MusicLobby = 0.45,
		MusicBattle = 0.5,
		MusicDungeon = 0.45,
		Click = 0.6,
		Confirm = 0.8,
		Error = 0.7,
		Reward = 0.8,
		Whoosh = 0.7,
		Inhale = 0.8,
		Shatter = 0.85,
		CrowdCheer = 0.3,
		DrumLoop = 0.35,
		FountainLoop = 0.45,
		-- wave 2 (starting values from the wiring plan: tune by ear in Studio). The hits are frequent: under the music
		HitFlame = 0.45,
		HitFrost = 0.42,
		HitShadow = 0.38,
		HitWater = 0.38,
		HitEarth = 0.38,
		HitStorm = 0.36,
		HitNature = 0.34,
		HitCelestial = 0.28,
		Crit = 0.55,
		KO = 0.7,
		KO2 = 0.7,
		KO3 = 0.7,
		KO4 = 0.7,
		Dash = 0.6,
		Parry = 0.8,
		PortalEnter = 0.65,
		PortalArrive = 0.6,
		StationBuild = 0.6,
		HouseTier = 0.85,
		DialogOpen = 0.55,
		DialogBlip = 0.3,
		DialogNext = 0.5,
		TutorialStep = 0.7,
		SpinStart = 0.65,
		SpinTick = 0.4,
		SpinLand = 0.75,
		RevealCommon = 0.7,
		RevealRare = 0.75,
		RevealLegendary = 0.8,
		-- (the NPC voices: 0.6 each, set below)
	},
	-- the frequent / quiet keys that may sit at or under the music (every other effect sits above it)
	UnderMusic = {
		HitFlame = true, HitFrost = true, HitShadow = true, HitWater = true, HitEarth = true, HitStorm = true,
		HitNature = true, HitCelestial = true, SpinTick = true, DialogBlip = true, DialogNext = true,
	},
	-- PlaybackSpeed range of a one-shot (not listed: 0.95-1.05). Tuned motifs (the reveals) never shift
	Pitch = {
		HitFlame = { 0.93, 1.07 },
		HitFrost = { 0.93, 1.07 },
		HitShadow = { 0.93, 1.07 },
		HitWater = { 0.93, 1.07 },
		HitEarth = { 0.92, 1.06 },
		HitStorm = { 0.93, 1.07 },
		HitNature = { 0.93, 1.07 },
		HitCelestial = { 0.96, 1.04 },
		Crit = { 0.97, 1.03 },
		KO = { 0.97, 1.03 },
		KO2 = { 0.97, 1.03 },
		KO3 = { 0.97, 1.03 },
		KO4 = { 0.97, 1.03 },
		Dash = { 0.95, 1.05 },
		Parry = { 1, 1 },
		PortalEnter = { 1, 1 },
		PortalArrive = { 1, 1 },
		StationBuild = { 0.95, 1.05 },
		HouseTier = { 1, 1 },
		DialogOpen = { 1, 1 },
		DialogBlip = { 0.96, 1.04 },
		DialogNext = { 1, 1 },
		TutorialStep = { 1, 1 },
		SpinStart = { 1, 1 },
		SpinTick = { 0.98, 1.02 },
		SpinLand = { 1, 1 },
		RevealCommon = { 1, 1 },
		RevealRare = { 1, 1 },
		RevealLegendary = { 1, 1 },
	},
	-- seconds a key waits before it plays again (a raid lands 20+ hits a second; the typewriter 50 letters a second)
	MinGap = {
		HitWater = 0.06, HitFlame = 0.06, HitFrost = 0.06, HitNature = 0.06, HitEarth = 0.06, HitStorm = 0.06,
		HitCelestial = 0.06, HitShadow = 0.06,
		Crit = 0.15,
		KO = 0.25, -- (the whole rotation: Variants share their name's gap)
		SpinTick = 0.025,
		DialogBlip = 0.045,
		Error = 1.0,
		StationBuild = 0.15, -- (a bought station and the next pad pop together: one pop)
		PortalEnter = 1.0,
	},
	-- at most Max plays of the keys starting with Prefix per Window seconds (the hits of a crowded raid)
	Caps = {
		{ Prefix = "Hit", Max = 8, Window = 0.25 },
	},
	-- a name that rotates through several files: never the same one twice in a row (SoundFx.PlayVariant)
	Variants = {
		KO = { "KO", "KO2", "KO3", "KO4" },
	},
	-- the NPC voices (NpcController): at most one per Voice.Gap seconds per NPC, a new one stops the old
	Voice = { Volume = 0.6, Pitch = { 0.98, 1.02 }, Gap = 1.5, GreetDelay = 0.12 },
	-- which player setting scales a key (ClientSettings "Music" / "Sfx"); a key not listed follows its group (Music ->
	-- "Music", Sfx / Ambient -> "Sfx")
	Setting = { DrumLoop = "Music" },
	Fade = 1.2, -- seconds of the music crossfade
	Resume = { Lobby = true, Dungeon = true }, -- these tracks continue where they stopped (Battle starts from its top)
	-- positional loops: full volume within Min studs, InverseTapered down to silence at Max (ring pockets are 380 apart)
	Positional = {
		CrowdCheer = { Min = 30, Max = 140 },
		DrumLoop = { Min = 24, Max = 120 },
		FountainLoop = { Min = 10, Max = 70 }, -- (FountainFx K.SOUND_RANGE)
	},
}
for _, npc in ipairs(AUDIO_NPCS) do
	for _, kind in ipairs(AUDIO_NPC_KINDS) do
		local key = "Npc" .. npc .. kind
		Config.Audio.Volume[key] = Config.Audio.Voice.Volume
		Config.Audio.Pitch[key] = { Config.Audio.Voice.Pitch[1], Config.Audio.Voice.Pitch[2] }
	end
end
for group, keys in pairs(AUDIO_KEYS) do
	for name, key in pairs(keys) do
		local id = AudioIds[key]
		if type(id) == "number" and id > 0 and id == math.floor(id) then
			Config.Audio[group][name] = id
		end
	end
end

-- Menu icons (optional): the tiles use emoji glyphs; Config.Icons[tileId] = "rbxassetid://<id>" replaces one with an
-- image (NeonKit.Icon). Empty table = glyphs everywhere.
Config.Icons = {}

-- Phase 6: the Blender models. Mesh key -> Roblox Model asset id, written only by tools/upload_assets.py into
-- shared/MeshIds.lua. Empty = every model uses its Part build. See README "Phase 6" and ARCHITECTURE_V3.md "## Phase 6".
Config.MeshAssets = require(script.Parent.MeshIds)

-- The loading screen (src/first/LoadingScreen.client.lua, ReplicatedFirst): SKIP appears after SkipAfter seconds, the
-- screen finishes by itself at 100% or after MaxSeconds.
Config.Loading = {
	SkipAfter = 6,
	MaxSeconds = 25,
}

-- The main menu BEFORE spawning (7.2, judge M7): the server holds the character until the client's PLAY (remote MenuPlay)
-- or FallbackSeconds; the camera orbits the Gate Court meanwhile. Enabled = false restores today's behaviour in one line
-- (the character spawns at once on join). On since the wave-3 gate (the smoke worlds switch it off in their common boot).
Config.MainMenu = {
	Enabled = true,
	OrbitRadius = 90,
	OrbitHeight = 38,
	OrbitPeriod = 60, -- seconds per orbit
	FallbackSeconds = 90, -- the server spawns the character after this even without MenuPlay (Y13)
}

return Config
