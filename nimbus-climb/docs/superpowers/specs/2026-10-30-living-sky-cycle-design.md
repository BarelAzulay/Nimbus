# Living sky cycle (design)

Date: 2026-10-30. Source: the 2026-10-29 sky brainstorm. Gemini gave 4 directions (Aetherial Dawn, Copper Sunset, Astral
Ocean, Overcharged Tempest), shown as in-game previews in `.superpowers/bugs-2026-10-24/pitch-2026-10-29/sky_options.jpg`.
The player picked **"Living sky cycle"** (Claude's pick; Gemini had picked a fixed Copper Sunset): Dawn -> a long Copper
Sunset -> a short starry night, about 20 minutes a loop, fights readable.

## Why

Today the sky is one fixed bright afternoon (LightingService, the Phase 4 look). A sky that slowly turns makes the
islands feel alive and gives returning players a reason to notice the world, without new art.

## Goals

1. One loop of about 20 minutes: **Dawn** (the bright pastel morning of preview A) -> **Copper Sunset** (preview B, the
   longest part) -> **Starry Night** (preview C, short) -> back to Dawn. Blends are slow (no visible switch).
2. Everybody on the server sees the same sky at the same moment.
3. Fights stay readable in every phase: pets, their rarity colours, telegraphs, HP bars and VFX read as well as today.
4. Indoor moods win: the dungeon preset, Low graphics and the attack-FX dim keep working on top of the cycle.

## Player decisions 2026-10-30 (after the first draft)

- The design is APPROVED to build.
- **Painted skies, not the stock sky:** "create and pitch me sky options for day, sunset/dawn, night, Events skies (boss
  raids: each boss spawn changes the sky - frost, cosmic, lava etc.)". So the cycle gets three painted skyboxes (Day,
  Dawn/Sunset, Night) and each raid boss gets an event sky shown while its raid runs (Storm Titan, Lava Golem, Frost
  Wyrm, Shadow Hydra). Options are rendered in Blender (blender/sky/sky_themes.py, branch sky-skies) and pitched on a
  page; the build waits for the picks and the upload.
- Claude's calls for this part: a skybox swap (Sky faces cannot tween) happens at the middle of a blend while the
  Atmosphere haze is at its thickest, so the change reads as the light turning, not a cut; a raid sky is server-wide
  (raids are server-wide events), blends in over ~3 s when the boss spawns and back to the current cycle sky when the raid
  ends; the readability floor and the battle lift apply to event skies too. The Day phase is the long bright part: the
  loop becomes Dawn -> Day -> Copper Sunset -> Night (lengths re-proposed with the picks).

## The player's sky picks 2026-10-30 (pitch page, all approved, no notes)

Rendered by `blender/sky/sky_themes.py` (theme ids below), final faces at 1024 px.

| Slot | Pick | Gemini / Claude had picked |
|---|---|---|
| Day | `day_vivid` Vivid Skylands | same / same |
| Dawn + Sunset | `dusk_amber` Amber Burn | Cotton Candy / Copper Glow (the player chose a third) |
| Night | `night_aurora` Aurora Slumber | same / same |
| Lengths | B: Dawn 2, Day 6, Sunset 9, Night 3 min (20 min) | B / B (replaces the 5 / 11 / 4 below) |
| Storm Titan raid | `storm_teal` Thunderhead Teal | Indigo / Teal |
| Lava Golem raid | `lava_obsidian` Obsidian Furnace | same / same |
| Frost Wyrm raid | `frost_glacial` Glacial Void | Blizzard / Glacial |
| Shadow Hydra raid | `shadow_eclipse` Eclipse Shadow | Rift / Eclipse |

Amber Burn is the strongest orange of the three and shows for 11 of 20 minutes (Dawn + Sunset). The colour rule
below matters more because of it: the orange stays in the skybox and the world light, ColorCorrection tint stays near
neutral, and the builder checks the HUD, rarity colours and a battle against the amber sky in Studio.

## Non-goals

- No weather (no rain, no storms; the Tempest direction was rejected).
- No new sounds this round (night ambience can be a later sound pitch).
- No player setting to lock the time (revisit if players ask).

## Anti-goals (a failure even if it works)

- A night so dark that a pet battle, an obby jump or a gate is hard to read, on a phone outdoors in daylight.
- A screen-wide orange tint that washes out the HUD, rarity colours or VFX at sunset.
- Lighting that pops or jitters (visible steps every few seconds).
- Any per-frame script cost, or network traffic per client for the clock.

## Decided by the player

- The living cycle, in the order Dawn -> long Copper Sunset -> short starry night, about 20 minutes, fights readable.

## Claude's calls (the player can override), checked with Gemini

- **Lengths:** Dawn 5 min, Copper Sunset 11 min, Night 4 min (20 min loop). Each phase blends into the next over the
  last ~75 s of the phase. The clock is piecewise, not a linear 24 h: ClockTime moves slowly through the sunset hours and
  fast through the night (Gemini).
- **One clock:** the server publishes one epoch at boot (an attribute, e.g. `Workspace.SkyEpoch`); each client computes
  the phase from `Workspace:GetServerTimeNow()` and re-applies the lighting every ~2 s with a ~2 s tween (smooth, no per-frame
  work, no remote traffic). A late joiner lands on the right moment at once.
