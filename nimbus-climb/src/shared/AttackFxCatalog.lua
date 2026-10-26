-- AttackFxCatalog: the look of every pet attack effect (docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md,
-- plan docs/superpowers/plans/2026-10-23-pet-attack-vfx.md Task 4). The single source of every effect's data: the
-- AttackFx engine (client) and BattleController only PLAY what Resolve returns. Pure data + pure functions: no
-- Instances, no services, no yields; safe on the server and the client. Plain Lua 5.1-compatible syntax only.
--
-- Tables a designer tunes (each one mirrors a spec section):
--   Bands / Sizes / StageBonus / SizeCap        "Rarity ladder": 4 bands (Common+Uncommon, Rare+Epic, Legendary+Mythic,
--                                               Secret), sizes 1.0 .. 1.4, Evolved +5% / Evolved II +10%, hard cap 1.4
--   CoreLook[band]                              the core's intensity and shape per band (plain -> hot inner core ->
--                                               blazing + upgraded shape -> white plasma with a colour-shifting rim)
--   Ladder                                      the layers each rarity ADDS (every rarity keeps all the layers below it)
--   LayerSlots[id]                              the layer templates the ladder names ("$Burst" etc. = the element's sheet)
--   Elements[element]                           "Elements: normal attacks": palette, melee swipe, ranged projectile +
--                                               trail, impact sheets, the "alive" detail, the Storm special's rain,
--                                               Tints[layerId]? (an explicit colour for a shared layer, like a signature's;
--                                               a signature's own Tints win)
--   Shapes[shape]                               the 8 element attacks (Cone / Circle / Line of BattleCatalog.ElementAttacks)
--   Specials[kind]                              "Specials (the 9 kinds)": core, beats, extra layers, skipped ladder layers
--   Reactions (Hurt / Ko / Victory)             the small reaction effects
--   Signatures[petId]                           "Signature specials (12 pets)": overrides on top of their kind
--   Textures[key]                               mirror of blender/vfx/textures.json { Grid = 4 | 1, Baked = bool } (smoke
--                                               p7vfx_catalog checks it): Grid 1 strips (fx_lightning, fx_speedlines) are
--                                               for Beam / Trail layers ONLY; every Emitter / Decal texture is a 4x4 flipbook
--
-- API:
--   AttackFxCatalog.BandOf(rarity) -> 1..4                         unknown rarity -> 1
--   AttackFxCatalog.SizeOf(rarity, stage) -> number                Sizes[rarity] x (1 + StageBonus[stage]), <= SizeCap 1.4;
--                                                                  unknown rarity = Common, stage clamped to 0..2 (non-number 0)
--   AttackFxCatalog.Resolve(req) -> recipe | nil                   req = { Element, Attack, Kind, Shape, Rarity, Stage, PetId,
--                                                                  Mine, Distance? }; Attack = "Melee" | "Ranged" | "Special" |
--                                                                  "Element" | "Hurt" | "Ko" | "Victory"; Kind = one of the 9
--                                                                  special kinds (Special; a signature pet may leave it nil);
--                                                                  Shape = "Cone" | "Circle" | "Line" (Element; nil = the element's
--                                                                  BattleCatalog shape); Distance = studs to the target (projectile
--                                                                  travel, default 14). nil for an unknown element / attack / kind /
--                                                                  shape (the caller falls back to the cube Fx).
--     recipe = { Element, Attack, Kind, Shape, Rarity, Stage, Band, Size, Density (1 mine / 0.6 others), CameraPunch
--                (mine and band >= 3), ScreenGlow (mine and band 4), Signature (petId | nil), Sig = { Name, Twist, Actor,
--                DimWorld } | nil, Palette = { Core, Mid, Edge, Hot, Smoke }, Text,
--                Beats = { Charge, Release, Travel, Impact, Linger, MinTravel? } (seconds), ImpactAt (= Charge + Release +
--                Travel: the engine starts the effect so that impact lands on the server event, never later, except
--                that a basic Ranged shot keeps MinTravel of flight: player note 1, the shot is always seen crossing),
--                Core = { Key (vfx_* MeshIds key), Color, Material, Path ("Projectile"|"Swipe"|"Ground"|"Self"|"Allies"|
--                "Area"), Glow, InnerColor?, RimColor?, RimShift?, Upgraded, Speed?, Count?, Scale?, ... shape flags },
--                LowKeep = { layerId, ... } (Low quality keeps the Burst and then the first of these that the effect has: the
--                element's most characteristic emitter, chosen on purpose, not left to the engine's rank),
--                Layers = { { Id, Kind ("Emitter"|"Beam"|"Trail"|"Light"|"Ring"|"Decal"|"Mesh"), Beat, At, Texture?, Key?,
--                Color, Count?, Size?, Motion?, Delay?, ... } } (a template's Except = { [Attack or special Kind] = true } leaves
--                it out of those attacks), Alive = { Kind ("Emitter"|"Beam"|"Decal"|"Mesh"), Texture?,
--                Key?, Motion, Color, Count, Seconds, Text } ({} = none) }
--     Layer kinds: Emitter = a flipbook ParticleEmitter (4x4 sheet); Beam / Trail = a grid-1 strip or untextured; Light =
--     a PointLight; Ring = an expanding solid vfx_* mesh (vfx_ring / vfx_shell); Decal = a ground-flat layer (a 4x4 sheet
--     played as a flat flipbook particle, or an untextured glow disc); Mesh = a solid vfx_* piece with a Motion (e.g.
--     Nature's roots erupting). Burst Motion: "Geyser" (an upward column), "Implode" (contracts inward first), "Shatter",
--     "Burst"; Delay = seconds after the beat starts (Shadow's glass shatters after the implosion).
--     Layer At: "Source" (mouth / paws), "Core" (on the moving core), "Path" (source -> target), "Target", "Ground" (under
--     the hit point), "Above" (over the target), "Behind" (behind the caster), "Self", "Allies". Counts are FULL density:
--     ladder / kind layers x CountScale[band]; the element's own impact detail and alive detail x DetailScale[band]
--     (reduced at band 1, growing by band). The engine multiplies them by Density and its quality factor. Recipes are
--     fresh tables every call.
--   AttackFxCatalog.Unit(info) -> { Element, Rarity, Stage, PetId, Ranged }   from a BattleSim unitInfo (petId, key, look,
--                                                                  element, elements, evo, ranged): Rarity = an explicit
--                                                                  info.rarity / look.Rarity, else PetCatalog.Get(petId | key's
--                                                                  base).Rarity, else a hybrid's: the HIGHER of its look.BodyId
--                                                                  and look.StyleId pets' rarities (PetKeys' own rule), else
--                                                                  "Common"; Element = the FIRST of `elements` (else `element`);
--                                                                  Stage = evo clamped 0..2
--   AttackFxCatalog.Signatures[petId]                              the 12 signature pets (Element, Kind, Rarity, Twist, overrides)
--   AttackFxCatalog.AttackNames / KindNames / ShapeNames / Rarities   ordered name lists (the /fx dev command validates with them)

local Shared = script.Parent

local AttackFxCatalog = {}

local floor, min, max, huge = math.floor, math.min, math.max, math.huge

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE = rgb(255, 255, 255)

----------------------------------------------------------------------
-- Lazy modules (load order must never matter)
----------------------------------------------------------------------
local lazyCache = {}
local function lazy(name)
	local entry = lazyCache[name]
	if entry == nil then
		entry = false
		local inst = Shared:FindFirstChild(name)
		if inst then
			local ok, result = pcall(require, inst)
			if ok and type(result) == "table" then
				entry = result
			end
		end
		lazyCache[name] = entry
	end
	return entry or nil
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = copy(v)
	end
	return out
end

local function merge(into, from)
	if type(from) == "table" then
		for k, v in pairs(from) do
			into[k] = copy(v)
		end
	end
	return into
end

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------
AttackFxCatalog.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
AttackFxCatalog.AttackNames = { "Melee", "Ranged", "Special", "Element", "Hurt", "Ko", "Victory" }
AttackFxCatalog.KindNames = { "Blast", "Heal", "Shield", "Storm", "Pounce", "Freeze", "Beam", "Rally", "Haste" } -- PetCatalog.SpecialKinds
AttackFxCatalog.ShapeNames = { "Cone", "Circle", "Line" }

local rarityOrder = {}
for i, r in ipairs(AttackFxCatalog.Rarities) do
	rarityOrder[r] = i
end

----------------------------------------------------------------------
-- Rarity ladder (spec "Rarity ladder"): rarity shows through the core's intensity and shape in 4 bands, not sheer size
----------------------------------------------------------------------
AttackFxCatalog.Bands = { Common = 1, Uncommon = 1, Rare = 2, Epic = 2, Legendary = 3, Mythic = 3, Secret = 4 }
AttackFxCatalog.Sizes = { Common = 1.0, Uncommon = 1.05, Rare = 1.1, Epic = 1.15, Legendary = 1.2, Mythic = 1.3, Secret = 1.4 }
AttackFxCatalog.StageBonus = { [0] = 0, [1] = 0.05, [2] = 0.10 } -- Evolved +5%, Evolved II +10%
AttackFxCatalog.SizeCap = 1.4
AttackFxCatalog.OthersDensity = 0.6 -- other players' and wild pets' effects (own team: 1)
AttackFxCatalog.CountScale = { 1, 1.2, 1.4, 1.6 } -- particle counts per band: ladder / kind layers (full density)
AttackFxCatalog.DetailScale = { 0.5, 0.75, 1, 1.25 } -- the element's own impact + alive detail: every rarity, reduced at band 1

-- the core per band: Color / Inner / Rim name Palette entries ("White" = pure white)
AttackFxCatalog.CoreLook = {
	[1] = { Color = "Mid", Glow = 0 }, -- plain element colour (e.g. orange fire)
	[2] = { Color = "Mid", Inner = "Hot", Glow = 0.35 }, -- brighter, a hot inner core (e.g. blue-hot fire)
	[3] = { Color = "Core", Inner = "Hot", Glow = 0.7, Upgraded = true }, -- blazing core, upgraded shape (fins / a second blade)
	-- (Task 9 Studio, two rounds: a white core, solid or as a see-through shell, read as a white ball / sheet on the pale
	-- arena and hid the target (the Secret shot, the crescents, the spikes / roots). The white plasma is the HEART: a
	-- white-hot inner core inside a shell of the element's colour, the rim twin shifting colour. The cores with no inner
	-- heart (ground spikes / roots, the cone fan) stay in the element's colour. An element's PlasmaColor names the
	-- Palette entry its heart takes instead of white (Earth: a gold-hot heart in the rock).)
	[4] = { Color = "Mid", Inner = "White", Rim = "Edge", RimShift = true, Glow = 1, Upgraded = true, Material = "Neon" }, -- white plasma heart, colour-shifting rim
}

-- the layers each rarity adds, in rarity order (each keeps everything below it). The element's OWN impact detail
-- (Elements[e].Detail + the attack's own Layers) and its alive detail are NOT on the ladder: they show at every rarity.
AttackFxCatalog.Ladder = {
	{ Tier = "Common", Add = { "Charge", "Burst" } }, -- core shape + impact burst (+ the charge glow of beat 1)
	{ Tier = "Uncommon", Add = { "Trail" } }, -- + element trail
	{ Tier = "Rare", Add = { "Slash", "GroundGlow" } }, -- + crescent slash arc, ground glow
	{ Tier = "Epic", Add = { "Shockwave", "Flash" } }, -- + shockwave ring, light flash
	{ Tier = "Legendary", Add = { "Afterimage", "Bloom" } }, -- + afterimages, bloom pulse (camera punch: own pet)
	{ Tier = "Mythic", Add = { "DoubleArc", "Field" } }, -- + double arcs, a ground-only lingering field
	{ Tier = "Secret", Add = { "PlasmaRim" } }, -- + the colour-shifting rim (signature layer on signature pets; screen glow: own pet)
}

-- layer templates: Texture / Kind / Key / Tint "$Name" = the element's (or attack's / kind's / signature's) slot; At "$Hit"
-- = where the attack lands (Target, or Self / Allies for those paths). Tint = a Palette entry (baked textures play white).
AttackFxCatalog.LayerSlots = {
	Charge = { Kind = "Emitter", Texture = "fx_glow", Beat = "Charge", At = "Source", Tint = "Mid", Count = 5, Size = 1.5 },
	Burst = { Kind = "Emitter", Texture = "$Burst", Beat = "Impact", At = "$Hit", Tint = "Mid", Count = 12, Size = 2.5 },
	Trail = { Kind = "Emitter", Texture = "$Trail", Beat = "Travel", At = "Core", Tint = "Mid", Count = 10, Size = 1 },
	-- (Task 9: in the pale Core tint the arc read as a big white sheet over the leap and the target at Secret; the
	-- element's colour, a little smaller and see-through)
	-- (Task 9 round 2: still additive (the sheet's LightEmission 1) the arc summed to white on the pale arena; half-lit it
	-- keeps the element's colour)
	Slash = { Kind = "Emitter", Texture = "fx_slash", Beat = "Release", At = "Source", Tint = "Mid", Count = 1, Size = 2.6, Transparency = 0.4, LightEmission = 0.35 },
	GroundGlow = { Kind = "Decal", Beat = "Impact", At = "Ground", Tint = "Edge", Size = 5, Seconds = 0.6 }, -- an untextured glow disc
	-- (Task 8, Studio + Gemini: at 3 / 4 the flash + bloom washed the pets white and a 14-stud ring buried the target:
	-- lights <= 2 brightness / 8 studs range, the shockwave ~7 studs across and see-through)
	Shockwave = { Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "Ground", Tint = "Mid", Grow = 1.7, Transparency = 0.35 },
	Flash = { Kind = "Light", Beat = "Impact", At = "$Hit", Tint = "Core", Brightness = 1.6, Range = 8 },
	Afterimage = { Kind = "Trail", Texture = "fx_speedlines", Beat = "Travel", At = "Core", Tint = "Edge", Afterimages = 2 },
	Bloom = { Kind = "Light", Beat = "Release", At = "Core", Tint = "Hot", Brightness = 1.4, Range = 8, Pulse = true },
	-- the second crescent, a curved Beam (Task 8 Studio: untextured it read as a flat white slab; streaked with the arc sheet)
	-- (Task 9: see-through, Gemini: >= 0.4, the Secret double slash hid the leap)
	-- (Task 9 round 2: in the pale Hot tint and additive the two arcs were a white half-moon over the target at Secret;
	-- the element's colour, half-lit)
	DoubleArc = { Kind = "Beam", Texture = "$Arc", Beat = "Release", At = "Source", Tint = "Mid", Curve = 3, Width = 1.0, Transparency = 0.4, LightEmission = 0.35 },
	Field = { Kind = "Decal", Texture = "$Ground", Beat = "Linger", At = "Ground", Tint = "Mid", Size = 7, Seconds = 1.0, GroundOnly = true },
	PlasmaRim = { Kind = "Light", Beat = "Travel", At = "Core", Tint = "Edge", Brightness = 1.2, Range = 6, ColorShift = true },
	-- the ranged swaps (Basic.Ranged.Swap, player note 1: a shot is no swing): the Rare crescent becomes a muzzle shock
	-- ring standing at the mouth, facing the shot; the Mythic double arcs become two spiral arcs wrapped round the shot
	MuzzleRing = { Kind = "Ring", Key = "vfx_ring", Beat = "Release", At = "Source", Tint = "Mid", Grow = 0.55, Face = true, Transparency = 0.35 }, -- (Task 9: Mid, the pale Core ring + the Secret shell read as a white ball at the mouth)
	-- the ranged shot's afterimages: short comet tails (Task 8 + Gemini: at the 0.2 s default they stretched back to the
	-- mouth mid-flight and the shot read as a tether)
	ShotAfterimage = { Kind = "Trail", Texture = "fx_speedlines", Beat = "Travel", At = "Core", Tint = "Edge", Afterimages = 2, Lifetime = 0.1 },
	ShotArcs = { Kind = "Beam", Texture = "$Arc", Beat = "Travel", At = "Path", Tint = "Hot", Spiral = true, Curve = 1.2, Width = 0.45, Count = 2 },
}

----------------------------------------------------------------------
-- Textures (mirror of blender/vfx/textures.json; Baked = the colour is in the sheet, play it white)
----------------------------------------------------------------------
AttackFxCatalog.Textures = {
	fx_flame = { Grid = 4, Baked = true },
	fx_embers = { Grid = 4, Baked = true },
	fx_smoke = { Grid = 4, Baked = false },
	fx_splash = { Grid = 4, Baked = true },
	fx_droplets = { Grid = 4, Baked = true },
	fx_ripple = { Grid = 4, Baked = true },
	fx_iceshards = { Grid = 4, Baked = true },
	fx_snow = { Grid = 4, Baked = true },
	fx_frostmist = { Grid = 4, Baked = true },
	fx_petals = { Grid = 4, Baked = true },
	fx_leaves = { Grid = 4, Baked = true },
	fx_thorn = { Grid = 4, Baked = true },
	fx_rock = { Grid = 4, Baked = true },
	fx_dust = { Grid = 4, Baked = true },
	fx_crack = { Grid = 4, Baked = true },
	fx_lightning = { Grid = 1, Baked = true }, -- Beam strip
	fx_sparks = { Grid = 4, Baked = false },
	fx_stormcloud = { Grid = 4, Baked = false },
	fx_stars = { Grid = 4, Baked = true },
	fx_rays = { Grid = 4, Baked = true },
	fx_sparkle = { Grid = 4, Baked = false },
	fx_wisps = { Grid = 4, Baked = true },
	fx_voidring = { Grid = 4, Baked = true },
	fx_darkglass = { Grid = 4, Baked = true },
	fx_slash = { Grid = 4, Baked = false },
	fx_shock = { Grid = 4, Baked = false },
	fx_glow = { Grid = 4, Baked = false },
	fx_streak = { Grid = 4, Baked = false },
	fx_speedlines = { Grid = 1, Baked = false }, -- Beam / Trail strip
	fx_hexshield = { Grid = 4, Baked = false },
}

----------------------------------------------------------------------
-- Elements: normal attacks (spec table). Sheets: Burst (the impact burst, Common up; BurstMotion = how it moves),
-- Trail (Uncommon up), Ground (the Mythic lingering field decal; nil = an untextured glow), Motif (heal spirals,
-- victory), Arc (the Beam special's spiral strip). Detail = the element's OWN impact detail (spec "Impact" column):
-- every attack that hits an enemy shows it at EVERY rarity (counts x DetailScale: reduced at band 1, growing by band).
-- Alive = the spec "Alive" detail (every rarity too). Melee / Ranged = the core + slot overrides + their own Layers
-- (attack-specific detail, also every rarity) + Drop = { [layerId] = true } (shared Basic layers this element's attack
-- leaves out). BurstScale = { Size, Count } x the Burst, BurstLight = the Burst's LightEmission (Task 9: tuned per element
-- in Studio: an additive burst of a pale glow sheet summed to a white ball on the pale arena).
----------------------------------------------------------------------
AttackFxCatalog.Elements = {
	Water = {
		Palette = { Core = rgb(214, 244, 255), Mid = rgb(64, 148, 236), Edge = rgb(28, 96, 204), Hot = rgb(236, 255, 255), Smoke = rgb(150, 190, 230) },
		Material = "Neon",
		-- (Task 9 emitter budget: Ground nil = the Mythic field is a soft glow disc, not a second fx_ripple sheet: the
		-- impact Ripple already lies there; the old impact Droplets fling is gone, the alive droplets bounce out of the hit)
		Burst = "fx_splash", BurstMotion = "Geyser", Trail = "fx_droplets", Ground = nil, Motif = "fx_droplets", Arc = "fx_speedlines",
		LowKeep = { "Ripple" },
		-- (Task 9 Studio + Gemini: 2.5-stud splash sheets clumped into a ball round the target and read as a shield bubble;
		-- smaller, more drops: a spray that rises as a geyser)
		-- (round 2: the Secret splash still balled up over the target: smaller drops; Gemini: the column's core still dense
		-- at Secret: a little see-through)
		BurstScale = { Size = 0.42, Count = 1.1, Transparency = 0.35 }, -- (round 3, Gemini: the target hid in the Secret spray)
		-- (round 2: from the target's middle the column of splash sheets read as a bubble round it (the "shield"); a geyser
		-- erupts from the GROUND under the target and the spray rises past it)
		BurstAt = "Ground",
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "crescent wave slash" },
		-- (Task 9: the shot's explosion is the boosted geyser splash + the shock ring; the Boom pop ball read as a bubble)
		Ranged = { Key = "vfx_orb", Path = "Projectile", Spin = true, Text = "spinning water orb, droplet trail", Drop = { Boom = true } },
		Impact = "geyser burst + ripple ring",
		Detail = {
			-- the geyser is the Burst itself (BurstMotion "Geyser": an upward fx_splash column)
			{ Id = "Ripple", Kind = "Decal", Texture = "fx_ripple", Beat = "Impact", At = "Ground", Size = 5, Seconds = 0.8 },
		},
		Alive = { Kind = "Emitter", Texture = "fx_droplets", Motion = "Bounce", Count = 6, Seconds = 0.7, Text = "droplets bounce on the ground, then pop" },
		Rain = { Key = "vfx_orb", Texture = "fx_droplets", Kind = "Emitter", Scale = 0.3, Text = "a downpour" },
	},
	Flame = {
		Palette = { Core = rgb(255, 232, 150), Mid = rgb(255, 122, 40), Edge = rgb(214, 54, 22), Hot = rgb(140, 200, 255), Smoke = rgb(112, 92, 82) },
		Material = "Neon",
		Burst = "fx_flame", BurstMotion = "Burst", Trail = "fx_embers", Ground = nil, Motif = "fx_embers", Arc = "fx_speedlines",
		LowKeep = { "Alive" }, -- the embers swirling up
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "crescent of fire" },
		Ranged = {
			Key = "vfx_spear", Path = "Projectile", Text = "flame spear, ember trail", Scale = 0.6, Girth = 1.25,
			-- the spear flies wrapped in fire: flame licks stream off it all the way to the target (a flame bolt)
			Layers = { { Id = "Mantle", Kind = "Emitter", Texture = "fx_flame", Beat = "Travel", At = "Core", Count = 14, Size = 2.4 } },
			LowKeep = { "Mantle" }, -- the shot is a flame bolt: its fire mantle
		},
		Impact = "fire burst + embers + scorch glow",
		Detail = {
			-- the scorch glow: an untextured Decal = the engine's glow Disc (a soft fx_glow image since Task 8; a Texture would
			-- make it a particle sheet and take one of the effect's 6 emitter slots: Task 8 fix round 3, review Important 1)
			{ Id = "Scorch", Kind = "Decal", Beat = "Impact", At = "Ground", Tint = "Edge", Size = 5, Seconds = 0.9 },
			-- (not on the ranged shot: its flame mantle + muzzle puff take the emitter budget, <= 6 per effect; not on the
			-- Storm: its cloud + fire rain do, and a smoke puff under a cloud of fire reads as mud; not on the Blast: its charge
			-- telegraph keeps its slot)
			-- (Task 8 Studio: at 74/56/48 and on the impact frame the fresh puff read as a black ball inside the fire burst;
			-- a lighter soot, rising as the burst fades)
			{ Id = "Smoke", Kind = "Emitter", Texture = "fx_smoke", Beat = "Impact", At = "$Hit", Tint = "Smoke", Motion = "Rise", Delay = 0.12, Count = 6, Size = 1.6, Except = { Ranged = true, Storm = true, Blast = true } },
		},
		Alive = { Kind = "Emitter", Texture = "fx_embers", Motion = "SwirlUp", Count = 8, Seconds = 0.9, Text = "embers swirl upward on heat" },
		Rain = { Key = "vfx_spear", Texture = "fx_flame", Kind = "Emitter", Scale = 0.4, Text = "fire rain" },
		-- (Task 8 Studio + Gemini: tinted the deep fire red the Storm cloud read as a blood-red blob; a smoky maroon ash
		-- cloud, the fire rain and its flashes carry the heat)
		Tints = { Cloud = rgb(150, 100, 84) },
	},
	Frost = {
		Palette = { Core = rgb(240, 252, 255), Mid = rgb(150, 222, 248), Edge = rgb(86, 168, 232), Hot = rgb(255, 255, 255), Smoke = rgb(200, 230, 245) },
		Material = "Glass",
		-- (Task 9 emitter budget: Ground nil = the Mythic field is a soft frost-blue glow disc; the impact FrostRing sheet
		-- already lies on the ground)
		Burst = "fx_iceshards", BurstMotion = "Shatter", Trail = "fx_snow", Ground = nil, Motif = "fx_snow", Arc = "fx_speedlines",
		LowKeep = { "FrostRing" },
		-- (Task 9 Studio: the boosted Secret shatter was a white wall over the target; smaller, fewer shards)
		BurstScale = { Size = 0.7, Count = 0.85 },
		Melee = { Key = "vfx_spike", Path = "Ground", Count = 4, Text = "ice spikes burst from the ground along a path" },
		-- (Task 9 Studio: at scale 1 the pale shard vanished against a pale sky mid-flight)
		Ranged = { Key = "vfx_shard", Path = "Projectile", Text = "sharp ice shard, snow trail", Scale = 1.35, Girth = 1.3 },
		Impact = "crystal shatter + frost ring on the ground",
		Detail = {
			{ Id = "FrostRing", Kind = "Decal", Texture = "fx_frostmist", Beat = "Impact", At = "Ground", Size = 5, Seconds = 1.0 },
			-- (Task 9: a cold mist rising after the shatter, not a white fog ball on the hit frame)
			{ Id = "FrostMist", Kind = "Emitter", Texture = "fx_frostmist", Beat = "Impact", At = "$Hit", Motion = "Rise", Delay = 0.08, Count = 5, Size = 1.2 },
		},
		Alive = { Kind = "Mesh", Key = "vfx_shard", Motion = "Melt", Tint = "Mid", Count = 5, Seconds = 1.0, Text = "impact shards linger and visibly melt (~1 s)" },
		Rain = { Key = "vfx_shard", Texture = "fx_snow", Kind = "Emitter", Scale = 0.5, Text = "hail" },
		Area = { Key = "vfx_spike", Count = 5 },
	},
	Nature = {
		-- pink / yellow / cream only: Nature must read on green grass (no green-only colour anywhere)
		Palette = { Core = rgb(255, 228, 120), Mid = rgb(255, 142, 192), Edge = rgb(240, 236, 150), Hot = rgb(255, 250, 214), Smoke = rgb(230, 210, 170) },
		Material = "Neon",
		Burst = "fx_petals", BurstMotion = "Burst", Trail = "fx_petals", Ground = nil, Motif = "fx_petals", Arc = "fx_speedlines",
		LowKeep = { "Thorns", "PodGlow" },
		BurstScale = { Size = 0.8, Count = 1 }, -- (Task 9: the Secret petal burst hid the target)
		Melee = {
			Key = "vfx_root", Path = "Ground", Count = 3, Scale = 0.75, Text = "thorny roots erupt under the target", -- (Task 9: at Secret the roots buried the target)
			Layers = {
				{ Id = "Thorns", Kind = "Emitter", Texture = "fx_thorn", Beat = "Travel", At = "$Hit", Count = 4, Size = 2.5 },
				-- root burst debris: golden pollen (Task 9, checked on the arena lawn: the baked green fx_leaves vanished on the
				-- grass, against the "no green-only colour" rule; the petals + pink roots carry the rest)
				{ Id = "Pollen", Kind = "Emitter", Texture = "fx_sparkle", Beat = "Impact", At = "$Hit", Tint = "Core", Count = 6, Size = 0.8 },
			},
		},
		Ranged = {
			Key = "vfx_orb", Path = "Projectile", Scale = 0.7, Text = "glowing seed pod, pink / yellow petal trail",
			Layers = {
				-- the root burst: the pod lands and roots erupt from the ground under the target
				{ Id = "RootBurst", Kind = "Mesh", Key = "vfx_root", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Edge", Count = 3, Scale = 0.6 },
				{ Id = "PodGlow", Kind = "Emitter", Texture = "fx_sparkle", Beat = "Impact", At = "$Hit", Tint = "Core", Count = 6, Size = 0.8 },
			},
		},
		Impact = "root burst + petals",
		Detail = {}, -- the petals are the Burst; the vines are the Alive detail
		Alive = { Kind = "Mesh", Key = "vfx_root", Motion = "Wrap", Tint = "Edge", Count = 3, Seconds = 0.6, Text = "vines briefly wrap the target" },
		Rain = { Key = "vfx_orb", Texture = "fx_petals", Kind = "Emitter", Scale = 0.25, Text = "a petal shower" },
		Area = { Key = "vfx_root", Count = 4 },
	},
	Earth = {
		Palette = { Core = rgb(255, 204, 120), Mid = rgb(178, 128, 80), Edge = rgb(110, 78, 50), Hot = rgb(255, 150, 60), Smoke = rgb(196, 170, 130) },
		Material = "SmoothPlastic", -- rock; the glowing seam comes in with the band 2 inner core
		-- (Task 9 emitter budget: Ground nil = the Mythic field is a soft glow disc; the impact GroundCrack sheet already
		-- lies on the ground)
		-- (Task 9 Studio: as a slow "Burst" the big rock sheets clumped into one boulder over the target; the rock now
		-- breaks: smaller chunks flung out and falling, Shatter)
		Burst = "fx_rock", BurstMotion = "Shatter", Trail = "fx_dust", Ground = nil, Motif = "fx_sparkle", Arc = "fx_speedlines",
		LowKeep = { "Dust" },
		PlasmaColor = "Core", -- (Task 9: the Secret rock's plasma heart glows gold, not white: a white boulder read as a snow cube)
		BurstScale = { Size = 0.55, Count = 0.5 }, -- (fewer, smaller chunks: at full count they still read as one boulder)
		Melee = { Key = "vfx_spike", Path = "Ground", Count = 3, Text = "ground slam, rock spikes" },
		Ranged = { Key = "vfx_chunk", Path = "Projectile", Scale = 2.2, Text = "boulder, dust trail" },
		Impact = "rock breaks into voxel chunks + dust + ground crack",
		Detail = {
			-- (Task 9: rising after the break, not a brown smudge over the target on the hit frame)
			{ Id = "Dust", Kind = "Emitter", Texture = "fx_dust", Beat = "Impact", At = "$Hit", Motion = "Rise", Delay = 0.06, Count = 8, Size = 1.6 },
			{ Id = "GroundCrack", Kind = "Decal", Texture = "fx_crack", Beat = "Impact", At = "Ground", Size = 5, Seconds = 1.0 },
		},
		-- (Task 9 Studio: full-size chunks piled into a boulder on the target at Secret; half size)
		Alive = { Kind = "Mesh", Key = "vfx_chunk", Motion = "Bounce", Tint = "Mid", Scale = 0.5, Count = 5, Seconds = 0.8, Text = "chunks scatter and bounce" },
		Rain = { Key = "vfx_chunk", Texture = "fx_rock", Kind = "Emitter", Scale = 1.2, Text = "a rock fall" },
		Area = { Key = "vfx_spike", Count = 5 },
	},
	Storm = {
		Palette = { Core = rgb(224, 236, 255), Mid = rgb(110, 128, 255), Edge = rgb(60, 72, 210), Hot = rgb(255, 252, 170), Smoke = rgb(120, 124, 150) },
		Material = "Neon",
		Burst = "fx_glow", BurstMotion = "Burst", Trail = "fx_sparks", Ground = nil, Motif = "fx_sparks", Arc = "fx_lightning",
		LowKeep = { "ZigZag" },
		-- (Task 9 Studio: the fx_glow burst was a white ball and the baked white lightning vanished on a pale sky: a small
		-- blue burst, every bolt tinted the storm's blue)
		BurstScale = { Size = 0.55, Count = 0.7 },
		Tints = { Bolt = rgb(120, 136, 255), Arcs = rgb(120, 136, 255), Crackle = rgb(120, 136, 255) },
		Melee = {
			Key = "vfx_crescent", Path = "Swipe", Text = "electric claw, crackling arcs",
			Layers = { { Id = "Arcs", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "$Hit", Count = 2 } },
		},
		Ranged = {
			Key = "vfx_shard", Path = "Projectile", Speed = 120, Scale = 0.8, Text = "jagged lightning bolt",
			Layers = {
				{ Id = "Bolt", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Width = 2, Count = 2 },
				-- the bolt crackles round the target as it strikes (beams, no emitter)
				{ Id = "Crackle", Kind = "Beam", Texture = "fx_lightning", Beat = "Impact", At = "$Hit", Count = 2 },
			},
		},
		Impact = "electric burst + zig-zag sparks",
		Detail = {
			{ Id = "ZigZag", Kind = "Emitter", Texture = "fx_sparks", Beat = "Impact", At = "$Hit", Tint = "Core", Count = 10, Size = 1.2 },
		},
		Alive = { Kind = "Beam", Texture = "fx_lightning", Motion = "Strike", Color = rgb(120, 136, 255), Count = 2, Seconds = 0.6, Text = "stray bolts strike the ground nearby" },
		Rain = { Key = "vfx_shard", Texture = "fx_lightning", Kind = "Beam", Scale = 0.6, Text = "lightning strikes" },
		Area = { Layers = { { Id = "Bolt", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Width = 1.6 } } },
	},
	Celestial = {
		Palette = { Core = rgb(255, 250, 224), Mid = rgb(255, 212, 104), Edge = rgb(236, 164, 64), Hot = rgb(255, 255, 255), Smoke = rgb(255, 236, 190) },
		Material = "Neon",
		Burst = "fx_stars", BurstMotion = "Burst", Trail = "fx_sparkle", Ground = nil, Motif = "fx_stars", Arc = "fx_speedlines",
		LowKeep = { "Rays" },
		BurstScale = { Size = 0.6, Count = 0.65 }, -- (Task 9: the star burst + rays were a white flare over the target)
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "golden starlight slash" },
		Ranged = { Key = "vfx_star", Path = "Projectile", Spin = true, Text = "shooting star, sparkle tail" },
		Impact = "star burst + light rays",
		Detail = {
			{ Id = "Rays", Kind = "Emitter", Texture = "fx_rays", Beat = "Impact", At = "$Hit", Count = 3, Size = 2.6 },
		},
		Alive = { Kind = "Beam", Motion = "Connect", Tint = "Core", Count = 4, Seconds = 0.8, Text = "constellation lines join the stars" },
		Rain = { Key = "vfx_star", Texture = "fx_stars", Kind = "Emitter", Scale = 0.5, Text = "falling stars" },
	},
	Shadow = {
		Palette = { Core = rgb(214, 156, 255), Mid = rgb(128, 72, 178), Edge = rgb(44, 22, 66), Hot = rgb(255, 96, 224), Smoke = rgb(60, 40, 80) },
		Material = "Neon",
		-- the void implosion is the Burst itself (BurstMotion "Implode": the fx_voidring contracts inward), then the glass
		Burst = "fx_voidring", BurstMotion = "Implode", Trail = "fx_wisps", Ground = nil, Motif = "fx_wisps", Arc = "fx_speedlines",
		LowKeep = { "Glass" },
		BurstScale = { Size = 0.5, Count = 0.65 }, -- (Task 9: the void rings swarmed into a ball twice the pet's size)
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "dark claw, purple wisps" },
		Ranged = { Key = "vfx_orb", Path = "Projectile", Text = "shadow orb pulling wisps" },
		Impact = "void implosion, then black glass shatters with glitchy purple sparks",
		Detail = {
			{ Id = "Glass", Kind = "Emitter", Texture = "fx_darkglass", Beat = "Impact", At = "$Hit", Delay = 0.12, Count = 8, Size = 1.2 },
			{ Id = "GlitchSparks", Kind = "Emitter", Texture = "fx_sparks", Beat = "Impact", At = "$Hit", Tint = "Hot", Delay = 0.12, Count = 8, Size = 1 },
		},
		Alive = { Kind = "Decal", Motion = "Darken", Tint = "Edge", Count = 2, Seconds = 0.9, Text = "the floor darkens under the wisps" },
		Rain = { Key = "vfx_shard", Texture = "fx_wisps", Kind = "Emitter", Scale = 0.5, Text = "falling shadow shards" },
	},
}

----------------------------------------------------------------------
-- The 5 beats (spec "The 5 beats of every attack"): Charge 0.12-0.3 (specials up to 0.8), Release 0.05, Travel by
-- distance (projectiles 60 studs/s, capped), Impact 0.15, Linger 0.4-1.0. Charge / Linger grow a little per band.
----------------------------------------------------------------------
AttackFxCatalog.Beats = {
	Release = 0.05,
	Impact = 0.15,
	ChargeStep = 0.03, -- per band above 1 (specials: 0.05)
	LingerStep = 0.1, -- per band above 1
	ChargeMax = 0.3,
	SpecialChargeMax = 0.8,
	LingerMax = 1.0,
	ProjectileSpeed = 60, -- studs / s (the Blast orb)
	RangedSpeed = 34, -- studs / s: a basic ranged shot flies slower than the Blast orb, so its flight reads (player note 1)
	MinTravel = 0.24, -- seconds a basic ranged shot always flies (the engine keeps it even when the event is near: the
	--                  impact may then land up to this much after the event, and BattleController holds the hit for it)
	DefaultDistance = 14, -- studs, when the request has no Distance
	TravelMax = 0.5, -- seconds (the engine keeps impact <= the event's due time, except for a recipe's MinTravel)
}

-- the basic attacks; Skip = ladder layers this attack never draws; Swap = ladder layers replaced by another template
-- (LayerSlots); Layers = the attack's own layers at every rarity (counts x DetailScale, like the element's detail).
-- Ranged (player note 1): a shot across the gap, never a swing: no crescent (Slash -> MuzzleRing, DoubleArc ->
-- ShotArcs), a muzzle puff of the element's burst sheet at the release, a glowing streak behind the shot at every
-- rarity, and a guaranteed visible flight (RangedSpeed, MinTravel).
AttackFxCatalog.Basic = {
	-- LeapTravel (player decision, Task 9: the melee leap lands on the target): with a known Distance (centre to centre)
	-- the swing's Travel grows by PerStud past Near, up to Extra, so a long leap (the /fx preview's 10 studs) has the
	-- air time to read as a jump; at battle range (~4 studs) it stays the base travel
	Melee = { Beats = { Charge = 0.15, Travel = 0.1, Linger = 0.5 }, GroundTravel = 0.15, LeapTravel = { Near = 4, PerStud = 0.02, Extra = 0.14 } },
	Ranged = {
		Beats = { Charge = 0.18, Linger = 0.5 }, -- Travel by distance at Beats.RangedSpeed (an element's Ranged.Speed wins:
		--                                          Storm's bolt), at least Beats.MinTravel
		Shot = true,
		Swap = { Slash = "MuzzleRing", DoubleArc = "ShotArcs", Afterimage = "ShotAfterimage" },
		-- player note (b), fix round 3: the shot's impact EXPLODES at every rarity: a bigger burst of the element's sheet
		-- (BurstBoost: Count / Size x), a fireball pop of the element's colour (Boom), a ground shock ring (BoomRing) and a
		-- flash (BoomFlash, which replaces the Epic Flash: <= 3 lights at Secret). It grows with the effect's Size
		-- (1.0 .. 1.4 by rarity) and with the ladder (the Epic Shockwave adds a second, wider ring). No emitter is added.
		Skip = { Flash = true },
		BurstBoost = { Count = 1.25, Size = 1.15 }, -- (Task 9: at 1.4 / 1.3 the Secret explosion hid the target)
		Layers = {
			{ Id = "Muzzle", Kind = "Emitter", Texture = "$Burst", Beat = "Release", At = "Source", Tint = "Mid", Count = 4, Size = 1.3 },
			-- (Task 8 Studio: untextured, the streak read as a flat white ribbon on a bright sky; streaked + the deep edge colour,
			-- and a short comet tail (Lifetime, seconds): at the default 0.2 s it stretched back to the mouth mid-flight)
			{ Id = "Streak", Kind = "Trail", Texture = "$Arc", Beat = "Travel", At = "Core", Tint = "Edge", Lifetime = 0.08 },
			{ Id = "Boom", Kind = "Ring", Key = "vfx_orb", Beat = "Impact", At = "$Hit", Tint = "Mid", Grow = 1.25, Transparency = 0.5, Pop = true }, -- (Studio + Gemini: at 0.3 the ball hid the target)
			{ Id = "BoomRing", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "Ground", Tint = "Core", Grow = 1.3, Transparency = 0.3 },
			{ Id = "BoomFlash", Kind = "Light", Beat = "Impact", At = "$Hit", Tint = "Core", Brightness = 1.5, Range = 7 },
		},
	},
}

----------------------------------------------------------------------
-- Element attacks (spec: "a Cone becomes a fanned blast of the element, a Circle a ground nova, a Line a long sweeping
-- strike"). Elements[e].Area overrides the core (ground elements: spikes / roots) and adds layers (Storm's bolt).
----------------------------------------------------------------------
AttackFxCatalog.Shapes = {
	Cone = { Text = "a fanned blast of the element", Core = { Key = "vfx_crescent", Path = "Area", Fan = true, Count = 3 }, Beats = { Charge = 0.2, Travel = 0.22, Linger = 0.5 } },
	Circle = { Text = "a ground nova", Core = { Key = "vfx_ring", Path = "Area", Grow = 4 }, Beats = { Charge = 0.2, Travel = 0.2, Linger = 0.5 } },
	-- (Task 8 Studio: at full width the line was a solid 1.3-stud bar that hid the target; a thinner, see-through beam)
	Line = { Text = "a long sweeping strike", Core = { Key = "vfx_beam", Path = "Area", Stretch = true, Thick = 0.5, Transparency = 0.25 }, Beats = { Charge = 0.2, Travel = 0.35, Linger = 0.5 } },
}

----------------------------------------------------------------------
-- Specials (spec "the 9 kinds, recoloured and retextured per element"). Core.Key "$RainKey" = the element's Rain.
-- Slots override the element's sheets for this kind; Layers are the kind's own (From = the tier they join, default
-- Common); Skip = ladder layers the kind never draws; Detail = false = no element impact detail (the support kinds).
----------------------------------------------------------------------
local SUPPORT_SKIP = { Trail = true, Slash = true, Afterimage = true, DoubleArc = true }

AttackFxCatalog.Specials = {
	Blast = {
		Text = "an orb grows above the pet, fires, and explodes into a dome + shockwave",
		-- (Task 8 Studio + Gemini: solid, the Secret white-plasma orb read as a flat white sticker; see-through, its rim twin
		-- shows inside)
		Core = { Key = "vfx_orb", Path = "Projectile", Rise = 3, Grow = true, Transparency = 0.45 },
		Beats = { Charge = 0.55, Linger = 0.6 },
		Layers = {
			-- (Task 8: a see-through dome ~1.5x a pet, the target stays visible inside it; the blastwave ~9 studs)
			{ Id = "Dome", Kind = "Ring", Key = "vfx_shell", Beat = "Impact", At = "$Hit", Tint = "Mid", Grow = 1.5, Transparency = 0.72 },
			{ Id = "Blastwave", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "Ground", Tint = "Core", Grow = 2.2, Transparency = 0.3 },
		},
		Skip = {},
	},
	Beam = {
		Text = "charge glow at the mouth, then a thick beam wrapped in spiral arcs; impact flare at the end",
		Core = { Key = "vfx_beam", Path = "Projectile", Stretch = true, Thick = 1.4 },
		Beats = { Charge = 0.5, Travel = 0.1, Linger = 0.5 },
		Layers = {
			{ Id = "Spiral", Kind = "Beam", Texture = "$Arc", Beat = "Travel", At = "Path", Tint = "Edge", Spiral = true, Count = 2 },
			{ Id = "Flare", Kind = "Emitter", Texture = "fx_glow", Beat = "Impact", At = "$Hit", Tint = "Hot", Count = 4, Size = 3 },
		},
		Skip = { Trail = true, Slash = true },
	},
	Pounce = {
		Text = "crouch, a leap with afterimages, a slam landing that cracks the ground",
		Core = { Key = "vfx_ring", Path = "Ground", Grow = 2.2 },
		Beats = { Charge = 0.4, Travel = 0.35, Linger = 0.6 },
		Layers = {
			{ Id = "Leap", Kind = "Trail", Texture = "fx_speedlines", Beat = "Travel", At = "Self", Tint = "Edge", Afterimages = 3 },
			{ Id = "SlamCrack", Kind = "Decal", Texture = "fx_crack", Beat = "Impact", At = "Ground", Size = 6, Seconds = 0.8 },
		},
		Skip = { Trail = true },
	},
	Storm = {
		Text = "a cloud gathers over the target and rains the element",
		Core = { Key = "$RainKey", Path = "Area", Count = 8, Fall = true },
		Beats = { Charge = 0.6, Travel = 0.45, Linger = 0.7 },
		Layers = {
			{ Id = "Cloud", Kind = "Emitter", Texture = "fx_stormcloud", Beat = "Charge", At = "Above", Tint = "Edge", Count = 6, Size = 4 },
			{ Id = "Rain", Kind = "$RainKind", Texture = "$RainTexture", Beat = "Travel", At = "Above", Tint = "Mid", Count = 12, Size = 1 },
		},
		LowKeep = { "Cloud" },
		Skip = { Trail = true, Slash = true, Afterimage = true },
	},
	Freeze = {
		Text = "a crystal cage in the element's colour locks the target",
		Core = { Key = "vfx_cage", Path = "Ground", Material = "Glass", KeepMaterial = true, Rise = true }, -- Glass at every band
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.7 },
		Layers = { { Id = "Lock", Kind = "Light", Beat = "Impact", At = "$Hit", Tint = "Core", Brightness = 2, Range = 8 } },
		Skip = { Trail = true, Slash = true, Afterimage = true },
	},
	Heal = {
		Text = "spirals of glowing petals rise around allies, plus-shaped sparkles",
		Core = { Key = "vfx_ring", Path = "Allies", Grow = 1.5 },
		Beats = { Charge = 0.45, Travel = 0.3, Linger = 0.7 },
		Slots = { Burst = "fx_sparkle" },
		Layers = { { Id = "Spiral", Kind = "Emitter", Texture = "$Motif", Beat = "Travel", At = "Allies", Tint = "Core", Spiral = true, Count = 10, Size = 1 } },
		LowKeep = { "Spiral" },
		BurstShape = "Plus",
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
	Shield = {
		Text = "a hexagon bubble around each ally, rippling when hit",
		Core = { Key = "vfx_shell", Path = "Allies", Material = "Glass", KeepMaterial = true, Transparency = 0.6 }, -- Glass at every band
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.8 },
		Slots = { Burst = "fx_hexshield" },
		Layers = {},
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
	Rally = {
		Text = "the pet roars; rings pulse outward; allies light up",
		Core = { Key = "vfx_ring", Path = "Self", Grow = 4, Pulses = 3 },
		Beats = { Charge = 0.45, Travel = 0.25, Linger = 0.6 },
		Slots = { Burst = "fx_shock" },
		Layers = { { Id = "AllyGlow", Kind = "Light", Beat = "Impact", At = "Allies", Tint = "Core", Brightness = 2, Range = 8 } },
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
	Haste = {
		Text = "wind-streak trails and speed lines on allies",
		Core = { Key = "vfx_ring", Path = "Allies", Grow = 1.2 },
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.6 },
		Slots = { Burst = "fx_streak" },
		Layers = { { Id = "Wind", Kind = "Trail", Texture = "fx_speedlines", Beat = "Linger", At = "Allies", Tint = "Core" } },
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
}

----------------------------------------------------------------------
-- Reactions: hit reaction, KO poof, victory sparkle (small; no element extras, no alive detail)
----------------------------------------------------------------------
local REACTION_SKIP = { Charge = true, Trail = true, Slash = true, Afterimage = true, DoubleArc = true, Field = true }

AttackFxCatalog.Reactions = {
	Hurt = {
		Text = "quick squash + flinch, a flash of the hit element",
		Core = { Key = "vfx_orb", Path = "Self", Scale = 0.45, Flash = true },
		Beats = { Charge = 0, Release = 0, Travel = 0, Linger = 0.4 },
		Skip = { Charge = true, Trail = true, Slash = true, GroundGlow = true, Shockwave = true, Afterimage = true, Bloom = true, DoubleArc = true, Field = true },
	},
	Ko = {
		Text = "tumble + element-coloured poof",
		Core = { Key = "vfx_orb", Path = "Self", Scale = 0.8, Poof = true },
		Beats = { Charge = 0, Travel = 0, Linger = 0.8 },
		Slots = { Burst = "fx_smoke" },
		Layers = { { Id = "Sparkle", Kind = "Emitter", Texture = "fx_sparkle", Beat = "Linger", At = "Self", Tint = "Core", Count = 6, Size = 0.8 } },
		Skip = REACTION_SKIP,
	},
	Victory = {
		Text = "hop-spin + sparkle burst",
		Core = { Key = "vfx_star", Path = "Self", Scale = 1 },
		Beats = { Charge = 0.2, Travel = 0.25, Linger = 1.0 },
		Slots = { Burst = "fx_sparkle" },
		Layers = { { Id = "Confetti", Kind = "Emitter", Texture = "$Motif", Beat = "Impact", At = "Self", Tint = "Core", Count = 10, Size = 1 } },
		Skip = REACTION_SKIP,
	},
}

----------------------------------------------------------------------
-- Signature specials (spec table, 12 pets). Overrides on top of the kind: Core (merged), Palette (merged), Slots,
-- Layers (added, From Common), Tints[layerId] (an explicit colour for a base layer), Beats, Actor (a vfx_sig_* solid
-- mesh piece), DimWorld (seconds the battle dims).
----------------------------------------------------------------------
AttackFxCatalog.Signatures = {
	ember_phoenix = {
		Name = "Phoenix Flare", Rarity = "Legendary", Element = "Flame", Kind = "Blast",
		Twist = "spreads blazing wings, the orb is a phoenix-shaped fireball",
		Core = { Key = "vfx_sig_phoenix_wing", Scale = 0.8 },
		Layers = { { Id = "SigWingGlow", Kind = "Light", Beat = "Charge", At = "Source", Tint = "Hot", Brightness = 3, Range = 14 } },
	},
	sunbeam_bear = {
		Name = "Golden Aegis", Rarity = "Legendary", Element = "Earth", Kind = "Shield",
		Twist = "a golden sun-disc shield with rays",
		Core = { Key = "vfx_sig_sun_disc", Material = "Neon", Transparency = 0.2 },
		Palette = { Core = rgb(255, 244, 196), Mid = rgb(255, 210, 110), Edge = rgb(232, 150, 40), Hot = rgb(255, 255, 230) },
		Layers = { { Id = "SigRays", Kind = "Emitter", Texture = "fx_rays", Beat = "Impact", At = "Allies", Count = 3, Size = 5 } },
	},
	twilight_dragon = {
		Name = "Dusk Storm", Rarity = "Legendary", Element = "Shadow", Kind = "Storm",
		Twist = "a dusk-purple storm with falling shadow stars",
		Palette = { Core = rgb(236, 190, 255), Mid = rgb(176, 124, 236), Edge = rgb(72, 40, 120) },
		Slots = { RainKey = "vfx_star", RainTexture = "fx_sparkle", RainKind = "Emitter" },
	},
	cloudy_dragon = {
		Name = "Cloud Breath", Rarity = "Mythic", Element = "Storm", Kind = "Beam",
		Twist = "a cloud dragon spirals up, then breathes the beam on the dive",
		Actor = { Key = "vfx_sig_cloud_dragon", At = "Source", Motion = "SpiralUp", Beat = "Charge", Tint = "Core" },
		Beats = { Charge = 0.65 },
	},
	starlight_unicorn = {
		Name = "Wishing Star", Rarity = "Mythic", Element = "Celestial", Kind = "Heal",
		Twist = "a giant wishing star rises and showers allies",
		Actor = { Key = "vfx_sig_wish_star", At = "Above", Motion = "Rise", Beat = "Charge", Tint = "Mid" },
		Layers = { { Id = "SigShower", Kind = "Emitter", Texture = "fx_stars", Beat = "Travel", At = "Allies", Count = 14, Size = 1, Fall = true } },
	},
	stormfang = {
		Name = "Storm Pounce", Rarity = "Secret", Element = "Storm", Kind = "Pounce",
		Twist = "a lightning storm-wolf charges through the target",
		Actor = { Key = "vfx_sig_wolf", At = "Source", Motion = "ChargeThrough", Beat = "Travel", Tint = "Core" },
		Layers = { { Id = "SigBolts", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Count = 3 } },
	},
	eclipse_dragon = {
		Name = "Eclipse Nova", Rarity = "Secret", Element = "Shadow", Kind = "Blast",
		Twist = "the battle dims for a moment; a black-sun ring bursts",
		DimWorld = 0.6,
		Actor = { Key = "vfx_sig_black_sun", At = "Target", Motion = "Burst", Beat = "Impact", Color = rgb(20, 10, 30) },
	},
	obsidian_phoenix = {
		Name = "Shadowflame Storm", Rarity = "Secret", Element = "Flame", Kind = "Storm",
		Twist = "black-flame wings sweep the field; dark fire rains",
		Palette = { Core = rgb(255, 150, 240), Mid = rgb(150, 40, 170), Edge = rgb(40, 12, 44), Smoke = rgb(30, 16, 36) },
		Tints = { Rain = rgb(170, 70, 210) }, -- the baked fire sheet darkened to shadow-fire
		Actor = { Key = "vfx_sig_phoenix_wing", At = "Above", Motion = "Sweep", Beat = "Charge", Color = rgb(40, 16, 48), Scale = 1.4 },
	},
	phantom_kitsune = {
		Name = "Foxfire Ward", Rarity = "Secret", Element = "Shadow", Kind = "Shield",
		Twist = "nine ghost fox-fire orbs circle each ally",
		Palette = { Core = rgb(220, 255, 250), Mid = rgb(124, 252, 228), Edge = rgb(60, 150, 170) },
		Actor = { Key = "vfx_sig_fox_orb", At = "Allies", Motion = "Orbit", Beat = "Travel", Count = 9, Scale = 0.5, Tint = "Mid" },
	},
	magma_cub = {
		Name = "Lava Slam", Rarity = "Secret", Element = "Flame", Kind = "Blast",
		Twist = "erupts from a lava crack; magma spikes ring the target",
		Layers = { { Id = "SigLavaCrack", Kind = "Decal", Texture = "fx_crack", Beat = "Charge", At = "Source", Color = rgb(255, 150, 80), Size = 5, Seconds = 1.0 } },
		Actor = { Key = "vfx_sig_lava_spike", At = "Target", Motion = "RingRise", Beat = "Impact", Count = 5, Tint = "Mid" },
	},
	rime_wyrmling = {
		Name = "Glacier Breath", Rarity = "Secret", Element = "Frost", Kind = "Freeze",
		Twist = "breathes a glacier that rises around the target",
		Core = { Key = "vfx_sig_glacier" },
		Layers = { { Id = "SigBreath", Kind = "Beam", Beat = "Travel", At = "Path", Tint = "Core", Width = 2 } },
	},
	hydralotl = {
		Name = "Void Fangs", Rarity = "Secret", Element = "Shadow", Kind = "Rally",
		Twist = "void serpent heads rise behind the pet and roar",
		Actor = { Key = "vfx_sig_serpent", At = "Behind", Motion = "RiseRoar", Beat = "Charge", Count = 3, Tint = "Mid" },
	},
}

----------------------------------------------------------------------
-- Rarity helpers
----------------------------------------------------------------------
local function cleanRarity(rarity)
	return (type(rarity) == "string" and rarityOrder[rarity]) and rarity or nil
end

local function cleanStage(stage)
	if not finite(stage) then
		return 0
	end
	return max(0, min(2, floor(stage)))
end

function AttackFxCatalog.BandOf(rarity)
	return AttackFxCatalog.Bands[cleanRarity(rarity) or "Common"]
end

function AttackFxCatalog.SizeOf(rarity, stage)
	local size = AttackFxCatalog.Sizes[cleanRarity(rarity) or "Common"]
	local bonus = AttackFxCatalog.StageBonus[cleanStage(stage)] or 0
	return min(AttackFxCatalog.SizeCap, size * (1 + bonus))
end

----------------------------------------------------------------------
-- Resolver
----------------------------------------------------------------------
local REACTIONS = AttackFxCatalog.Reactions
local HIT_AT = { Projectile = "Target", Swipe = "Target", Ground = "Target", Area = "Target", Self = "Self", Allies = "Allies" }

-- the attack definition: { Core, Beats, Skip, Layers (lists: kind / reaction layers), Detail (lists: the attack's own
-- element detail, e.g. Nature's thorns), Slots (list), Alive?, Extras? (= the element's impact detail), Kind?, Shape?,
-- Text, Special? }
local function attackDef(req, element, sig)
	local attack = req.Attack
	if attack == "Melee" or attack == "Ranged" then
		local entry = element[attack]
		local base = AttackFxCatalog.Basic[attack]
		local beats = copy(base.Beats)
		if attack == "Melee" and entry.Path == "Ground" then
			beats.Travel = base.GroundTravel
		end
		local d = tonumber(req.Distance)
		if attack == "Melee" and base.LeapTravel and finite(d) then
			local lt = base.LeapTravel
			beats.Travel = beats.Travel + max(0, min(lt.Extra, (d - lt.Near) * lt.PerStud))
		end
		local detail = {} -- (no holes: ipairs) the attack's own layers, then the element's for this attack
		detail[#detail + 1] = base.Layers
		detail[#detail + 1] = entry.Layers
		return {
			Core = entry, Beats = beats, Skip = base.Skip or {}, Swap = base.Swap, Shot = base.Shot == true, BurstBoost = base.BurstBoost, Layers = {},
			LowKeep = entry.LowKeep, Drop = entry.Drop,
			Detail = detail, Slots = { entry }, Alive = true, Extras = true, Text = entry.Text,
		}
	elseif attack == "Element" then
		local shape = req.Shape
		if shape == nil then
			local bc = lazy("BattleCatalog")
			local ea = bc and type(bc.ElementAttacks) == "table" and bc.ElementAttacks[req.Element]
			shape = type(ea) == "table" and ea.Shape or "Cone"
		end
		local def = AttackFxCatalog.Shapes[shape]
		if not def then
			return nil
		end
		local area = element.Area or {}
		local core = copy(def.Core)
		if area.Key then
			core.Key, core.Count = area.Key, area.Count
		end
		return { Core = core, Beats = copy(def.Beats), Skip = { Afterimage = true }, Layers = {}, Detail = { area.Layers }, Slots = {}, Alive = true, Extras = true, Shape = shape, Text = def.Text }
	elseif attack == "Special" then
		local kind = req.Kind
		if kind == nil and sig then
			kind = sig.Kind
		end
		local def = type(kind) == "string" and AttackFxCatalog.Specials[kind]
		if not def then
			return nil
		end
		return { Core = def.Core, Beats = copy(def.Beats), Skip = def.Skip or {}, Layers = { def.Layers }, Detail = {}, Slots = { def.Slots }, Alive = true, Extras = def.Detail ~= false, Kind = kind, Text = def.Text, Special = true, BurstShape = def.BurstShape, LowKeep = def.LowKeep }
	end
	local def = REACTIONS[attack]
	if not def then
		return nil
	end
	return { Core = def.Core, Beats = copy(def.Beats), Skip = def.Skip or {}, Layers = { def.Layers }, Detail = {}, Slots = { def.Slots }, Alive = false, Extras = false, Text = def.Text }
end

local function slotsOf(def, element, sig)
	local refs = {
		Burst = element.Burst, Trail = element.Trail, Ground = element.Ground, Motif = element.Motif, Arc = element.Arc,
		RainKey = element.Rain.Key, RainTexture = element.Rain.Texture, RainKind = element.Rain.Kind or "Emitter",
	}
	for i = 1, #def.Slots do
		local s = def.Slots[i]
		if type(s) == "table" then
			for k in pairs(refs) do
				if s[k] ~= nil then
					refs[k] = s[k]
				end
			end
		end
	end
	if sig and type(sig.Slots) == "table" then
		for k, v in pairs(sig.Slots) do
			refs[k] = v
		end
	end
	return refs
end

local function ref(v, refs)
	if type(v) == "string" and string.sub(v, 1, 1) == "$" then
		return refs[string.sub(v, 2)]
	end
	return v
end

local function colourOf(spec, texture, palette, refs)
	if spec.Color ~= nil then
		return spec.Color
	end
	local t = texture and AttackFxCatalog.Textures[texture]
	if t and t.Baked then
		return WHITE
	end
	local tint = ref(spec.Tint, refs) or "Mid"
	return palette[tint] or palette.Mid
end

-- one concrete layer from a template, or nil when it has nothing to draw (an Emitter without a sheet)
local function buildLayer(id, tpl, ctx, scale)
	local layer = copy(tpl)
	layer.Id = id
	layer.Kind = ref(tpl.Kind, ctx.refs)
	layer.Texture = ref(tpl.Texture, ctx.refs)
	layer.Key = ref(tpl.Key, ctx.refs)
	if layer.Kind == "Emitter" and layer.Texture == nil then
		return nil
	end
	if layer.Kind == "Light" or layer.Kind == "Ring" or layer.Kind == "Mesh" then
		layer.Texture = nil
	end
	local at = tpl.At
	if at == "$Hit" then
		at = ctx.hitAt
	end
	layer.At = at
	layer.Color = colourOf(tpl, layer.Texture, ctx.palette, ctx.refs)
	if ctx.tints and ctx.tints[id] then
		layer.Color = ctx.tints[id]
	end
	if finite(tpl.Count) then
		layer.Count = max(1, floor(tpl.Count * (scale or ctx.countScale) + 0.5))
	end
	layer.Tint = nil
	layer.From = nil
	layer.Except = nil
	return layer
end

local function addExtras(out, list, tier, ctx, scale)
	if type(list) ~= "table" then
		return
	end
	for _, tpl in ipairs(list) do
		if (tpl.From or "Common") == tier and not (type(tpl.Except) == "table" and (tpl.Except[ctx.attack] or (ctx.kind and tpl.Except[ctx.kind])))
			and not (ctx.drop and ctx.drop[tpl.Id]) then
			local layer = buildLayer(tpl.Id, tpl, ctx, scale)
			if layer then
				out[#out + 1] = layer
			end
		end
	end
end

local function aliveOf(element, palette, countScale)
	local a = copy(element.Alive)
	a.Color = colourOf(element.Alive, a.Texture, palette, {})
	a.Count = max(1, floor((a.Count or 1) * countScale + 0.5))
	a.Tint = nil
	return a
end

function AttackFxCatalog.Resolve(req)
	if type(req) ~= "table" then
		return nil
	end
	local petId = type(req.PetId) == "string" and req.PetId or nil
	local sig = (req.Attack == "Special" and petId) and AttackFxCatalog.Signatures[petId] or nil
	if sig and req.Kind ~= nil and req.Kind ~= sig.Kind then
		sig = nil -- a signature only replaces its own kind
	end
	local elementName = req.Element
	if elementName == nil and sig then
		elementName = sig.Element
	end
	local element = type(elementName) == "string" and AttackFxCatalog.Elements[elementName]
	if not element then
		return nil
	end
	local def = attackDef({ Attack = req.Attack, Kind = req.Kind, Shape = req.Shape, Element = elementName, Distance = req.Distance }, element, sig)
	if not def then
		return nil
	end

	local rarity = cleanRarity(req.Rarity) or "Common"
	local stage = cleanStage(req.Stage)
	local band = AttackFxCatalog.BandOf(rarity)
	local mine = req.Mine == true
	local B = AttackFxCatalog.Beats

	local palette = merge(copy(element.Palette), sig and sig.Palette)
	palette.White = WHITE
	local refs = slotsOf(def, element, sig)

	-- core
	local core = copy(def.Core)
	merge(core, sig and sig.Core)
	core.Key = ref(core.Key, refs)
	core.Text = nil
	core.Layers = nil
	for slotName in pairs(refs) do
		core[slotName] = nil -- slot overrides that rode on the element's Melee / Ranged entry
	end
	local look = AttackFxCatalog.CoreLook[band]
	core.Color = palette[look.Color] or palette.Mid
	core.InnerColor = look.Inner and palette[(look.Inner == "White" and element.PlasmaColor) or look.Inner] or nil -- (Earth's band 4: a gold-hot heart)
	core.RimColor = look.Rim and palette[look.Rim] or nil
	core.RimShift = look.RimShift == true
	core.Glow = look.Glow
	core.Upgraded = look.Upgraded == true
	if not (core.KeepMaterial and core.Material) then -- the Shield shell / Freeze cage stay Glass at every band
		core.Material = look.Material or core.Material or element.Material or "Neon"
	end
	if core.Path == "Projectile" and not core.Stretch then
		core.Speed = core.Speed or (def.Shot and B.RangedSpeed) or B.ProjectileSpeed
	end

	-- beats
	local beats = merge(def.Beats, sig and sig.Beats)
	local special = def.Special == true
	local chargeStep = special and 0.05 or B.ChargeStep
	local charge = beats.Charge or 0
	if charge > 0 then
		charge = min(special and B.SpecialChargeMax or B.ChargeMax, charge + chargeStep * (band - 1))
	end
	local travel = beats.Travel
	if core.Speed then
		local d = tonumber(req.Distance)
		if not finite(d) or d < 0 then
			d = B.DefaultDistance
		end
		travel = min(B.TravelMax, d / core.Speed)
		if def.Shot then
			travel = max(travel, B.MinTravel) -- a ranged shot is always seen flying (player note 1)
		end
	end
	local linger = beats.Linger or 0.5
	if req.Attack ~= "Hurt" then
		linger = linger + B.LingerStep * (band - 1)
	end
	local out = {
		Charge = charge,
		Release = beats.Release or B.Release,
		Travel = travel or 0,
		Impact = beats.Impact or B.Impact,
		Linger = min(B.LingerMax, linger),
		MinTravel = def.Shot and min(travel or 0, B.MinTravel) or nil, -- the engine never cuts the shot's flight below this
	}

	-- layers: the ladder up to this rarity, each tier followed by the kind layers, the attack's and the element's impact
	-- detail and the signature layers of that tier (detail is From = "Common": every rarity shows it)
	local ctx = {
		refs = refs,
		palette = palette,
		hitAt = HIT_AT[core.Path] or "Target",
		countScale = AttackFxCatalog.CountScale[band],
		detailScale = AttackFxCatalog.DetailScale[band],
		tints = (element.Tints or (sig and sig.Tints)) and merge(copy(element.Tints or {}), sig and sig.Tints) or nil,
		attack = req.Attack,
		kind = def.Kind, -- the resolved kind (a signature special may come with Kind nil: Task 8 review)
		drop = def.Drop, -- the element's Melee / Ranged Drop: shared attack layers it replaces (Water's shot: no Boom ball)
	}
	local layers = {}
	local myOrder = rarityOrder[rarity]
	for _, step in ipairs(AttackFxCatalog.Ladder) do
		if rarityOrder[step.Tier] > myOrder then
			break
		end
		for _, ladderId in ipairs(step.Add) do
			if not def.Skip[ladderId] then
				local id = (def.Swap and def.Swap[ladderId]) or ladderId -- (Ranged: Slash -> MuzzleRing, DoubleArc -> ShotArcs)
				local layer = buildLayer(id, AttackFxCatalog.LayerSlots[id], ctx)
				if layer then
					if id == "Burst" and def.BurstShape then
						layer.Shape = def.BurstShape
					end
					if id == "Burst" and def.BurstBoost then -- (the ranged impact explosion, player note (b))
						layer.Size = (layer.Size or 1) * def.BurstBoost.Size
						layer.Count = max(1, floor((layer.Count or 1) * def.BurstBoost.Count + 0.5))
					end
					if id == "Burst" and refs.Burst == element.Burst then
						layer.Motion = element.BurstMotion -- e.g. Water's geyser column, Shadow's void implosion
						local bs = element.BurstScale -- (Task 9: the element's own burst size / count, tuned in Studio)
						if bs then
							layer.Size = (layer.Size or 1) * (bs.Size or 1)
							layer.Count = max(1, floor((layer.Count or 1) * (bs.Count or 1) + 0.5))
							if finite(bs.Transparency) then -- (a see-through burst: the target stays readable inside it)
								layer.Transparency = bs.Transparency
							end
						end
						if finite(element.BurstLight) then -- (Task 9: an additive burst summed to white on the pale arena)
							layer.LightEmission = element.BurstLight
						end
						if element.BurstAt and layer.At == "Target" then -- (Task 9: Water's geyser erupts from the ground)
							layer.At = element.BurstAt
						end
					end
					layers[#layers + 1] = layer
				end
			end
		end
		for _, list in ipairs(def.Layers) do
			addExtras(layers, list, step.Tier, ctx)
		end
		for _, list in ipairs(def.Detail) do
			addExtras(layers, list, step.Tier, ctx, ctx.detailScale)
		end
		if def.Extras then
			addExtras(layers, element.Detail, step.Tier, ctx, ctx.detailScale)
		end
		if sig then
			addExtras(layers, sig.Layers, step.Tier, ctx)
		end
	end

	local recipe = {
		Element = elementName,
		Attack = req.Attack,
		Kind = def.Kind,
		Shape = def.Shape,
		Rarity = rarity,
		Stage = stage,
		Band = band,
		Size = AttackFxCatalog.SizeOf(rarity, stage),
		Density = mine and 1 or AttackFxCatalog.OthersDensity,
		CameraPunch = mine and band >= 3,
		ScreenGlow = mine and band == 4,
		Signature = sig and petId or nil,
		Palette = palette,
		Text = def.Text,
		Beats = out,
		ImpactAt = out.Charge + out.Release + out.Travel,
		Core = core,
		Layers = layers,
		Alive = def.Alive and aliveOf(element, palette, ctx.detailScale) or {},
		LowKeep = {},
	}
	-- Low quality's second emitter after the Burst (AttackFx: MAX_EMITTERS.Low 2): the kind's pick, then the attack's,
	-- then the element's; the engine keeps the first one this effect has
	for _, list in ipairs({ def.LowKeep or {}, element.LowKeep or {} }) do
		for _, id in ipairs(list) do
			recipe.LowKeep[#recipe.LowKeep + 1] = id
		end
	end
	if sig then
		local actor = copy(sig.Actor)
		if actor then
			actor.Color = actor.Color or palette[actor.Tint or "Mid"] or palette.Mid
			actor.Tint = nil
		end
		recipe.Sig = { Name = sig.Name, Twist = sig.Twist, Actor = actor, DimWorld = sig.DimWorld }
	end
	return recipe
end

----------------------------------------------------------------------
-- Unit: what a battle unit's effects look like (from a BattleSim unitInfo)
----------------------------------------------------------------------
local function rarityOfPet(id)
	local pc = lazy("PetCatalog")
	if not pc or type(pc.Get) ~= "function" or type(id) ~= "string" then
		return nil
	end
	local ok, def = pcall(pc.Get, id)
	return ok and type(def) == "table" and cleanRarity(def.Rarity) or nil
end

-- a hybrid's rarity when its record gave none: the higher of its body and style pets (PetKeys hybridDef: higherRarity)
local function hybridRarity(look)
	local body, style = rarityOfPet(look.BodyId), rarityOfPet(look.StyleId)
	if body and style then
		return (rarityOrder[style] > rarityOrder[body]) and style or body
	end
	return body or style
end

function AttackFxCatalog.Unit(info)
	if type(info) ~= "table" then
		info = {}
	end
	local look = type(info.look) == "table" and info.look or {}
	local petId = type(info.petId) == "string" and info.petId or nil
	if petId == nil and type(info.key) == "string" and info.key ~= "" then
		petId = string.match(info.key, "^([^@]+)") -- "cat@Golden" -> "cat"; "hyb:<uid>@Golden" -> "hyb:<uid>"
	end
	local keyBase = type(info.key) == "string" and string.match(info.key, "^([^@]+)") or nil
	local rarity = cleanRarity(info.rarity) or cleanRarity(info.Rarity) or cleanRarity(look.Rarity)
		or rarityOfPet(petId) or rarityOfPet(keyBase) or hybridRarity(look) or "Common"
	local element = nil
	if type(info.elements) == "table" and type(info.elements[1]) == "string" then
		element = info.elements[1]
	elseif type(info.element) == "string" then
		element = info.element
	end
	if element ~= nil and not AttackFxCatalog.Elements[element] then
		element = nil
	end
	return {
		Element = element,
		Rarity = rarity,
		Stage = cleanStage(info.evo),
		PetId = petId,
		Ranged = info.ranged == true,
	}
end

return AttackFxCatalog
