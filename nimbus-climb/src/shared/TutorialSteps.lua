-- TutorialSteps: the new-player tutorial, told by Nimbus the Cloudy Dragon (ARCHITECTURE_V3.md section 4 and the
-- Phase 2 "Tutorial" paragraph). Data only: TutorialService (server) walks a player through these steps in order and
-- TutorialController (client) shows them in the side panel.
--
-- Chapters. Saved progress is the step INDEX (Profile.Tutorial.Step), so steps are only ever APPENDED: chapter 1
-- (steps 1-9, the Phase 1 basics) keeps its indices, chapter 2 (the tycoon home, Phase 2) follows, Phase 3 appends
-- the arena (chapter 3, Phase 3: go to the Battle Arena, set a battle team, win Trial 1, see a Boss Raid) and Phase 4
-- appends chapter 4 (pets make the money: train a pet, win a Champion Ring round, use the home portal). Phase 4 also
-- rewrote chapter 2 IN PLACE (claim, garden, coins, machine, feed: still five steps at indices 10-14, so a saved
-- index keeps its place). A player who finished an earlier chapter resumes at the first step of the next one when it
-- ships (TutorialService: a stored Done tutorial whose Step points into a later chapter carries on from there; a
-- finished Phase 3 tutorial stored Step 19 = chapter 4's first step).
--
-- Step fields
--   Id          unique step id inside its chapter (chapter 4's "portal" shares its id with chapter 1's: IndexOf keeps
--               the FIRST index of an id; use the step index / ChapterStart to tell them apart)
--   Chapter     1 (basics), 2 (home), 3 (pet battles) or 4 (pets make the money); defaults to 1
--   ChapterEnd  true on the last step of a chapter: completing it pays the chapter's reward once
--               (chapter 1: Config.Tutorial.FinishReward; chapters 2, 3 and 4: TutorialService's rewards)
--   Title       short headline shown above the text
--   Text        what Nimbus says (short, friendly). Placeholders filled in by TutorialService:
--               {GiftTokens} = Config.Tutorial.GiftTokens, {FinishTokens} = Config.Tutorial.FinishReward.Tokens,
--               {RaidMinutes} = minutes between two Boss Raids (BattleCatalog.Events; the raid step builds its text from
--               BattleCatalog when this module loads, so it needs no placeholder)
--   Target      nil, or where the guide arrow points:
--                 { Kind = "Spot" }                     the player's own home plot (SpotIndex attribute)
--                 { Kind = "Spot", Gate = true }        the gate of the plot the player should claim: their claimed
--                                                       plot, else their last plot when free, else the nearest free
--                                                       plot (SpotService.SuggestSpot)
--                 { Kind = "Spot", Pad = "Press1" }     a buy pad on the player's own plot (Pad_<StationId>)
--                     + Path = true                     ...or the next pad on the way to it (its prerequisites)
--                     + Station = "Gym"                 ...or that station once it is built
--                 { Kind = "Spot", Station = "Kitchen", Food = true }   the Food Machine (its Hopper) once it is built,
--                                                       else the pads on the way to it
--                 { Kind = "Spot", Pad = "Garden", Station = "Garden", GardenSpot = true }   no pet: the Shop; the free
--                                                       Pet Garden pad until it is built; then the first empty open
--                                                       garden place (else the Pets menu button)
--                 { Kind = "Spot", Station = "Garden", Coins = true }   the fullest rainbow-coin pile of the garden
--                                                       (TycoonService.Piles), else the Garden itself
--                 { Kind = "Shop" }                     the roulette machines (Roulette_<first roulette id>)
--                 { Kind = "Roulette", Id = "Cloud" }   model Roulette_<Id> under workspace.NimbusLobby
--                 { Kind = "Portal", Id = "Easy" }      model Portal_<Id> under workspace.NimbusLobby
--                 { Kind = "Menu", Id = "Pets" }        the menu button MenuButton_<Id> ("Team": the battle team tile)
--                 { Kind = "Arena", Place = "Gate" }    Phase 3, resolved by TutorialService from ArenaInfo and sent as
--                                                       { Kind = "Spot", Position, Label }: "Gate" = the arena's arrival
--                                                       forum (ArenaInfo.Spawn), "Trials" = the Trial Portal
--                                                       (ArenaInfo.TrialPortal), "Floor" = the colosseum floor (raids),
--                                                       "Ring" = the Champion Ring portal (ArenaInfo.RingPortal)
--               Label (optional) names the target on the floating sign above the arrow. TutorialService resolves
--               the home targets on the server and sends Kind "Spot" + Position (or Kind "Menu") to the client.
--   CompleteOn  "Next"         the player presses Next (client event)
--               "NearSpot"     within 14 studs of the player's own SpotInfo.Center (server poll; kept for old data)
--               "Claimed"      the player owns a home plot (claimed with E at a gate)
--               "Built"        the home has the station `Station` at level 1 or more
--               "Collected"    (Phase 2, retired: no step uses it; a step that still did would pass at once)
--               "Fed"          the player fed a pet (PetCareService.Fed: the Food Machine / the Pets panel)
--               "ShopOpened"   the Shop window opened (client event)
--               "Rolled"       a roulette spin succeeded (PetService.Rolled)
--               "Equipped"     the player equips a pet / opens Pets with a pet equipped
--               "IndexOpened"  the Pet Index window opened (client event)
--               "MatchStarted" the player's InMatch attribute turned true
--               "MatchEnded"   the player's InMatch attribute turned false again
--               "ArenaReached" the player stands in the Battle Arena (ArenaBuilder.InArena, server poll)
--               "TeamSet"      the active battle team holds the player's pets: min(3, pets that can join a team)
--                              (DataService.TeamsChanged / ActiveTeamKeys / FieldableKeys)
--               "TrialWon"     Trial level 1 is cleared (BattleService.BattleEnded / Battle.TrialCleared)
--               "RaidSeen"     the player joined a Boss Raid, or stood in the arena while one was running
--               "GardenPlaced" (Phase 4) a pet sits in an open place of the Pet Garden (Home.Garden)
--               "CoinsScooped" the player scooped rainbow coins (TycoonService.CoinsScooped; a home that already has
--                              the Food Machine passes at once)
--               "TrainingStarted" a pet trains or has trained (PetCareService.TrainingStarted / PetGrowth job or rank)
--               "RingWon"      a Champion Ring round was won (BattleService.BattleEnded Mode "Ring", or Ring.Best >= 1)
--               "PortalUsed"   the player walked through their home portal (TycoonService.PortalUsed)
--   Station     the station id a "Built" step waits for
--   Gift        true: entering this step grants Config.Tutorial.GiftTokens once (Profile.Tutorial.Gifted)
--   Hint        short objective line shown under the text while the step waits for an action (TutorialService
--               may send a more precise one, e.g. the next pad on the way to the Kitchen)
--   Button      label of the Next button (CompleteOn = "Next" only)
--
-- Plain Lua 5.1-compatible syntax only.

local TutorialSteps = {}

-- the level of the first evolution for the chapter 2 text (PetCatalog.EvolutionLevels[1]; 20 without it)
local EVOLVE_LEVEL = 20
do
	local module = script.Parent:FindFirstChild("PetCatalog")
	if module then
		local ok, catalog = pcall(require, module)
		local levels = ok and type(catalog) == "table" and catalog.EvolutionLevels or nil
		if type(levels) == "table" and tonumber(levels[1]) then
			EVOLVE_LEVEL = math.floor(tonumber(levels[1]))
		end
	end
end

-- minutes between two Boss Raids for the chapter 3 text (BattleCatalog.Events; data read once, 20 without it)
local RAID_MINUTES = 20
do
	local module = script.Parent:FindFirstChild("BattleCatalog")
	if module then
		local ok, catalog = pcall(require, module)
		local events = ok and type(catalog) == "table" and catalog.Events or nil
		local first = type(events) == "table" and type(events.Schedule) == "table" and events.Schedule[1] or nil
		if type(first) == "table" and tonumber(first.EveryMinutes) then
			RAID_MINUTES = math.floor(tonumber(first.EveryMinutes))
		end
	end
end

TutorialSteps.Guide = {
	Name = "Nimbus",
	Title = "the Cloudy Dragon",
	PetId = "cloudy_dragon", -- PetCatalog id of the portrait in the side panel
}

TutorialSteps.Steps = {
	----------------------------------------------------------------------------------------------- chapter 1: basics
	{
		Id = "welcome",
		Chapter = 1,
		Title = "Hi there, climber!",
		Text = "I'm Nimbus, the Cloudy Dragon! Welcome to my sky village. Stick with me and I'll show you around. It's quick, promise!",
		Target = nil,
		CompleteOn = "Next",
		Button = "Let's go!",
	},
	{
		-- (Phase 2: homes are claimed with E at their gate, so this step now leads to a free gate)
		Id = "home",
		Chapter = 1,
		Title = "Your Home Plot",
		Text = "Every climber can have a home plot on the big ring! Follow my golden arrow to a free gate and press E to make it yours.",
		Target = { Kind = "Spot", Gate = true, Label = "Free home" },
		CompleteOn = "Claimed",
		Hint = "Press E at a free gate",
	},
	{
		Id = "shop",
		Chapter = 1,
		Title = "The Cloud Shop",
		Text = "Next stop: the Cloud Shop! Follow the arrow to the roulette machines and open one. The Shop button works too!",
		Target = { Kind = "Shop", Label = "Cloud Shop" },
		CompleteOn = "ShopOpened",
		Hint = "Open the shop",
	},
	{
		Id = "spin",
		Chapter = 1,
		Title = "Your First Pet",
		Text = "Here are {GiftTokens} Cloud Tokens, my treat! Spin the Cloud Roulette to hatch your very first pet buddy.",
		Target = { Kind = "Roulette", Id = "Cloud", Label = "Cloud Roulette" },
		CompleteOn = "Rolled",
		Gift = true,
		Hint = "Spin a roulette",
	},
	{
		Id = "equip",
		Chapter = 1,
		Title = "Pick a Buddy",
		Text = "Aww, a new friend! Open Pets and equip your buddy so it follows right behind you. Pets give handy perks!",
		Target = { Kind = "Menu", Id = "Pets" },
		CompleteOn = "Equipped",
		Hint = "Tap the glowing Pets button",
	},
	{
		Id = "index",
		Chapter = 1,
		Title = "The Pet Index",
		Text = "Every pet you find lands in the Pet Index. Take a peek! Collect a whole rarity group for a big reward.",
		Target = { Kind = "Menu", Id = "Index" },
		CompleteOn = "IndexOpened",
		Hint = "Tap the glowing Index button",
	},
	{
		Id = "portal",
		Chapter = 1,
		Title = "Time to Climb!",
		Text = "Now the fun part! Step into the Easy portal and wait for the countdown. Friends can hop in with you.",
		Target = { Kind = "Portal", Id = "Easy", Label = "Easy Portal" },
		CompleteOn = "MatchStarted",
		Hint = "Stand in the Easy portal",
	},
	{
		Id = "finish",
		Chapter = 1,
		Title = "Up, Up and Away!",
		Text = "Hop from cloud to cloud, grab the shiny tokens and reach the finish. Checkpoints keep your progress. You've got this!",
		Target = nil,
		CompleteOn = "MatchEnded",
		Hint = "Reach the finish",
	},
	{
		Id = "done",
		Chapter = 1,
		ChapterEnd = true,
		Title = "You're a Natural!",
		Text = "That's the basics, climber! Here are {FinishTokens} Cloud Tokens to celebrate. Next up: your very own home!",
		Target = nil,
		CompleteOn = "Next",
		Button = "Collect!",
	},
	------------------------------------------------------------------------------------- chapter 2: the tycoon home
	{
		Id = "claim",
		Chapter = 2,
		Title = "Claim Your Home",
		Text = "Homes are the heart of Nimbus Village! Walk up to a free gate and press E. The plot is yours for as long as you play.",
		Target = { Kind = "Spot", Gate = true, Label = "Free home" },
		CompleteOn = "Claimed",
		Hint = "Press E at a free gate",
	},
	{
		-- (Phase 4: was "press", the first Cloud Press; the index stays 11)
		Id = "garden",
		Chapter = 2,
		Title = "Your Pet Garden",
		Text = "Your pets make the money! Build your free Pet Garden, then press E on a garden spot to put a pet in it.",
		Target = { Kind = "Spot", Pad = "Garden", Station = "Garden", GardenSpot = true, Label = "Pet Garden" },
		CompleteOn = "GardenPlaced",
		Hint = "Put a pet in your Pet Garden",
	},
	{
		-- (Phase 4: was "collect", the Collector)
		Id = "coins",
		Chapter = 2,
		Title = "Rainbow Coins!",
		Text = "Garden pets eat and pop out rainbow coins. Only you can scoop yours: just walk over them!",
		Target = { Kind = "Spot", Station = "Garden", Coins = true, Label = "Your coins" },
		CompleteOn = "CoinsScooped",
		Hint = "Walk over your rainbow coins",
	},
	{
		-- (Phase 4: was "kitchen"; the station id stays Kitchen, its name is the Food Machine)
		Id = "machine",
		Chapter = 2,
		Title = "The Food Machine",
		Text = "Spend coins on the glowing pads: plants make bigger coins! Follow my arrow and build the Food Machine.",
		Target = { Kind = "Spot", Pad = "Kitchen", Path = true, Label = "Food Machine pad" },
		CompleteOn = "Built",
		Station = "Kitchen",
		Hint = "Build the Food Machine",
	},
	{
		Id = "feed",
		Chapter = 2,
		ChapterEnd = true,
		Title = "Snack Time!",
		Text = "Press E at the Food Machine, pick a pet and press Feed. Fed pets level up, and at level " .. EVOLVE_LEVEL
			.. " they EVOLVE!",
		Target = { Kind = "Spot", Station = "Kitchen", Food = true, Label = "Food Machine" },
		CompleteOn = "Fed",
		Hint = "Feed a pet at the Food Machine",
	},
	-------------------------------------------------------------------------------------- chapter 3: pet battles
	{
		Id = "arena",
		Chapter = 3,
		Title = "The Battle Arena",
		Text = "Your pets are strong enough to battle now! Follow my arrow over the bridge to the Battle Arena.",
		Target = { Kind = "Arena", Place = "Gate", Label = "Battle Arena" },
		CompleteOn = "ArenaReached",
		Hint = "Walk into the Battle Arena",
	},
	{
		Id = "team",
		Chapter = 3,
		Title = "Pick Your Team",
		Text = "Battles need a team! Tap Team and put your pets in your team (up to 3; a 4th slot opens at Prestige 1). Same-element pets power each other up!",
		Target = { Kind = "Menu", Id = "Team" },
		CompleteOn = "TeamSet",
		Hint = "Tap the glowing Team button and put your pets in your team",
	},
	{
		Id = "trial",
		Chapter = 3,
		Title = "Your First Trial",
		Text = "Press E at the Trial Portal and start Level 1. Tap ATTACK, RETREAT when it gets rough, SPECIAL when its gold bar is full!",
		Target = { Kind = "Arena", Place = "Trials", Label = "Trial Portal" },
		CompleteOn = "TrialWon",
		Hint = "Win Trial level 1",
	},
	{
		Id = "raid",
		Chapter = 3,
		ChapterEnd = true,
		Title = "Boss Raids!",
		Text = "Every " .. RAID_MINUTES .. " minutes a giant boss stomps into the colosseum and everyone fights it together. Be there!",
		Target = { Kind = "Arena", Place = "Floor", Label = "Boss Raid floor" },
		CompleteOn = "RaidSeen",
		Hint = "Join or watch a Boss Raid",
	},
	---------------------------------------------------------------------- chapter 4: pets make the money (Phase 4)
	{
		Id = "train",
		Chapter = 4,
		Title = "Training Time",
		Text = "Your Training Place makes pets stronger: pick a pet and a skill. Training pets rest at home until they're done!",
		Target = { Kind = "Spot", Pad = "Gym", Station = "Gym", Path = true, Label = "Training Place" },
		CompleteOn = "TrainingStarted",
		Hint = "Start training a pet",
	},
	{
		Id = "ring",
		Chapter = 4,
		Title = "The Champion Ring",
		Text = "Claim your home, then press E at the Champion Ring portal on the plaza. Beat the champion: Cash and XP!",
		Target = { Kind = "Arena", Place = "Ring", Label = "Champion Ring" },
		CompleteOn = "RingWon",
		Hint = "Win a round in the Champion Ring",
	},
	{
		Id = "portal",
		Chapter = 4,
		ChapterEnd = true,
		Title = "Portal Home",
		Text = "Tap Home, then Go home: a magic portal opens just for you and your pets. Hop in!",
		Target = { Kind = "Menu", Id = "Home", Label = "Home" },
		CompleteOn = "PortalUsed",
		Hint = "Tap Home, then Go home",
	},
}

-- Id -> index lookup (the FIRST step with that id: chapter 1's "portal" is 7, chapter 4's is ChapterStart[4] + 2) and
-- the first step of every chapter (data, built once).
TutorialSteps.IndexOf = {}
TutorialSteps.ChapterStart = {}
for index, step in ipairs(TutorialSteps.Steps) do
	if not TutorialSteps.IndexOf[step.Id] then
		TutorialSteps.IndexOf[step.Id] = index
	end
	local chapter = step.Chapter or 1
	if not TutorialSteps.ChapterStart[chapter] then
		TutorialSteps.ChapterStart[chapter] = index
	end
end

return TutorialSteps
