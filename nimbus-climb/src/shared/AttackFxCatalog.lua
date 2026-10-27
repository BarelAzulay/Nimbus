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
--   Specials[kind]                              "Specials (the 9 kinds)": core, beats, extra layers, skipped ladder layers;
--                                               each element retextures them by its sheets (slots) + Elements[e].Specials
--   Reactions (Hurt / Ko / Victory / ShieldHit) the small reaction effects (ShieldHit: a shield absorbs a later hit)
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
--                                                                  "Element" | "Hurt" | "Ko" | "Victory" | "ShieldHit"; Kind = one of the 9
--                                                                  special kinds (Special; a signature pet may leave it nil);
--                                                                  Shape = "Cone" | "Circle" | "Line" (Element; nil = the element's
--                                                                  BattleCatalog shape); Distance = studs to the target (projectile
--                                                                  travel, default 14). nil for an unknown element / attack / kind /
--                                                                  shape (the caller falls back to the cube Fx).
--     recipe = { Element, Attack, Kind, Shape, Rarity, Stage, Band, Size, Density (1 mine / 0.6 others), CameraPunch
--                (mine and band >= 3; never a Quiet reaction: ShieldHit), ScreenGlow (mine and band 4; not Quiet),
--                Signature (petId | nil), Sig = { Name, Twist, Actor, DimWorld } | nil, Palette = { Core, Mid, Edge, Hot, Smoke }, Text,
--                Beats = { Charge, Release, Travel, Impact, Linger, MinTravel? } (seconds), ImpactAt (= Charge + Release +
--                Travel: the engine starts the effect so that impact lands on the server event, never later, except
--                that a basic Ranged shot keeps MinTravel of flight: player note 1, the shot is always seen crossing),
--                Core = { Key (vfx_* MeshIds key), Color, Material, Path ("Projectile"|"Swipe"|"Ground"|"Self"|"Allies"|
--                "Area"), Glow, InnerColor?, RimColor?, RimShift?, Upgraded, Speed?, Count?, Scale?, ... shape flags },
--                LowKeep = { layerId, ... } (Low quality keeps the Burst and then the first of these that the effect has: the
--                element's most characteristic emitter, chosen on purpose, not left to the engine's rank),
--                Layers = { { Id, Kind ("Emitter"|"Beam"|"Trail"|"Light"|"Ring"|"Decal"|"Mesh"), Beat, At, Texture?, Key?,
--                Color, Count?, Size?, Motion?, Delay?, Transparency? (0..1: lifts the layer's whole fade, see-through),
--                LightEmission? (overrides the sheet's / beam's default; the engine lights a layer under 0.5 by the scene
--                and starts a glow hot from 0.8), SpeedScale? (x the emitter preset's speed), KeepCount? (n: a Beam layer
--                that is the kind's / element's identity: under the 4-beam cap it gets n beams before any other layer's
--                second beam), (Studio findings round, 2026-10-27:) Height? (studs: an "Above" emitter this high over the hit
--                point instead of ABOVE x size: the Storm cloud low over its zone, the rain falls from it), Tint2? (a
--                second Palette entry -> Color2: an emitter's puffs are born in it and darken into Color: a two-tone cloud),
--                Streak? (a falling rain layer drawn as thin velocity-aligned streaks when its sheet is fx_streak), Ride?
--                (an emitter streaming off the caster through its leap: the Pounce's storm-cloud ride), Strike? (a Beam
--                layer whose bolts strike down round the hit: the Pounce slam), Level? (a vfx_ring at the hit's height,
--                not flat on the floor), OrbRadius? (a Ring's peak radius = this x the Blast orb's peak radius) ... } } (a template's
--                Except = { [Attack or special Kind] = true } leaves
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
AttackFxCatalog.AttackNames = { "Melee", "Ranged", "Special", "Element", "Hurt", "Ko", "Victory", "ShieldHit" }
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
	-- the Pounce's swap (Task 10): its Legendary afterimages are two more speed-line trails riding the leaping pet (a trail
	-- on the core would sit still on the slam point and draw nothing)
	LeapEcho = { Kind = "Trail", Texture = "fx_speedlines", Beat = "Travel", At = "Self", Tint = "Mid", Afterimages = 2 },
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
	fx_leaves = { Grid = 4, Baked = true }, -- UNUSED since Task 9 (Nature's green leaves vanished on the lawn: golden pollen); kept as the textures.json mirror
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
-- leaves out). Task 9 per-element knobs (tuned in Studio: an additive burst of a pale glow sheet summed to a white ball on
-- the pale arena):
--   BurstScale = { Size, Count, Transparency?, Speed? }  x the Burst's size / count; its Transparency; Speed -> the
--                                                        Burst layer's SpeedScale (chunks flung further)
--   BurstLight   the Burst's (and the ranged Muzzle puff's) LightEmission
--   BurstAt      where the Burst sits when it would sit on the Target (Water: "Ground", the geyser from the floor)
--   PlasmaColor  the band 4 white heart's Palette entry instead of white (Earth "Core" gold, Shadow "Hot" pink)
--   Tints        { [layerId] = Color3 } (Alive = the alive detail's colour)
--   Area         { Transparency?, Layers? } the element attacks' (Cone / Circle / Line) core transparency + own layers
--   Specials     { [kind] = { Core?, Slots?, Layers?, Drop?, Tints?, LowKeep? } } (Task 10) the element's own take on a
--                special kind: Core fields merged over the kind's core, Slots re-point the kind's slots ($Wrap, $Ward ...),
--                Layers added (From = their tier), Drop = { [layerId] = true } the kind layers it leaves out, Tints for
--                this kind only. A signature pet's overrides still win.
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
		-- (Task 10) a water orb spins as it flies; the pounce lands in a splash (the geyser + ripple), not a ground crack
		Specials = {
			Blast = { Core = { Spin = true } },
			Pounce = { Drop = { SlamCrack = true } },
		},
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
			-- (Task 9: at Secret (x1.4 size, x1.25 count) the additive mantle washed the whole gap pale yellow (Task 8 review):
			-- smaller and half-lit, the fire keeps its orange)
			Layers = { { Id = "Mantle", Kind = "Emitter", Texture = "fx_flame", Beat = "Travel", At = "Core", Count = 12, Size = 2.1, LightEmission = 0.45 } },
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
		-- (Task 10) Blast / Pounce / Storm approved at check-in 2 (unchanged). The beam is a fire breath (flame tongues along
		-- it, not embers); the ward is flames licking up each bubble (Gemini: embers on a hex bubble read as tech, not fire)
		Specials = {
			Beam = { Slots = { Wrap = "fx_flame" } },
			Shield = { Slots = { Ward = "fx_flame" } },
		},
	},
	Frost = {
		-- (Task 9 round 2: Mid 150/222/248 drew near white in Neon at Secret on the pale arena: a deeper ice blue)
		Palette = { Core = rgb(240, 252, 255), Mid = rgb(118, 198, 246), Edge = rgb(70, 150, 226), Hot = rgb(255, 255, 255), Smoke = rgb(200, 230, 245) },
		Material = "Glass",
		-- (Task 9 emitter budget: Ground nil = the Mythic field is a soft frost-blue glow disc; the impact FrostRing sheet
		-- already lies on the ground)
		Burst = "fx_iceshards", BurstMotion = "Shatter", Trail = "fx_snow", Ground = nil, Motif = "fx_snow", Arc = "fx_speedlines",
		LowKeep = { "FrostRing" },
		-- (Task 9 Studio: the boosted Secret shatter was a white wall over the target; smaller, fewer shards; round 3 (c2 +
		-- Gemini): still a white blob that swallowed the target on the pale floor: smaller, see-through, half-lit)
		BurstScale = { Size = 0.5, Count = 0.7, Transparency = 0.25 },
		BurstLight = 0.35,
		-- (round 3, Gemini: the solid Neon spikes read as plastic, not ice: a little see-through)
		Melee = { Key = "vfx_spike", Path = "Ground", Count = 4, Transparency = 0.2, Text = "ice spikes burst from the ground along a path" },
		-- (Task 9 Studio: at scale 1 the pale shard vanished against a pale sky mid-flight)
		Ranged = { Key = "vfx_shard", Path = "Projectile", Text = "sharp ice shard, snow trail", Scale = 1.35, Girth = 1.3 },
		Impact = "crystal shatter + frost ring on the ground",
		Detail = {
			{ Id = "FrostRing", Kind = "Decal", Texture = "fx_frostmist", Beat = "Impact", At = "Ground", Size = 5, Seconds = 1.0 },
			-- (Task 9: a cold mist rising after the shatter, not a white fog ball on the hit frame)
			{ Id = "FrostMist", Kind = "Emitter", Texture = "fx_frostmist", Beat = "Impact", At = "$Hit", Motion = "Rise", Delay = 0.08, Count = 5, Size = 1.2 },
		},
		Alive = { Kind = "Mesh", Key = "vfx_shard", Motion = "Melt", Tint = "Mid", Count = 5, Seconds = 1.0, Text = "impact shards linger and visibly melt (~1 s)" },
		Rain = { Key = "vfx_shard", Texture = "fx_snow", Kind = "Emitter", Scale = 0.5, Text = "hail", Streak = false },
		Area = { Key = "vfx_spike", Count = 5, Transparency = 0.2 },
		-- (Task 10) the pounce lands in a ring of see-through ice spikes; the Freeze cage gets an outer ring of them from
		-- Epic (Gemini: the cage's own rarity step)
		Specials = {
			Pounce = { Layers = { { Id = "IceSpikes", Kind = "Mesh", Key = "vfx_spike", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 4, Scale = 0.6, Transparency = 0.2 } } },
			Freeze = { Layers = { { Id = "IceSpikes", Kind = "Mesh", Key = "vfx_spike", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 5, Scale = 0.55, Transparency = 0.2, From = "Epic" } } },
		},
	},
	Nature = {
		-- pink / yellow / cream only: Nature must read on green grass (no green-only colour anywhere)
		-- (Task 9 Studio c2 + Gemini: in Neon at Secret the light pink Mid and the cream Edge drew white on the pale floor:
		-- the band 4 roots / vines (shifting Mid -> Edge) were white-cream ghosts over the target. A deeper rose pink and
		-- a deep rose Edge (round 3: an amber Edge turned the Secret roots neon yellow, "electricity, not plants" - Gemini);
		-- the yellow stays in Core: the pod glow, the pollen)
		Palette = { Core = rgb(255, 228, 120), Mid = rgb(250, 110, 170), Edge = rgb(212, 58, 128), Hot = rgb(255, 250, 214), Smoke = rgb(230, 210, 170) },
		Material = "Neon",
		Burst = "fx_petals", BurstMotion = "Burst", Trail = "fx_petals", Ground = nil, Motif = "fx_petals", Arc = "fx_speedlines",
		LowKeep = { "Thorns", "PodGlow" },
		BurstScale = { Size = 0.8, Count = 1 }, -- (Task 9: the Secret petal burst hid the target)
		Melee = {
			-- (Task 9: at Secret the roots buried the target; round 3, Gemini: still swallowed it: a little see-through)
			Key = "vfx_root", Path = "Ground", Count = 3, Scale = 0.75, Transparency = 0.2, Text = "thorny roots erupt under the target",
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
				-- (Task 9 round 3, Gemini: amber roots read as electricity / holy magic, not plants: rose pink)
				{ Id = "RootBurst", Kind = "Mesh", Key = "vfx_root", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 3, Scale = 0.6 },
				{ Id = "PodGlow", Kind = "Emitter", Texture = "fx_sparkle", Beat = "Impact", At = "$Hit", Tint = "Core", Count = 6, Size = 0.8 },
			},
		},
		Impact = "root burst + petals",
		Detail = {}, -- the petals are the Burst; the vines are the Alive detail
		-- (Task 9: at Secret (x1.4) the full-size vines buried the target: 0.7)
		Alive = { Kind = "Mesh", Key = "vfx_root", Motion = "Wrap", Tint = "Mid", Count = 3, Scale = 0.7, Seconds = 0.6, Text = "vines briefly wrap the target" },
		-- (Task 10, Gemini: a petal shower alone is spring, not an ultimate: heavy seed pods fall with the petals)
		Rain = { Key = "vfx_orb", Texture = "fx_petals", Kind = "Emitter", Scale = 0.42, Text = "seed pods and a petal shower", Streak = false },
		Area = { Key = "vfx_root", Count = 4, Transparency = 0.2 },
		-- (Task 10) roots everywhere: the seed-pod Blast and the pounce landing burst roots out of the ground; the Freeze is
		-- a ROOT cage (5 rose roots curling in round the target, not glass); the ward is a root curling up each bubble
		Specials = {
			Blast = { Core = { Scale = 0.85 }, Layers = { { Id = "RootBurst", Kind = "Mesh", Key = "vfx_root", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 3, Scale = 0.6, Transparency = 0.2 } } },
			Pounce = { Layers = { { Id = "RootBurst", Kind = "Mesh", Key = "vfx_root", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 3, Scale = 0.6, Transparency = 0.2 } } },
			Freeze = { Core = { Key = "vfx_root", Count = 5, Material = "Neon", KeepMaterial = false, Transparency = 0.2, Scale = 0.8 } },
			Shield = { Layers = { { Id = "RootWard", Kind = "Mesh", Key = "vfx_root", Beat = "Travel", At = "Allies", Motion = "Wrap", Tint = "Mid", Count = 1, Scale = 0.55, Transparency = 0.2 } } },
		},
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
		-- (fewer, smaller chunks: at full count they still read as one boulder; round 2 again; round 3 (c2 + Gemini): the
		-- Shatter's drag held the chunks in a 3-stud ball that hid the target: flung 1.9x further, a little smaller)
		BurstScale = { Size = 0.36, Count = 0.4, Speed = 1.9 },
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
		Rain = { Key = "vfx_chunk", Texture = "fx_rock", Kind = "Emitter", Scale = 1.2, Text = "a rock fall", Streak = false },
		Area = { Key = "vfx_spike", Count = 5 },
		-- (Task 10) the Blast hurls a boulder (solid rock, not a see-through orb); the pounce is a ground slam with a ring of
		-- rock spikes (its own GroundCrack is the crack: no second crack sheet); the Freeze is a STONE cage (Gemini: glass
		-- is off-theme for earth), ringed by rock spikes from Epic
		Specials = {
			Blast = { Core = { Key = "vfx_chunk", Scale = 1.3, Transparency = 0 } },
			Pounce = { Drop = { SlamCrack = true }, Layers = { { Id = "RockSpikes", Kind = "Mesh", Key = "vfx_spike", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Mid", Count = 4, Scale = 0.65 } } },
			Freeze = {
				Core = { Material = "SmoothPlastic", Transparency = 0.1 },
				Layers = { { Id = "RockSpikes", Kind = "Mesh", Key = "vfx_spike", Beat = "Impact", At = "$Hit", Motion = "Erupt", Tint = "Edge", Count = 5, Scale = 0.55, From = "Epic" } },
			},
			-- (the motif is the runtime fx_sparkle: in the rock-brown Mid it read as dull specks; the gold of the seam)
			Shield = { Tints = { Ward = rgb(255, 204, 120) } },
			Rally = { Tints = { Rouse = rgb(255, 204, 120) } },
		},
	},
	Storm = {
		Palette = { Core = rgb(224, 236, 255), Mid = rgb(110, 128, 255), Edge = rgb(60, 72, 210), Hot = rgb(255, 252, 170), Smoke = rgb(120, 124, 150) },
		Material = "Neon",
		Burst = "fx_glow", BurstMotion = "Burst", Trail = "fx_sparks", Ground = nil, Motif = "fx_sparks", Arc = "fx_lightning",
		LowKeep = { "ZigZag" },
		-- (Task 9 Studio: the fx_glow burst was a white ball and the baked white lightning vanished on a pale sky: a small
		-- blue burst, every bolt tinted the storm's blue)
		BurstScale = { Size = 0.55, Count = 0.7 },
		BurstLight = 0.4, -- (Task 9 round 2: still a white ball at Secret; half-lit the glow keeps the storm's blue)
		-- (round 2: at 120/136/255 the bolt was a faint lilac squiggle on the pale floor: a deeper electric blue)
		-- (review M1: the stray strikes too, Tints.Alive; they kept the lilac)
		Tints = { Bolt = rgb(72, 98, 255), Arcs = rgb(72, 98, 255), Crackle = rgb(72, 98, 255), Alive = rgb(72, 98, 255) },
		Melee = {
			Key = "vfx_crescent", Path = "Swipe", Text = "electric claw, crackling arcs",
			Layers = { { Id = "Arcs", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "$Hit", Count = 2 } },
		},
		Ranged = {
			-- (round 3, s4: at 0.8 the Common shard was a speck mid-gap)
			Key = "vfx_shard", Path = "Projectile", Speed = 120, Scale = 1.1, Text = "jagged lightning bolt",
			Layers = {
				-- (round 3, c2: 2.6 wide the strip's bolt wandered over a 3.6-stud band at Secret: a scribble on the floor, not
				-- one bolt; narrower and running mouth -> shot (engine), the jag stays one bolt at the shot's height; s4: at 1.3
				-- the Common bolt's line was hairline-thin)
				-- (review I1: Bolt + Crackle ask for up to 3 beams each; the engine ranks beams (the alive strikes first, the
				-- ladder's ShotArcs last, one each before any second), so under the 4-beam cap the shot draws Bolt 1 + Crackle 1
				-- + 1-2 stray strikes, + 1 ShotArc at Mythic / Secret)
				{ Id = "Bolt", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Width = 1.6, Count = 2 },
				-- the bolt crackles round the target as it strikes (beams, no emitter)
				{ Id = "Crackle", Kind = "Beam", Texture = "fx_lightning", Beat = "Impact", At = "$Hit", Count = 2 },
			},
		},
		Impact = "electric burst + zig-zag sparks",
		Detail = {
			-- (Task 9 round 3, c2: in the pale Core tint, additive, the sparks summed to a white ball round the target at Secret;
			-- the storm's blue, half-lit)
			{ Id = "ZigZag", Kind = "Emitter", Texture = "fx_sparks", Beat = "Impact", At = "$Hit", Tint = "Mid", Count = 10, Size = 1.2, LightEmission = 0.5 },
		},
		Alive = { Kind = "Beam", Texture = "fx_lightning", Motion = "Strike", Count = 2, Seconds = 0.6, Text = "stray bolts strike the ground nearby" },
		Rain = { Key = "vfx_shard", Texture = "fx_lightning", Kind = "Beam", Scale = 0.6, Text = "lightning strikes" },
		-- (round 3, c2 + Gemini: the Secret line / cone / ring read as solid plastic slabs that buried the lightning: see-
		-- through, so the bolt and the blue sparks define the strike; the bolt narrow like the shot's, one jag not a scribble)
		Area = { Transparency = 0.5, Layers = { { Id = "Bolt", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Width = 1.2 } } },
		-- (Task 10) ball lightning: the Blast's orb crackles at the hit; the Freeze cage is electric (two arcs crackle round
		-- it); the Heal is soft blue glints (Gemini: sparks rising off allies read as electrocution, not healing)
		Specials = {
			-- (KeepCount, Task 10 review I2 / M2: both bolts at every rarity; the stray strikes (alive) take what is left)
			Blast = { Layers = { { Id = "Crackle", Kind = "Beam", Texture = "fx_lightning", Beat = "Impact", At = "$Hit", Count = 2, KeepCount = 2 } } },
			Freeze = { Layers = { { Id = "Arcs", Kind = "Beam", Texture = "fx_lightning", Beat = "Impact", At = "$Hit", Count = 2, KeepCount = 2 } } },
			Heal = { Slots = { Motif = "fx_sparkle" }, Tints = { Spiral = rgb(150, 170, 255) } },
		},
	},
	Celestial = {
		Palette = { Core = rgb(255, 250, 224), Mid = rgb(255, 212, 104), Edge = rgb(236, 164, 64), Hot = rgb(255, 255, 255), Smoke = rgb(255, 236, 190) },
		Material = "Neon",
		Burst = "fx_stars", BurstMotion = "Burst", Trail = "fx_sparkle", Ground = nil, Motif = "fx_stars", Arc = "fx_speedlines",
		LowKeep = { "Rays" },
		BurstScale = { Size = 0.6, Count = 0.65 }, -- (Task 9: the star burst + rays were a white flare over the target)
		-- (round 3, c2: at Secret the shot's stars + rays still summed to a pale flare that hid the target: half-lit, the
		-- burst (and the muzzle puff) keeps its gold)
		BurstLight = 0.35,
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "golden starlight slash" },
		Ranged = { Key = "vfx_star", Path = "Projectile", Spin = true, Text = "shooting star, sparkle tail" },
		Impact = "star burst + light rays",
		Detail = {
			-- (round 3, c2: 2.6-stud rays, half-lit by the sheet, were the pale flare round the target at Secret: smaller, dimmer)
			{ Id = "Rays", Kind = "Emitter", Texture = "fx_rays", Beat = "Impact", At = "$Hit", Count = 3, Size = 1.8, LightEmission = 0.3 },
		},
		-- (round 3, c2: in the pale Core tint the lines read as stray white sticks in the sky: starlight gold)
		Alive = { Kind = "Beam", Motion = "Connect", Tint = "Mid", Count = 4, Seconds = 0.8, Text = "constellation lines join the stars" },
		Rain = { Key = "vfx_star", Texture = "fx_stars", Kind = "Emitter", Scale = 0.5, Text = "falling stars", Streak = false },
		-- (round 3, c2 + Gemini: the line / cone / ring cores read as solid yellow tape: see-through starlight)
		Area = { Transparency = 0.45 },
		-- (Task 10) the Blast is a spinning star; stars wheel round the Freeze cage (Gemini: a plain glass cage had no cosmos;
		-- outside the cage, so the target stays readable)
		Specials = {
			Blast = { Core = { Key = "vfx_star", Spin = true } },
			Freeze = { Layers = { { Id = "StarSpin", Kind = "Emitter", Texture = "fx_stars", Beat = "Linger", At = "$Hit", Spiral = true, Count = 8, Size = 0.8 } } },
		},
	},
	Shadow = {
		Palette = { Core = rgb(214, 156, 255), Mid = rgb(128, 72, 178), Edge = rgb(44, 22, 66), Hot = rgb(255, 96, 224), Smoke = rgb(60, 40, 80) },
		Material = "Neon",
		-- the void implosion is the Burst itself (BurstMotion "Implode": the fx_voidring contracts inward), then the glass
		Burst = "fx_voidring", BurstMotion = "Implode", Trail = "fx_wisps", Ground = nil, Motif = "fx_wisps", Arc = "fx_speedlines",
		LowKeep = { "Glass" },
		-- (Task 9: the void rings swarmed into a ball twice the pet's size; round 2: still a swarm of glowing lilac rings at
		-- Secret: fewer, smaller, unlit so they read as a dark void, not a light)
		BurstScale = { Size = 0.42, Count = 0.45 },
		BurstLight = 0,
		-- (round 3, Gemini on c0: a white-hot heart is a light, the opposite of a void: the Secret heart burns the glitch
		-- pink inside the purple shell)
		PlasmaColor = "Hot",
		Melee = { Key = "vfx_crescent", Path = "Swipe", Text = "dark claw, purple wisps" },
		Ranged = { Key = "vfx_orb", Path = "Projectile", Text = "shadow orb pulling wisps" },
		Impact = "void implosion, then black glass shatters with glitchy purple sparks",
		Detail = {
			-- (round 3, Gemini: bigger dark shards that block the pale floor read as glass breaking, not dust)
			{ Id = "Glass", Kind = "Emitter", Texture = "fx_darkglass", Beat = "Impact", At = "$Hit", Delay = 0.12, Count = 8, Size = 1.55 },
			{ Id = "GlitchSparks", Kind = "Emitter", Texture = "fx_sparks", Beat = "Impact", At = "$Hit", Tint = "Hot", Delay = 0.12, Count = 8, Size = 1 },
		},
		Alive = { Kind = "Decal", Motion = "Darken", Tint = "Edge", Count = 2, Seconds = 0.9, Text = "the floor darkens under the wisps" },
		Rain = { Key = "vfx_shard", Texture = "fx_wisps", Kind = "Emitter", Scale = 0.5, Text = "falling shadow shards" },
		-- (round 3, c0 + Gemini: the line / cone / ring cores were solid glowing magenta slabs (arcane, not void): see-through)
		Area = { Transparency = 0.4 },
		-- (Task 10, Gemini: wisps streaming off a hasted ally read as a curse: glitch-pink sparks; the wind lines stay purple)
		Specials = {
			Haste = { Slots = { Gust = "fx_sparks" }, Tints = { Gust = rgb(255, 96, 224) } },
		},
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

-- Task 10 (the 9 kinds for every element; Gemini design pass, see task-10-report.md). Each kind draws the element's own
-- sheets through slots: $Burst (the impact burst), $Trail, $Motif, $Arc, $Rain*, and the kind slots below, which an
-- element may re-point in Elements[e].Specials[kind].Slots:
--   $ElementBurst / $BurstMotion  the element's impact sheet and its motion, even where the kind swaps $Burst (Rally's roar)
--   $Wrap   the Beam's particles streaming along it (default the element's Trail)
--   $Ward   the Shield's element rising over each bubble (default Motif)
--   $Gust   the Haste's element streaming off each ally (default Trail)
-- Kind fields besides Core / Beats / Layers / Slots / Skip / LowKeep: Swap (ladder layer -> LayerSlots template, like
-- Basic.Ranged), CoreCount[band] (the core's piece count per band: rarity = more), ThickBand[band] (the Beam's thickness
-- per band). Every kind fits the effect caps (6 emitters, 4 beams, 4 trails, 3 lights: Rally / Freeze have their own
-- light, so the Epic Flash is skipped).
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
		-- (Task 10, Gemini: a wider beam by band reads as rarer without one more emitter; x Size 1.0 .. 1.4)
		ThickBand = { 1.1, 1.3, 1.5, 1.7 },
		Beats = { Charge = 0.5, Travel = 0.1, Linger = 0.5 },
		Layers = {
			-- (KeepCount, Task 10 review I2: the kind's identity, "wrapped in spiral arcs", keeps both arcs under the 4-beam
			-- cap; the element's alive beams take what is left, never the second arc (a third arc from Legendary when there
			-- is room))
			{ Id = "Spiral", Kind = "Beam", Texture = "$Arc", Beat = "Travel", At = "Path", Tint = "Edge", Spiral = true, Count = 2, KeepCount = 2 },
			{ Id = "Flare", Kind = "Emitter", Texture = "fx_glow", Beat = "Impact", At = "$Hit", Tint = "Hot", Count = 4, Size = 3 },
			-- (Task 10) the element streams along the beam while it holds (fire licks, a water jet's drops, snow, petals,
			-- dust, sparks, sparkle, wisps): sparse and small, drifting off the beam (Gemini: a dense wrap looks messy)
			{ Id = "Wrap", Kind = "Emitter", Texture = "$Wrap", Beat = "Travel", At = "Path", Along = true, Tint = "Mid", Count = 9, Size = 0.9 },
		},
		-- (no Afterimage: the beam does not move, a trail on it would draw nothing; Task 10 review I2: no Mythic double
		-- crescent either, a slash arc on a beam reads as nothing and took one of the 4 beams from the spiral: the wider
		-- ThickBand marks Mythic / Secret)
		Skip = { Trail = true, Slash = true, Afterimage = true, DoubleArc = true },
	},
	Pounce = {
		Text = "crouch, a leap with afterimages, a slam landing that cracks the ground",
		Core = { Key = "vfx_ring", Path = "Ground", Grow = 2.2 },
		Beats = { Charge = 0.4, Travel = 0.35, Linger = 0.6 },
		Layers = {
			-- (Task 10: the trail rides the leaping pet (AttackFx), one at Common; the Legendary afterimages add two more)
			{ Id = "Leap", Kind = "Trail", Texture = "fx_speedlines", Beat = "Travel", At = "Self", Tint = "Edge", Afterimages = 1 },
			{ Id = "SlamCrack", Kind = "Decal", Texture = "fx_crack", Beat = "Impact", At = "Ground", Size = 6, Seconds = 0.8 },
		},
		Swap = { Afterimage = "LeapEcho" },
		Skip = { Trail = true },
	},
	Storm = {
		Text = "a cloud gathers over the target and rains the element",
		Core = { Key = "$RainKey", Path = "Area", Count = 8, Fall = true },
		CoreCount = { 5, 6, 7, 8 }, -- (Task 10, Gemini: the rain grows with rarity)
		Beats = { Charge = 0.6, Travel = 0.45, Linger = 0.7 },
		-- (Studio findings round, Gemini top 5 #1: an opaque navy / purple blob, size 3-6, high over the zone, read as a paint
		-- smear behind it) a smaller, partly see-through cloud LOW over the zone (Height 4.5 studs over the hit point), its
		-- puffs born in the lighter Mid and darkening into the Edge (a lit rim / underside), half-lit. The rain falls from it
		-- as thin velocity-aligned streaks (fx_streak) where the element's rain is a liquid / fire / shadow (Water, Flame,
		-- Shadow); hail, petals, rocks and stars keep their own tumbling sheets (Rain.Streak = false), Storm rains lightning
		Layers = {
			{ Id = "Cloud", Kind = "Emitter", Texture = "fx_stormcloud", Beat = "Charge", At = "Above", Tint = "Edge", Tint2 = "Mid", Count = 5, Size = 2.6, Height = 4.5, Transparency = 0.42, LightEmission = 0.22 },
			{ Id = "Rain", Kind = "$RainKind", Texture = "$RainStreak", Beat = "Travel", At = "Above", Tint = "Mid", Count = 12, Size = 0.8, Streak = true },
		},
		LowKeep = { "Cloud" },
		-- (Task 10: no Mythic double crescent: a slash arc in a rain cloud reads as nothing)
		Skip = { Trail = true, Slash = true, Afterimage = true, DoubleArc = true },
	},
	Freeze = {
		Text = "a crystal cage in the element's colour locks the target",
		Core = { Key = "vfx_cage", Path = "Ground", Material = "Glass", KeepMaterial = true, Rise = true }, -- Glass at every band
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.7 },
		Layers = { { Id = "Lock", Kind = "Light", Beat = "Impact", At = "$Hit", Tint = "Core", Brightness = 2, Range = 8 } },
		-- (Task 10: the Lock is the flash (3 lights at Secret); no double crescent on a cage)
		Skip = { Trail = true, Slash = true, Afterimage = true, DoubleArc = true, Flash = true },
	},
	Heal = {
		Text = "spirals of glowing petals rise around allies, plus-shaped sparkles",
		Core = { Key = "vfx_ring", Path = "Allies", Grow = 1.5 },
		Beats = { Charge = 0.45, Travel = 0.3, Linger = 0.7 },
		Slots = { Burst = "fx_sparkle" },
		Layers = { { Id = "Spiral", Kind = "Emitter", Texture = "$Motif", Beat = "Travel", At = "Allies", Tint = "Core", Spiral = true, Count = 10, Size = 1 } },
		LowKeep = { "Spiral" },
		BurstShape = "Plus", -- (Task 10: the 4-point glint held upright, not spinning: a "+" (AttackFx))
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
	Shield = {
		Text = "a hexagon bubble around each ally, rippling when hit",
		-- (Studio findings round, Gemini top 5 #2: the 7-stud domes overlapped into one blob and hid the name tags) each
		-- dome fits ITS ally: radius Fit x the ally's half-width, never touching the next ally's dome, its top at most
		-- TopClear studs over the ally's head (the name tag stays clear), ~30 % smaller; more see-through. Glass at every band
		Core = { Key = "vfx_shell", Path = "Allies", Material = "Glass", KeepMaterial = true, Transparency = 0.72, Fit = 1.35, TopClear = 0.3 },
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.8 },
		Slots = { Burst = "fx_hexshield" },
		-- (Task 10: the element rises over each bubble: the hex bubble alone had no element but its colour)
		Layers = { { Id = "Ward", Kind = "Emitter", Texture = "$Ward", Beat = "Travel", At = "Allies", Motion = "Rise", Tint = "Mid", Count = 7, Size = 1 } },
		LowKeep = { "Ward" },
		Skip = SUPPORT_SKIP,
		Detail = false, -- lands on allies: no element impact detail
	},
	Rally = {
		Text = "the pet roars; rings pulse outward; allies light up",
		Core = { Key = "vfx_ring", Path = "Self", Grow = 4, Pulses = 3 },
		Beats = { Charge = 0.45, Travel = 0.25, Linger = 0.6 },
		Slots = { Burst = "fx_shock" },
		Layers = {
			{ Id = "AllyGlow", Kind = "Light", Beat = "Impact", At = "Allies", Tint = "Core", Brightness = 2, Range = 8 },
			-- (Task 10) the roar: a burst of the element's own impact sheet from the pet (fire, a geyser, an ice shatter ...)
			{ Id = "Roar", Kind = "Emitter", Texture = "$ElementBurst", Motion = "$BurstMotion", Beat = "Release", At = "Self", Tint = "Mid", Count = 8, Size = 1.6 },
			-- each ally lights up: a ring rises under it and the element's motif flares on it (one light at the allies'
			-- centre was all there was)
			{ Id = "AllyRing", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "Allies", Tint = "Mid", Grow = 1.3, Transparency = 0.35 },
			{ Id = "Rouse", Kind = "Emitter", Texture = "$Motif", Beat = "Impact", At = "Allies", Motion = "Rise", Tint = "Mid", Count = 8, Size = 1 },
		},
		LowKeep = { "Roar" },
		Skip = { Trail = true, Slash = true, Afterimage = true, DoubleArc = true, Flash = true }, -- (AllyGlow is its flash)
		Detail = false, -- lands on allies: no element impact detail
	},
	Haste = {
		Text = "wind-streak trails and speed lines on allies",
		Core = { Key = "vfx_ring", Path = "Allies", Grow = 1.2 },
		Beats = { Charge = 0.4, Travel = 0.2, Linger = 0.6 },
		Slots = { Burst = "fx_streak" },
		Layers = {
			-- (Task 10: in the pale Core tint the wind read as white; the element's colour)
			{ Id = "Wind", Kind = "Trail", Texture = "fx_speedlines", Beat = "Linger", At = "Allies", Tint = "Mid" },
			-- the element streams off each ally as it speeds up (embers, drops, snow, petals, dust, sparks, sparkle)
			{ Id = "Gust", Kind = "Emitter", Texture = "$Gust", Beat = "Linger", At = "Allies", Drift = true, Tint = "Mid", Count = 10, Size = 0.9 },
		},
		LowKeep = { "Gust" },
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
	-- (Task 10 review I1, Ruling 17: "a hexagon bubble round each ally, rippling when hit") a hit the shield absorbs after
	-- the Shield's own impact: the bubble swells out a little and fades (a see-through glass shell, From / To x the pet's
	-- size) and the hex sheet pulses on it, in the shield's element colour (BattleController plays it on the victim at
	-- the hit). One emitter, no light, no charge: it plays on every absorbed hit of a 6 s shield
	ShieldHit = {
		Text = "the shield ripples: the hex bubble swells and fades as it absorbs a hit",
		-- (Studio findings round: the Shield domes fit their ally now, ~0.55 x the old shell: the ripple swells from that)
		Core = { Key = "vfx_shell", Path = "Self", Flash = true, From = 0.55, To = 0.72, Material = "Glass", KeepMaterial = true, Transparency = 0.7 },
		Beats = { Charge = 0, Release = 0, Travel = 0, Linger = 0.35 },
		Slots = { Burst = "fx_hexshield" },
		BurstBoost = { Size = 0.7, Count = 0.5 }, -- (a pulse, not the Shield's full burst)
		LowKeep = { "Burst" },
		Short = true, -- (like the Hurt: the linger does not grow with the band)
		-- (Task 10 re-review I4) no camera punch, no screen glow at any band: it plays on every absorbed hit, a Linger
		-- zone's 0.5 s ticks included, and on a boss hit beside the Hurt's own punch
		Quiet = true,
		Skip = { Charge = true, Trail = true, Slash = true, GroundGlow = true, Shockwave = true, Flash = true, Afterimage = true, Bloom = true, DoubleArc = true, Field = true, PlasmaRim = true },
	},
}

----------------------------------------------------------------------
-- Signature specials (spec table, 12 pets; Task 11, Gemini design pass in task-11-report.md). Each is its kind's
-- special at the pet's rarity (the element's take included) + the pet's own pieces. Overrides on top of the kind:
--   Core      merged over the kind's core; Key = a vfx_sig_* core; Tint / InnerTint = the Palette entries of the body /
--             its hot heart instead of the band's; NoTwin = no band 3+ quarter-turned twin
--   Palette   merged over the element's        Slots   re-point the kind's slots ($Trail, $RainKey ...)
--   Layers    added (From = their tier, default Common: every rarity the pet can be drawn at)
--   Tints     { [layerId] = Color3 } (Alive = the alive detail)          Beats   merged over the kind's
--   Skip      { [ladder layer] = true } ladder layers it trades for its own (a slash crescent on a blast reads as
--             nothing; Ember's wing glow is its bloom light: <= 3 lights at every rarity)
--   Drop      { [layer id] = true } kind / element layers it replaces     Alive = false: no alive detail
--   LowKeep   its own pick for Low quality's second emitter (before the kind's / element's)
--   Tweak     { [layer id] = { field = value } } (Studio findings round) fields set on a kind / element layer it keeps
--             (Lava Slam's see-through Dome)
--   Actor     its vfx_sig_* piece(s): { Key, At, Motion (AttackFx MOVE.Actor), Beat, Count?, Scale?, Tint | Color,
--             Material? ("Neon" default, "Glass"), Transparency?, Rim? = { Tint | Color, Scale?, Back?, Transparency? }:
--             a bigger glowing copy just behind each piece, Echo? = { Color, Count?, Lag?, Transparency? }: dimmer copies
--             trailing each piece along its path, Gap? = true (RingRise: the slot facing the caster stays open, the
--             target's flinch shows through it), Clear? / Forward? (WishRise: studs x size kept clear round the caster and
--             the local player's character / pushed toward the allies) }; built before the layers, Count x Density for
--             others' pets; Low quality draws no rim / echo
--   Core.Spread  (a Storm) the rain falls on EVERY target, round robin, not round the aimed one (Obsidian: the enemies in
--                its Storm zone)
--   DimWorld  (Eclipse Nova) seconds the battle stays dim after the impact (own pet only: AttackFx.Hooks.DimWorld ->
--             BattleController, a LightingStack preset; it dims from the cast's first frame, Undim on end / KO / teardown)
-- Every signature is checked at every rarity it can be drawn at (all 7: a budget step-down draws one band lower) x
-- stage within the effect caps (6 emitters, 4 beams, 4 trails, 3 lights, 14 pieces), its core / actor / identity
-- layers drawn at their count (smoke p7vfx_catalog, client_p7vfx_engine 17).
----------------------------------------------------------------------
AttackFxCatalog.Signatures = {
	-- the Blast orb IS a phoenix: it forms over the pet with its wings spread (a gold phoenix glowing inside a see-through
	-- orange one), flies and explodes; flame tongues stream behind it; the wings flare at the release and a warm light
	-- glows on the pet through the charge (it is the bloom light: <= 3 lights at every rarity)
	ember_phoenix = {
		Name = "Phoenix Flare", Rarity = "Legendary", Element = "Flame", Kind = "Blast",
		Twist = "spreads blazing wings, the orb is a phoenix-shaped fireball",
		Core = { Key = "vfx_sig_phoenix_wing", Scale = 0.75, Tint = "Mid", InnerTint = "Core", NoTwin = true, Transparency = 0.3 },
		Slots = { Trail = "fx_flame" },
		Skip = { Slash = true, Bloom = true },
		Layers = {
			{ Id = "SigWingGlow", Kind = "Light", Beat = "Charge", At = "Source", Tint = "Core", Brightness = 2, Range = 10 },
			{ Id = "SigWingFlare", Kind = "Emitter", Texture = "fx_flame", Beat = "Release", At = "Source", Motion = "Burst", Count = 6, Size = 1.6, LightEmission = 0.5 },
		},
		LowKeep = { "SigWingFlare" },
	},
	-- ACCEPTED DEVIATION (Task 11 fix round 1 ruling, Gemini consulted): the spec's "sun-disc shield" is built as a sun
	-- seal lying flat under each ally PLUS the gold shield bubble, not a standing disc. Keep it: a standing disc clips into
	-- the ally and hides it. (Gemini) a gold sun seal lies flat under each ally,
	-- turning and pulsing, under the gold glass bubble; light rays flare up off each at the impact; no bouncing rocks
	sunbeam_bear = {
		Name = "Golden Aegis", Rarity = "Legendary", Element = "Earth", Kind = "Shield",
		Twist = "a golden sun-disc shield with rays",
		Palette = { Core = rgb(255, 244, 196), Mid = rgb(255, 210, 110), Edge = rgb(232, 150, 40), Hot = rgb(255, 255, 230) },
		Actor = { Key = "vfx_sig_sun_disc", At = "Allies", Motion = "Seal", Beat = "Travel", Scale = 0.6, Tint = "Mid", Transparency = 0.25 },
		Layers = { { Id = "SigRays", Kind = "Emitter", Texture = "fx_rays", Beat = "Impact", At = "Allies", Count = 3, Size = 3.5, LightEmission = 0.4 } },
		Alive = false,
	},
	-- a dusk-violet cloud; dark violet stars fall out of it (Gemini, option b: the 5-point star, not the unicorn's comet;
	-- the plain Shadow Storm already rains shards) with lilac streaks (Studio findings round: the Storm rain is thin
	-- falling streaks; was lilac sparkle), into a violet pool of dusk on the floor; a lilac
	-- crescent DUSK MOON (deep violet glow behind it) rises behind the storm (Gemini's second pass: the pet had no
	-- piece of its own; it has no vfx_sig_* mesh, so the shared crescent stands upright as a moon, see the report)
	twilight_dragon = {
		Name = "Dusk Storm", Rarity = "Legendary", Element = "Shadow", Kind = "Storm",
		Twist = "a dusk-purple storm with falling shadow stars",
		Palette = { Core = rgb(236, 190, 255), Mid = rgb(150, 96, 220), Edge = rgb(64, 34, 110), Hot = rgb(255, 150, 240) },
		Slots = { RainKey = "vfx_star", RainTexture = "fx_sparkle", RainKind = "Emitter" },
		Core = { Tint = "Mid", Scale = 1.1 },
		Layers = { { Id = "SigDusk", Kind = "Decal", Beat = "Travel", At = "Ground", Tint = "Mid", Size = 7, Seconds = 1.0 } },
		Actor = { Key = "vfx_crescent", At = "Above", Motion = "MoonRise", Beat = "Charge", Scale = 1.3, Color = rgb(206, 166, 255), Transparency = 0.1, Rim = { Color = rgb(112, 56, 210), Scale = 1.12, Transparency = 0.25 } },
	},
	-- the cloud dragon spirals up round the pet through the charge, then dives down the beam onto the target (the beam is
	-- its breath) and coils once round it, rising, as it fades (Gemini's second pass: in a battle the charge is cut, the
	-- coil keeps the dragon in view); a puff of storm cloud bursts from its mouth at the release
	cloudy_dragon = {
		Name = "Cloud Breath", Rarity = "Mythic", Element = "Storm", Kind = "Beam",
		Twist = "a cloud dragon spirals up, then breathes the beam on the dive",
		Beats = { Charge = 0.65 },
		-- (Studio findings round, Gemini top 5 #5: a solid white neon bar with a glare that hid the target) the breath is
		-- 3 see-through segments with gaps (Segments / Gap: AttackFx MOVE.Stretch), the target shows through and between
		-- them; the kind's big Flare is traded for a smaller see-through one
		Core = { Transparency = 0.5, Segments = 3, Gap = 0.22 },
		Drop = { Flare = true },
		Actor = { Key = "vfx_sig_cloud_dragon", At = "Source", Motion = "SpiralUp", Beat = "Charge", Tint = "Core", Transparency = 0.1 },
		Layers = {
			{ Id = "SigCloud", Kind = "Emitter", Texture = "fx_stormcloud", Beat = "Release", At = "Source", Motion = "Burst", Tint = "Smoke", Count = 5, Size = 2.5 },
			{ Id = "SigFlare", Kind = "Emitter", Texture = "fx_glow", Beat = "Impact", At = "$Hit", Tint = "Hot", Count = 3, Size = 1.6, Transparency = 0.35 },
		},
	},
	-- a giant wishing star rises over the allies (Gemini: a gold glass body with a deep gold neon rim, not a solid neon
	-- blob) and showers falling stars on each of them while the heal's star spirals rise
	starlight_unicorn = {
		Name = "Wishing Star", Rarity = "Mythic", Element = "Celestial", Kind = "Heal",
		Twist = "a giant wishing star rises and showers allies",
		-- (Studio findings round, Gemini top 5 #4: the giant star rose straight through the player's avatar) its path keeps
		-- Clear studs (x size, + its own half-width) away from the caster and the local player's character, pushed Forward
		-- toward the allies' side
		Actor = { Key = "vfx_sig_wish_star", At = "Above", Motion = "WishRise", Beat = "Charge", Tint = "Mid", Material = "Glass", Transparency = 0.15, Rim = { Tint = "Edge", Scale = 1.1, Transparency = 0.2 }, Clear = 1.5, Forward = 1.5 },
		Layers = { { Id = "SigShower", Kind = "Emitter", Texture = "fx_stars", Beat = "Travel", At = "Allies", Count = 14, Size = 1, Fall = true } },
	},
	-- as the pet leaps, an electric storm-wolf charges out of it and through the target, two bolts crackling along its
	-- path (the Mythic slash arc is left out: both bolts under the 4-beam cap)
	stormfang = {
		Name = "Storm Pounce", Rarity = "Secret", Element = "Storm", Kind = "Pounce",
		Twist = "a lightning storm-wolf charges through the target",
		Actor = { Key = "vfx_sig_wolf", At = "Source", Motion = "ChargeThrough", Beat = "Travel", Color = rgb(80, 180, 255), Rim = { Color = rgb(40, 60, 200), Scale = 1.1, Transparency = 0.3 } },
		Skip = { DoubleArc = true, Flash = true }, -- (the slam's own flash replaces the ladder's: <= 3 lights)
		Tints = { SigBolts = rgb(90, 170, 255), SigSlamBolts = rgb(150, 210, 255), SigCloudRide = rgb(46, 60, 120) },
		-- (Studio findings round, Gemini top 5 #3: the Secret landing read weaker than Lava Slam / Glacier Breath) the slam:
		-- a wide shock ring races over the ground, two bolts strike down round the target, a lightning flash; the pet rides a
		-- storm cloud through the leap (its two bolts, the slam bolts: the 4-beam cap; the slam bolts replace the element's
		-- stray alive bolts: Alive = false)
		Alive = false,
		Layers = {
			{ Id = "SigBolts", Kind = "Beam", Texture = "fx_lightning", Beat = "Travel", At = "Path", Count = 2, KeepCount = 2 },
			{ Id = "SigShock", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "Ground", Color = rgb(130, 205, 255), Grow = 3.6, Transparency = 0.2 },
			{ Id = "SigSlamBolts", Kind = "Beam", Texture = "fx_lightning", Beat = "Impact", At = "Ground", Strike = true, Count = 2, KeepCount = 2, Width = 1.1 },
			{ Id = "SigSlamFlash", Kind = "Light", Beat = "Impact", At = "Ground", Color = rgb(150, 210, 255), Brightness = 4, Range = 14 },
			{ Id = "SigCloudRide", Kind = "Emitter", Texture = "fx_stormcloud", Beat = "Travel", At = "Self", Ride = true, Tint2 = "Mid", Count = 16, Size = 2.2, Transparency = 0.3 },
		},
		LowKeep = { "SigCloudRide" },
	},
	-- the battle dims (own pet); a black sun with a violet corona hangs over the target through the charge, the void orb
	-- flies, and at the impact the sun drops onto the target and bursts flat over the floor as violet wisps fling out
	-- (the slash crescent, nothing on a blast, makes room for the wisps)
	eclipse_dragon = {
		Name = "Eclipse Nova", Rarity = "Secret", Element = "Shadow", Kind = "Blast",
		Twist = "the battle dims for a moment; a black-sun ring bursts",
		DimWorld = 0.6,
		Actor = { Key = "vfx_sig_black_sun", At = "Above", Motion = "Eclipse", Beat = "Charge", Color = rgb(18, 8, 28), Scale = 0.6, Rim = { Color = rgb(186, 104, 255), Scale = 1.14, Transparency = 0.15 } },
		Skip = { Slash = true },
		-- (Studio findings round, Ruling 19: the dim stays; a clearly bigger nova at the impact) a dark-purple ring with a
		-- bright violet edge expands round the target at its height to 2x the orb's peak radius (OrbRadius)
		Layers = {
			{ Id = "SigCorona", Kind = "Emitter", Texture = "fx_wisps", Beat = "Impact", At = "$Hit", Motion = "Burst", Count = 10, Size = 1.4 },
			{ Id = "SigNova", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "$Hit", Level = true, OrbRadius = 2, Color = rgb(74, 22, 128), Transparency = 0.1 },
			{ Id = "SigNovaEdge", Kind = "Ring", Key = "vfx_ring", Beat = "Impact", At = "$Hit", Level = true, OrbRadius = 2.1, Color = rgb(232, 176, 255), Transparency = 0.3 },
		},
	},
	-- RULING (Task 11 fix rounds 1 + 2, Gemini consulted): NOT a single-target dive. Its special is a Storm that hits the
	-- enemies in the Storm zone (BattleSim: a Specials.Storm.Radius zone at the aimed target; BattleController's
	-- Atk.Special gathers them, the sim's event names only the aimed one), so a dive onto one target misread the
	-- mechanic. A black phoenix with a magenta rim waits over the near end of that enemy group, wings folded, then makes
	-- a LOW sweeping pass across it, end to end (AttackFx MOVE.Actor "Sweep"; one enemy in the zone: a short crossing
	-- over it), its black-flame wings trailing (Echo), the pass centred on the impact (a battle cuts the charge, so the
	-- beat lives at the impact) while the dark fire rains on every enemy in the zone (Core.Spread); violet fire spears,
	-- violet flames, an ash-violet cloud. Tests: client_p7vfx_engine 17e (the pass spans the group, the rain covers every
	-- target), client_p7vfx_storm (the battle path), client_dev_pets (the /fx stand-ins). Do not turn it back into a
	-- dive or a hover.
	obsidian_phoenix = {
		Name = "Shadowflame Storm", Rarity = "Secret", Element = "Flame", Kind = "Storm",
		Twist = "black-flame wings sweep the field; dark fire rains",
		Palette = { Core = rgb(255, 150, 240), Mid = rgb(150, 40, 170), Edge = rgb(40, 12, 44), Smoke = rgb(30, 16, 36) },
		Tints = { Rain = rgb(170, 70, 210), Burst = rgb(200, 90, 255), Alive = rgb(220, 110, 255), Cloud = rgb(92, 58, 108) }, -- the baked fire sheets darkened to shadow-fire
		Core = { Spread = true },
		Actor = {
			Key = "vfx_sig_phoenix_wing", At = "Above", Motion = "Sweep", Beat = "Charge", Color = rgb(34, 12, 42), Scale = 0.9,
			Rim = { Color = rgb(222, 86, 255), Scale = 1.1, Transparency = 0.2 },
			Echo = { Count = 2, Lag = 0.06, Color = rgb(96, 26, 120), Transparency = 0.45 },
		},
	},
	-- ACCEPTED DEVIATION (Task 11 fix round 1 ruling, Gemini consulted): the spec's "nine orbs circle EACH ally" is built
	-- as nine orbs in all, SHARED over the allies (3 / 2 / 2 / 2 on four). Keep it: 9 x 4 = 36 pieces breaks the 14-piece
	-- cap. Nine teal fox-fire orbs circle the kitsune through the charge (its nine tails), then fly out and circle the allies
	-- (all nine round one ally; 3 / 2 / 2 / 2 round four: the 14-piece cap); teal glass bubbles, teal wisps rising
	phantom_kitsune = {
		Name = "Foxfire Ward", Rarity = "Secret", Element = "Shadow", Kind = "Shield",
		Twist = "nine ghost fox-fire orbs circle each ally",
		Palette = { Core = rgb(220, 255, 250), Mid = rgb(124, 252, 228), Edge = rgb(60, 150, 170) },
		Tints = { Ward = rgb(124, 252, 228) },
		Actor = { Key = "vfx_sig_fox_orb", At = "Allies", Motion = "FoxFire", Beat = "Charge", Count = 9, Scale = 0.55, Tint = "Mid", Transparency = 0.1 },
	},
	-- ACCEPTED DEVIATION (Task 11 fix round 1 ruling, Gemini consulted): the spec's "erupts from a lava crack" is built
	-- with the crack opening under the TARGET (none under the cub). Keep it: a battle cuts the charge, so a crack under
	-- the cub would never be seen; the target's crack is the warning before the spikes.
	-- Lava spurts up round the cub as it heaves the orb, a molten boulder (yellow-hot heart), and slams it on the target:
	-- a lava crack glows open under the target just before (Gemini's second pass: the cub's own crack lived in the
	-- charge, which a battle cuts) and 5 magma spikes erupt from it in a ring; deeper lava reds
	magma_cub = {
		Name = "Lava Slam", Rarity = "Secret", Element = "Flame", Kind = "Blast",
		Twist = "erupts from a lava crack; magma spikes ring the target",
		Palette = { Core = rgb(255, 206, 96), Mid = rgb(255, 92, 24), Edge = rgb(150, 28, 8), Hot = rgb(255, 238, 150), Smoke = rgb(74, 44, 36) },
		Core = { Key = "vfx_chunk", Scale = 1.5, Transparency = 0, InnerTint = "Hot" },
		Skip = { Slash = true },
		Layers = {
			{ Id = "SigLavaCrack", Kind = "Decal", Texture = "fx_crack", Beat = "Travel", At = "Ground", Color = rgb(255, 120, 40), Size = 6, Seconds = 1.2 },
			{ Id = "SigEruption", Kind = "Emitter", Texture = "fx_flame", Beat = "Release", At = "Self", Motion = "Burst", Count = 8, Size = 1.3 },
		},
		-- (Studio findings round: the spikes + dome buried the target's flinch) the spike ring leaves the slot facing the
		-- caster open (Gap) and the Blast dome is fainter
		Actor = { Key = "vfx_sig_lava_spike", At = "Target", Motion = "RingRise", Beat = "Impact", Count = 5, Tint = "Mid", Gap = true },
		Tweak = { Dome = { Transparency = 0.84 } },
		LowKeep = { "SigLavaCrack" },
	},
	-- the wyrmling breathes a frost stream (an ice-blue beam, snow streaming along it), then the glacier rises out of the
	-- floor round the target in place of the cage, see-through (Gemini: >= 0.55, the frozen pet stays readable); it IS
	-- the ring of spikes, so the Frost spike ring is left out
	rime_wyrmling = {
		Name = "Glacier Breath", Rarity = "Secret", Element = "Frost", Kind = "Freeze",
		Twist = "breathes a glacier that rises around the target",
		-- (Studio findings round: the glacier buried the target's flinch) thinner: 0.55 -> 0.66
		Core = { Key = "vfx_sig_glacier", Transparency = 0.66 },
		Beats = { Travel = 0.35 },
		Drop = { IceSpikes = true },
		Layers = {
			{ Id = "SigBreath", Kind = "Beam", Texture = "fx_speedlines", Beat = "Travel", At = "Path", Tint = "Mid", Width = 1.6, Transparency = 0.2 },
			{ Id = "SigSnow", Kind = "Emitter", Texture = "fx_snow", Beat = "Travel", At = "Path", Along = true, Count = 10, Size = 0.9 },
		},
		LowKeep = { "SigSnow" },
	},
	-- three void serpent heads (a glitch-pink rim) rise from the floor behind the pet in a fan, the middle one tallest,
	-- and lunge forward roaring at the release with the Rally's void roar and rings
	hydralotl = {
		Name = "Void Fangs", Rarity = "Secret", Element = "Shadow", Kind = "Rally",
		Twist = "void serpent heads rise behind the pet and roar",
		Actor = { Key = "vfx_sig_serpent", At = "Behind", Motion = "RiseRoar", Beat = "Charge", Count = 3, Tint = "Mid", Transparency = 0.2, Rim = { Tint = "Hot", Scale = 1.08, Transparency = 0.25 } },
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
		if finite(area.Transparency) then -- (Task 9: Frost's see-through ice spikes)
			core.Transparency = area.Transparency
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
		-- (Task 10) the element's own take on the kind: Core fields merged over the kind's, its Slots / Layers / Drop /
		-- Tints / LowKeep on top (a signature still wins over both)
		local es = type(element.Specials) == "table" and element.Specials[kind] or nil
		if type(es) ~= "table" then
			es = {}
		end
		local core = merge(copy(def.Core), es.Core)
		local lowKeep = {}
		for _, list in ipairs({ es.LowKeep or {}, def.LowKeep or {} }) do
			for _, id in ipairs(list) do
				lowKeep[#lowKeep + 1] = id
			end
		end
		return {
			-- (review M1: no leading nil hole in the lists: slotsOf / ipairs read them in order)
			Core = core, Beats = copy(def.Beats), Skip = def.Skip or {}, Swap = def.Swap, Layers = { def.Layers or {}, es.Layers }, Detail = {},
			Slots = { def.Slots or {}, es.Slots }, Alive = true, Extras = def.Detail ~= false, Kind = kind, Text = def.Text, Special = true,
			BurstShape = def.BurstShape, LowKeep = lowKeep, Drop = es.Drop, Tints = es.Tints, CoreCount = def.CoreCount, ThickBand = def.ThickBand,
		}
	end
	local def = REACTIONS[attack]
	if not def then
		return nil
	end
	return {
		Core = def.Core, Beats = copy(def.Beats), Skip = def.Skip or {}, Layers = { def.Layers or {} }, Detail = {}, Slots = { def.Slots or {} }, Alive = false,
		Extras = false, Text = def.Text, BurstBoost = def.BurstBoost, LowKeep = def.LowKeep, Short = def.Short == true, Quiet = def.Quiet == true,
	}
end

local function slotsOf(def, element, sig)
	local refs = {
		Burst = element.Burst, Trail = element.Trail, Ground = element.Ground, Motif = element.Motif, Arc = element.Arc,
		RainKey = element.Rain.Key, RainTexture = element.Rain.Texture, RainKind = element.Rain.Kind or "Emitter",
		-- (Studio findings round) the Storm's rain sheet: thin falling streaks, unless the element's rain is solid / tumbling
		-- (Rain.Streak = false) or a Beam (Storm's lightning)
		RainStreak = (element.Rain.Streak == false or element.Rain.Kind == "Beam") and element.Rain.Texture or "fx_streak",
		-- (Task 10 kind slots: see Specials)
		ElementBurst = element.Burst, BurstMotion = element.BurstMotion or "Burst", Wrap = element.Trail, Ward = element.Motif, Gust = element.Trail,
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
	layer.Motion = ref(tpl.Motion, ctx.refs) -- (Task 10: "$BurstMotion", the Rally roar moves like the element's burst)
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
	if tpl.Tint2 ~= nil then -- (Studio findings round) a second tone: the puffs are born in it (the cloud's lit underside)
		layer.Color2 = ctx.palette[tpl.Tint2]
	end
	layer.Tint2 = nil
	if ctx.tweaks and type(ctx.tweaks[id]) == "table" then -- (a signature's Tweak on a layer it keeps)
		for k, v in pairs(ctx.tweaks[id]) do
			layer[k] = v
		end
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

local function aliveOf(element, palette, countScale, sigTints)
	local a = copy(element.Alive)
	a.Color = (sigTints and sigTints.Alive) or (element.Tints and element.Tints.Alive) or colourOf(element.Alive, a.Texture, palette, {})
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
	-- (Task 10) a kind's core grows with the band: more falling pieces (Storm), a wider beam (Beam)
	if type(def.CoreCount) == "table" and finite(def.CoreCount[band]) then
		core.Count = def.CoreCount[band]
	end
	if type(def.ThickBand) == "table" and finite(def.ThickBand[band]) then
		core.Thick = def.ThickBand[band]
	end
	-- (Task 11) a signature's core colour: Tint / InnerTint name the Palette entries its body / hot heart take instead of
	-- the band's (Ember's orange phoenix with a gold one inside, not the band's pale yellow round a blue-hot heart);
	-- NoTwin = no band 3+ quarter-turned twin (a phoenix crossed with itself reads as a spinning star)
	local sc = sig and type(sig.Core) == "table" and sig.Core or nil
	if sc then
		if sc.Tint and palette[sc.Tint] then
			core.Color = palette[sc.Tint]
		end
		if sc.InnerTint and core.InnerColor and palette[sc.InnerTint] then
			core.InnerColor = palette[sc.InnerTint]
		end
		if sc.NoTwin then
			core.Upgraded = false
		end
	end
	core.Tint, core.InnerTint, core.NoTwin = nil, nil, nil

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
	if req.Attack ~= "Hurt" and not def.Short then
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
		-- (the element's Tints, then its own take on this special kind (Task 10), then a signature's)
		tints = (element.Tints or def.Tints or (sig and sig.Tints)) and merge(merge(copy(element.Tints or {}), def.Tints), sig and sig.Tints) or nil,
		attack = req.Attack,
		kind = def.Kind, -- the resolved kind (a signature special may come with Kind nil: Task 8 review)
		drop = def.Drop, -- the element's Melee / Ranged Drop: shared attack layers it replaces (Water's shot: no Boom ball)
		tweaks = sig and type(sig.Tweak) == "table" and sig.Tweak or nil,
	}
	if sig and type(sig.Drop) == "table" then -- (Task 11) the kind / element layers a signature replaces (Rime: its glacier IS the spikes)
		ctx.drop = merge(copy(def.Drop or {}), sig.Drop)
	end
	local sigSkip = sig and type(sig.Skip) == "table" and sig.Skip or {} -- (Task 11) ladder layers a signature trades for its own
	local layers = {}
	local myOrder = rarityOrder[rarity]
	for _, step in ipairs(AttackFxCatalog.Ladder) do
		if rarityOrder[step.Tier] > myOrder then
			break
		end
		for _, ladderId in ipairs(step.Add) do
			if not def.Skip[ladderId] and not sigSkip[ladderId] then
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
							if finite(bs.Speed) then -- (a burst flung further: Earth's chunks scatter instead of piling into a boulder)
								layer.SpeedScale = bs.Speed
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

	-- (Task 9 Studio, Storm c2: the ranged Muzzle puff is the element's Burst sheet, but fully additive (fx_glow 1) it read
	-- as a white glare at the mouth: it takes the element's BurstLight like the Burst itself)
	if finite(element.BurstLight) then
		for _, layer in ipairs(layers) do
			if (layer.Id == "Muzzle" or layer.Id == "Roar") and layer.Texture == element.Burst then -- (Task 10: the Rally roar too)
				layer.LightEmission = element.BurstLight
			end
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
		CameraPunch = mine and band >= 3 and not def.Quiet,
		ScreenGlow = mine and band == 4 and not def.Quiet,
		Signature = sig and petId or nil,
		Palette = palette,
		Text = def.Text,
		Beats = out,
		ImpactAt = out.Charge + out.Release + out.Travel,
		Core = core,
		Layers = layers,
		-- (Task 11: a signature may leave the element's alive detail out (Alive = false: Sunbeam's ward has no bouncing rocks)
		-- or tint it, Tints.Alive: Obsidian's embers burn violet)
		Alive = (def.Alive and not (sig and sig.Alive == false)) and aliveOf(element, palette, ctx.detailScale, sig and sig.Tints) or {},
		LowKeep = {},
	}
	-- Low quality's second emitter after the Burst (AttackFx: MAX_EMITTERS.Low 2): the kind's pick, then the attack's,
	-- then the element's; the engine keeps the first one this effect has
	for _, list in ipairs({ (sig and sig.LowKeep) or {}, def.LowKeep or {}, element.LowKeep or {} }) do -- (a signature's own pick first)
		for _, id in ipairs(list) do
			recipe.LowKeep[#recipe.LowKeep + 1] = id
		end
	end
	if sig then
		local actor = copy(sig.Actor)
		if actor then
			actor.Color = actor.Color or palette[actor.Tint or "Mid"] or palette.Mid
			actor.Tint = nil
			if type(actor.Rim) == "table" then -- (Task 11) the rim's colour: its own Color, else a Palette entry
				actor.Rim.Color = actor.Rim.Color or palette[actor.Rim.Tint or "Hot"] or palette.Hot
				actor.Rim.Tint = nil
			end
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