- **Base layer:** the cycle is the BASE of the client's LightingStack, under every preset (Dungeon, GfxLow, AttackFxDim
  stay on top, unchanged). LightingStack gets a way to set or update the base (today a Push always goes on top).
- **Colour by world light, not screen tint (Gemini):** the sunset's copper comes from ColorShift_Top/Bottom, Ambient,
  Atmosphere Color/Decay, cloud colour and sun height; ColorCorrection TintColor moves only a little, so the HUD and
  pets keep their true colours.
- **Readability floor:** night is moonlit indigo, never black (Gemini: a rich indigo / violet ambient, not grey).
  OutdoorAmbient and Brightness never drop below a floor where voxel sides still read; the builder tunes it with
  screenshots of a battle at night. While I am in an outdoor pet battle (Battle Arena duel / raid, Champion Ring, PvP),
  my night lifts toward twilight over ~1.5 s and settles back after the fight (that player only).
- **Night details (no new art):** ~3000 stars and the moon; Terrain clouds go sparse and thin violet at night, warm peach
  and a little fuller at sunset (Gemini); lobby lamp posts / lanterns that already have lights glow a bit brighter at
  night; a few soft **fireflies** near meadow trees at night (a standard ParticleEmitter with the default sparkle, pale
  yellow-green, slow, capped low; off on Low graphics) (Gemini).
- **Not taken from Gemini:** animating GeographicLatitude for long sunset shadows (long shadows can hide pets and jump
  edges; the sun stays at a modest height).

## Constraints

- Plain Lua 5.1-compatible syntax, the project's module layout (LightingService server boot, LightingStack client).
- The server still writes Lighting only at boot; all changes after boot are client side (LightingStack rule).
- Phones: no extra cost beyond the 2 s tween; fireflies capped and off on Low graphics.
- Tests: smoke tests for the phase math (any server time -> the right phase and blend; a late joiner; loop wrap), the
  base-layer rule (Dungeon on top restores to the CURRENT cycle values when popped, not the boot values), the battle
  lift, the readability floor (minimum Brightness / OutdoorAmbient in every phase), Low graphics (no fireflies).

## Builder check (2026-10-30): settled

- **Moving base:** LightingStack's base is a one-time snapshot today (LightingStack.lua:15, 97-123). Add
  `SetBase(values, seconds)` that overwrites the base values and re-applies; presets on top keep winning, so a Dungeon
  popped at night returns to the current cycle values. Update the module header ("nothing else writes Lighting").
- **ClockTime wrap:** never tween across 24 -> 0 (it would run backwards through the day). Keep each phase's clock in
  one range and jump to Dawn instantly at the loop, or tween in unwrapped steps.
- **Sun height:** the sunset's ClockTime stays around 16-17 (a low sun would mean long shadows); the copper comes
  from colour, not from a sun on the horizon.
- **Integers:** StarCount (and any other whole-number property) is set at once, never tweened.
- **Low graphics:** GfxLow's fixed Clouds Density 0.4 (GraphicsQuality.lua:34) becomes a cap (the lower of 0.4 and the
  cycle value), so the clouds still thin at night on Low.
- **Dungeon atmosphere:** DungeonController caches `R.BaseDensity` once (DungeonController.lua:2093-2096); read
  `LightingStack.Value("Atmosphere", "Density", "Dungeon")` instead, so it adds to the current sky.
- **2 s refresh vs running fades:** apply() cancels running tweens (LightingStack.lua:148-153); a cycle refresh must
  not restart a Dungeon / AttackFxDim fade visibly (test it; skip a refresh while such a fade runs, if needed).
- **Battle lift:** the player attribute Config.Attr.InBattle starting with "B" (duel, raid, Champion Ring, PvP; a
  dungeon run is "D..." and stays under the dungeon preset). A ring run keeps it until the player is back at the portal,
  so the lift lasts the whole run.
- **Lamps:** the lobby lights come from LobbyBuilder `pointLight()` on parts named LampGlass, LanternLight, StallLight,
  DomeGlow (Brightness 0.8-1.2). A small client pass raises their Brightness at night, on phase changes only.
- **Join:** the first apply is instant (a late joiner never sees the boot afternoon fade away).
- **Dev:** `/sky dawn|sunset|night|speed <x>` in DevService (time offset / speed replicated through an attribute).

## Left to the builder

- The exact Lighting / Atmosphere / Clouds / Sky numbers per phase (start from preview A / B / C and today's P4 look),
  tuned with in-game screenshots of the plaza, a battle and an obby in each phase.
- How LightingStack exposes the base (a SetBase(preset) or a bottom-layer id) without breaking its current users.
- Which lamps brighten (existing PointLights / neon in the lobby) and the firefly spots.
- A dev command to jump the clock (e.g. `/sky dawn|sunset|night`) for testing and the Studio check.

## Studio checks after the build

- Watch one full loop at x10 speed (dev command): no pops, the order Dawn -> Sunset -> Night, sunset clearly longest.
- At night: a Battle Arena duel, a Champion Ring round and an obby jump all read clearly; the battle lift kicks in.
- Enter and leave a dungeon at sunset and at night: the dungeon look on top, the right sky when you come out.
- Two clients see the same phase.
