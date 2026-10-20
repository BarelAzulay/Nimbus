-- UpdateNotes: what the UPDATES panel of the main menu shows, the credits and the loading-screen tips
-- (ARCHITECTURE_V3.md "Phase 5 build contract" 7.1 / 7.2; lead W0). Pure data, read by the client only.
--
--   UpdateNotes.Latest   -> 6   the newest note's Version; the menu shows a "NEW" badge while Settings.SeenNotes < Latest
--                                and opening UPDATES sends SettingsSet("SeenNotes", Latest)
--   UpdateNotes.Notes    -> { { Version, Title, Lines = { ... } }, ... }  newest first
--   UpdateNotes.Credits  -> { line, ... }
--   UpdateNotes.Tips     -> { 12 short tips }  the loading screen rotates one every 5 s (LoadingScreen.client.lua)
-- Texts are for kids: short lines, plain words, no jargon. Plain Lua 5.1-compatible syntax only.

local UpdateNotes = {}

UpdateNotes.Latest = 6

UpdateNotes.Notes = {
	{
		Version = 6,
		Title = "The Cute Blocks Update",
		Lines = {
			"The bright, cute look is back, with smaller blocks and more detail.",
			"New hand-made 3D models for every pet, evolved pet, boss, gate, home and island arrive one by one.",
			"Evolved pets shine: sparkles in their colours and a soft glow. Second evolutions glow brighter and pulse.",
			"A magic swirl spins inside every gate, with a glowing rim and tiny lightning sparks.",
			"No Home gate in the lobby: tap Home, then Go home. No home yet? Tap Claim a home.",
			"Nothing is lost: pets, levels, Cash, Gems, Tokens and homes stay the same.",
		},
	},
	{
		Version = 5,
		Title = "The Big Sky Update",
		Lines = {
			"Fight with one pet and bring two helpers. You move your fighter: ATTACK, ELEMENT, SPECIAL and DASH.",
			"The Dungeon: 12 floors of 4 rooms, alone or with up to 3 friends. Every room pays Cash, Tokens and XP.",
			"One portal per mode in the new Gate Court: Obby, Dungeon, Champion Ring, Arena, Storm Altar. Tap Home to go home.",
			"Pick your obby level at the Obby gate. Beat a level to unlock the next one.",
			"Your home got simpler: one Berry Farm, a roaming Pet Garden and three decorations.",
			"Garden pets roam your yard, eat at the Food Bowl and drop Cloud Cash. Walk over it to scoop!",
			"Berries fill your Berry Basket. At the Food Machine, ONE button: Feed. No Cash for food anymore.",
			"Evolved pets look evolved everywhere, and the level bonus grows x1.5 and x1.875 after evolving.",
			"More stamina: 150, it refills faster, and four dashes from full.",
			"A new look: stone and wood under a pink and purple cloud sky, neon menus, a loading screen and a main menu with settings.",
			"Nothing is lost: pets, levels, Cash, Gems, Tokens, homes and records carry over. Old Trial clears became dungeon floors.",
		},
	},
	{
		Version = 4,
		Title = "The Coin Garden Update",
		Lines = {
			"Garden pets make Cloud Cash: scoop their coin piles.",
			"Feed pets at the Food Machine, train them at the Training Place, and EVOLVE them at level 20 and 50.",
			"The Champion Ring: beat round after round of champions.",
		},
	},
	{
		Version = 3,
		Title = "The Battle Arena Update",
		Lines = {
			"The Battle Arena island: boss raids, duels and battle teams.",
			"Pets have elements: Water beats Flame, Flame beats Frost, and so on.",
		},
	},
	{
		Version = 2,
		Title = "The Sky Homes Update",
		Lines = {
			"Claim a home in the sky, build it up with Cash and go for Prestige.",
			"Fuse two pets into a new one at the Fusion Machine.",
		},
	},
}

-- The README's owner checklist tells the owner to put their name on the first line.
UpdateNotes.Credits = {
	"Game by the Nimbus Climb owner",
	"Built with Claude",
}

UpdateNotes.Tips = {
	"Your two helpers float behind your fighter. Each has one BUFF button.",
	"SWAP puts a helper in as the fighter. Three pets, three lives.",
	"Water beats Flame, Flame beats Frost, Frost beats Nature, Nature beats Earth, Earth beats Storm, Storm beats Water.",
	"Support pets heal, shield or boost. They are best as helpers.",
	"Every level adds +10% to a pet. Evolving makes that bonus grow faster.",
	"Beat an obby level to unlock the next one at the Obby gate.",
	"Dungeon rooms pay everyone who fought in them. Standing still pays nothing.",
	"Clear a dungeon floor for the first time for big Tokens and Gems.",
	"Garden pets drop Cloud Cash in your yard. Walk over it to scoop it up.",
	"Berries go into your Berry Basket. Feed them to your pets at the Food Machine.",
	"DASH costs stamina outside a battle, but inside a battle it is free.",
	"Tap Home, then Go home: a magic portal takes you and your pets home.",
}

return UpdateNotes
