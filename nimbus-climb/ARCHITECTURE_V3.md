# Nimbus Climb — v3 contract (multi-concept game: tycoon + pet battles + obby)

Read `ARCHITECTURE.md`, then `ARCHITECTURE_V2.md`, then this file. **v3 supersedes both wherever they disagree.**
`src/shared/Config.lua` already has the v3 additions (Attr.Cash/Gems, remotes TutorialState/TutorialEvent/IndexClaim,
the Secret rarity, Config.Index, Config.Tutorial, Config.PetStats, Lobby.SpotRingRadius 300 + Lobby.PlotSize 72).
`Main.server.lua` already loads and inits `IndexService`, `NpcService`, `TutorialService`; `Main.client.lua` already
loads `SkyDragonController`, `IndexController`, `NpcController`, `TutorialController` (missing modules are skipped).

## What the player asked for after the first real playtest

1. Ground looks flat and plain: make it detailed (real materials, paths, patches, grass).
2. Token aura stays behind while the coin spins/bobs: it must move with the coin.
3. More colour in the world; a slightly brighter, warmer sun so the world does not look sad.
4. An animated flying **Sage Dragon** in the sky for atmosphere.
5. A **tutorial guide**: Nimbus the Cloudy Dragon in a small side panel guides a new player step by step with a
   guiding arrow until they know the basics.
6. **NPC pets** in the lobby, each telling the player something useful (how to get more coins, more pets, ...).
7. Pets and objects look too simple: clouds do not look like clouds; pet eyes look stuck on, not part of the face.
   Make everything cleaner and more detailed.
8. A **Pet Index** of all pets (reference: a "Pet Index" window with ??? silhouettes, group progress "0/8",
   a detail card, group rewards with a CLAIM button and "Unlocked: x/N").
9. Upgrade the UI look on the menu and the HUD (not too big, not too small); **text is too small**: fix readability.
10. Make it a **multi-concept game**: obby (side mode, not the main fun), **Tycoon** (main focus, with prestige), and
    **Pet Battles** (arena + PvP; feed pets, upgrade home, pets get stronger; each pet has a special attack with
    animations and effects). Decisions: tycoon = home + pet upgrades (rooms like kitchen/gym/garden); some pets are
    better for the economy (home grind) and some for combat, usefulness scales with rarity; battles = auto-battle with
    a special-attack button; currencies = **Cash** (tycoon), **Cloud Tokens** (obby + battles, roulettes/items),
    **Gems** (Robux; buy roulettes cheaply in gems, and a gems-only **Secret** roulette). All art is built in code.

## ART DIRECTION (decided by the player after the plan): DETAILED voxel style everywhere
**This section overrides sections 6, 7 and 8 wherever they mention smooth terrain, round parts or Ball shapes.**
The player chose a voxel ("pixel") look for the whole game, and then clarified with a reference image: **NOT chunky /
low-resolution blocks**, but the **detailed, fine-voxel MagicaVoxel style**: small voxels relative to the model
(pets ~24-32 voxels tall), natural readable proportions, smooth-looking curves (curled horns, rounded heads, tapered
legs), 2-3 shades per colour region for depth (lighter on top, darker underneath and in creases), fur patterns
(stripes, spots, masks, bellies), carved eye sockets with a dark iris, a white highlight voxel and darker brows/lids,
fine details (claws, beaks, nostrils, inner ears, feather/fur tufts). Cute and appealing (these are pets), but crafted.

* **`shared/Voxel.lua` (new, owned by the pets agent)** — the voxel kit everyone uses. It SCULPTS models from signed
  distance shapes instead of hand-typed voxels:
  ```lua
  Voxel.NewGrid(resolution)               -- e.g. 32 voxels per model height; grid keys are integer voxel coords
  Voxel.Shape(grid, shape)                -- shape = { Kind = "Ellipsoid"|"Capsule"|"Box"|"RoundBox"|"Cone"|"Torus"|"Curve",
                                          --   ...geometry in voxel units..., Key = paletteKey, Op = "Add"|"Carve"|"Paint",
                                          --   Rotation = CFrame (optional), Pattern = optional fn(x,y,z)->paletteKey }
  Voxel.Shade(grid, opts)                 -- assigns shade variants per voxel: <key>_Light on exposed tops, <key>_Dark
                                          --   on undersides/creases (ambient-occlusion-like), deterministic
  Voxel.Build(grid, opts) -> Model        -- opts: { VoxelSize = studs, Palette = {key -> Color3 | {Color, Material, Transparency}},
                                          --   Anchored = true, Name, PrimaryKey, MaxParts = n }; 3D greedy merge of same-colour
                                          --   voxels into box Parts; if over MaxParts, merges nearly-equal shades first (LOD)
  Voxel.Merge(grid) -> boxes              -- the greedy merge used by Build
  Voxel.Box(parent, cframe, size, color, material, props) -> Part   -- single block helper for world building
  ```
  Shade variants: Palette may define `Fur`, `Fur_Light`, `Fur_Dark`; when a variant is missing, derive it from the base
  colour (lighter/darker by ~10-15%). Parts: `Anchored`, `CanCollide/CanTouch/CanQuery` false unless asked,
  `CastShadow` false for small parts, SmoothPlastic unless the palette says otherwise.
* **Pets (PetBuilder, pets agent):** every species sculpted in this detailed voxel style (Cat, Dog, Fox, Bunny, Bear,
  Panda, Dragon, Owl, Slime, Unicorn, Phoenix, Frog, Penguin, Axolotl), palettes from `Look` with shading and
  species patterns, accessories and wings (per WingStyle) sculpted too; wings grouped for flapping. **Two levels of
  detail:** `PetBuilder.Build(def, {Detail = "High"|"Low", Scale})`: High (default) for ViewportFrames (Index, menu),
  podiums and NPCs, <= ~350 parts; Low for follower pets of other players / far away, <= ~120 parts.
  `PetController` uses High for the local player's pets and Low for others (the petcontroller code is in client/
  Controllers/PetController.lua: the pets agent may make this one-line LOD change there). Same public API otherwise
  (`Build/Animate/GetHeight`, `WingL/WingR`, Animate from the PrimaryPart, works in ViewportFrames). Build results are
  cached per (petId, detail) on the client and cloned, so opening the Index stays fast.
* **Tokens:** a detailed voxel coin (round silhouette at fine resolution, gold with lighter rim and a cloud emblem in
  relief) and a soft halo that moves with the coin; golden tokens bigger/brighter.
* **World (world agent):** NO smooth terrain. Cloud islands = sculpted voxel clouds (puffy, soft, several shades of
  white/very light blue, bigger voxels than pets, e.g. 2-3 studs, so part counts stay sane); ground = tiles with subtle
  colour variation and clear stone/sand/wood paths; detailed voxel trees (sculpted canopies with shading), lamps,
  benches, fences, banners, fountains (translucent blue water blocks), flower clusters; portals, roulette machines,
  shop and home plots in the same crafted style. Cheerful colours, not blinding. Whole lobby <= ~6000 parts after
  merging; build heavy decor once and reuse by `:Clone()`.
* **Sky Dragon (skydragon agent):** a detailed voxel eastern Sage Dragon sculpted with the kit (segments, head with
  horns/whiskers/mane), <= ~300 parts.
* **NPC pets** use PetBuilder High detail at Scale ~2.2 on crafted voxel pedestals.
* **UI** stays the chunky cloud UI (2D).

## Phases
* **Phase 1 (this build):** items 1–9 + the data foundations phases 2/3 need (pet roles/stats/specials, secret pets,
  bigger home plots in the lobby).
* **Phase 2:** tycoon homes on the plots, Cash, rooms, economy pets working at home, prestige, Gems + developer
  products + gem/secret roulettes.
* **Phase 3:** battle arena, PvE ladder + PvP, feeding/levels, specials with animations.
* **Phase 4 (asked for after Phase 3):** pets make the money (rainbow coins in the Pet Garden, food plants, Coin Magnet), the Food
  Machine, XP from every fight, EVOLVE at 20 / 50, the Training Place, the Champion Ring, pet cards, the home portal, safe zones,
  pets following behind (see "Phase 4" and "Phase 4 build contract" at the end).

## Global rules (additions)
* Everything from the earlier docs still applies (Lua 5.1 syntax, Theme fonts only, no asset ids, server-authoritative,
  rate-limited validated remotes, nothing system-announced in the screen centre).
* **Replication rule:** anything that moves every frame and is purely visual (sky dragon, NPC idle bobbing, token
  spin, pet followers) is animated on the **client**. The server never rewrites part CFrames at high frequency.
* **Readability rule:** at a 1920x1080 screen, body text >= 18 px, small captions >= 15 px, buttons >= 20 px, titles
  28–44 px; everything scales with screen height (factor clamp(viewportY / 1080, 0.8, 1.25)) and phones never go
  below 14 px. Every text has a stroke or sits on a solid panel so it reads on any background.
* **World text rule (added after the player's playtest: "letters too small, when you zoom a little you can barely
  read it"):** text in the 3D world must stay readable from normal camera distances. Name/info tags above things
  (BillboardGui) are sized in PIXELS (offset UDim2, never studs-scale for text), so they keep a constant on-screen size:
  names >= 22 px and info lines >= 18 px at 1080p, with a dark stroke, a compact solid backing plate sized to the text
  (no huge empty panels), sensible MaxDistance (~60-120 studs) and LightInfluence 0. Big signs on surfaces (SurfaceGui)
  use PixelsPerStud ~40-60 and letters at least ~1 stud tall for titles and ~0.6 stud for info lines, so they read
  from ~30 studs. Never a fixed small TextSize inside a studs-sized billboard. Every new sign follows this.
* **Terrain** (`workspace.Terrain`, smooth terrain) may be used for organic shapes (cloud islands, ground). Use
  `Terrain:SetMaterialColor` to tint materials. Terrain is static: build it once at boot.

## Ownership (phase 1)
| Agent | Files |
|---|---|
| world | `server/Services/LobbyBuilder.lua`, `server/Services/LightingService.lua` |
| skydragon | `client/Controllers/SkyDragonController.lua` (new) |
| pets | `shared/Voxel.lua` (new), `shared/PetBuilder.lua`, `client/Controllers/TokenFx.lua`, `server/Services/TokenService.lua` |
| catalog | `shared/PetCatalog.lua`, `server/Services/DataService.lua`, `server/Services/PetService.lua`, `server/Services/IndexService.lua` (new) |
| ui | `shared/Theme.lua`, `client/UI/CloudUI.lua`, `client/Controllers/HudController.lua`, `client/Controllers/NotifyController.lua`, `client/Controllers/DamageFx.lua` |
| menu | `client/Controllers/MenuController.lua`, `client/Controllers/HotbarController.lua`, `client/Controllers/IndexController.lua` (new), `client/State.lua` |
| tutorial | `shared/TutorialSteps.lua` (new), `server/Services/TutorialService.lua` (new), `client/Controllers/TutorialController.lua` (new) |
| npc | `shared/NpcDialog.lua` (new), `server/Services/NpcService.lua` (new), `client/Controllers/NpcController.lua` (new) |
| lead / tooling | `shared/Config.lua`, `Main.*.lua`, docs, `tools/*` |

---

## 1. Data (catalog agent: DataService)
Profile gains (migrate older profiles; defaults shown):
```lua
Discovered = { [petId] = true },   -- every pet ever owned/rolled (owned pets at migration time count as discovered)
IndexClaimed = { [groupId] = true },
Tutorial = { Step = 1, Done = false, Gifted = false },  -- Step = index into TutorialSteps.Steps
-- reserved for phase 2/3 (create with defaults now so later phases do not need another migration):
Cash = 0, Gems = 0, Home = { Level = 0, Rooms = {}, Prestige = 0 }, PetLevels = {},  -- PetLevels[petId] = {Level=1, Xp=0}
```
`ProfileSync` snapshot gains `Discovered`, `IndexClaimed`, `Tutorial` (plain tables). Do NOT show Cash/Gems in the
HUD until phase 2 sets the attributes.
New DataService helpers: `DataService.MarkDiscovered(player, petId) -> isNew`, `DataService.GetTutorial(player)`,
`DataService.SetTutorial(player, tutorialTable)` (MarkDirty + Sync).

## 2. Pet catalog v3 (catalog agent: PetCatalog)
Every PetDef gains (keep all existing fields; ids unchanged):
```lua
Role = "Economy" | "Combat",
Stats = { Income = n, Power = n, Health = n, Speed = n },   -- BASE values at rarity scale 1 (multiplied by Config.PetStats.RarityScale[rarity])
Special = { Id = "snow_burst", Name = "Snow Burst", Kind = "Blast"|"Heal"|"Shield"|"Storm"|"Pounce"|"Freeze"|"Beam", Power = n, Color = Color3 },
```
Economy pets: high Income, low Power/Health; Combat pets: the opposite. Roughly half of each per rarity. The Cloudy
Dragon is Combat (signature special "Cloud Breath", Kind "Beam").
Add **3 Secret pets** (Rarity "Secret", Glow = true, dark/iridescent palettes, only obtainable later from the
gems-only Secret roulette; they are NOT in any current roulette's possible list). Use existing species + accessories.
New pure helpers:
```lua
PetCatalog.IndexGroups() -> { {Id = rarityId, Rarity = rarityId, Pets = {PetDef...}, Reward = Config.Index.Rewards[rarityId]}, ... }  -- in rarity order, Secret last
PetCatalog.GetStats(petId, level) -> {Income, Power, Health, Speed}   -- base * RarityScale * (1 + 0.1 * (level - 1))
PetCatalog.TotalCount() -> n
```

## 3. Pet Index (catalog agent: IndexService + PetService; menu agent: IndexController)
* `PetService`: after a successful roll call `DataService.MarkDiscovered(player, petId)`; the RouletteResult `IsNew`
  keeps meaning "first time owned".
* `IndexService.Init(deps)` (deps: DataService, PetService); `IndexService.CanClaim(player, groupId) -> bool, reason`;
  `IndexService.Claim(player, groupId) -> ok, reason` (group complete = every pet in that group discovered; once
  only; grants the Config.Index reward via DataService.AddTokens; Notify the player; Sync). Remote `IndexClaim`
  (rate-limited, validated). `IndexService.Completed` signal Fire(player, groupId) (the tutorial may listen).
* `IndexController` (client): `IndexController.Init()`, `IndexController.Open(groupId|nil)`, `IndexController.Close()`.
  Opens on the menu "Index" button and on `OpenPanel("Index")`. Layout (like the reference, cloud-styled through
  CloudUI): title bar "Pet Index" + red X; left: vertical group list (one tile per rarity group: rarity-coloured
  gradient art tile, group name, "3/6" progress); centre: grid of pet tiles (ViewportFrame of the pet; undiscovered
  pets are black silhouettes using `ViewportFrame.ImageColor3 = Color3.new(0,0,0)` with a "???" caption; discovered
  show name); a group progress bar "x/N"; right: detail card (big viewport, name or "???", rarity, Role, stats and
  special name when discovered); rewards box ("Rewards:" with the token amount) and a CLAIM button (green when
  claimable, grey otherwise, "Claimed" when done) -> `IndexClaim`; footer "Unlocked: x/N" over all pets.
  Viewports are built a few per frame (as MenuController does), silhouettes never animate, one shared update loop.

## 4. Tutorial (tutorial agent)
`shared/TutorialSteps.lua` (data only):
```lua
TutorialSteps.Steps = {
  { Id = "welcome",   Text = "...", Target = nil,                       CompleteOn = "Next" },          -- player presses Next
  { Id = "home",      Text = "...", Target = { Kind = "Spot" },          CompleteOn = "NearSpot" },      -- within 14 studs of own SpotInfo.Center
  { Id = "shop",      Text = "...", Target = { Kind = "Shop" },          CompleteOn = "ShopOpened" },    -- client TutorialEvent
  { Id = "spin",      Text = "...", Target = { Kind = "Roulette", Id = "Cloud" }, CompleteOn = "Rolled", Gift = true },
  { Id = "equip",     Text = "...", Target = { Kind = "Menu", Id = "Pets" },      CompleteOn = "Equipped" },
  { Id = "index",     Text = "...", Target = { Kind = "Menu", Id = "Index" },     CompleteOn = "IndexOpened" },
  { Id = "portal",    Text = "...", Target = { Kind = "Portal", Id = "Easy" },    CompleteOn = "MatchStarted" },
  { Id = "finish",    Text = "...", Target = nil,                       CompleteOn = "MatchEnded" },
  { Id = "done",      Text = "...", Target = nil,                       CompleteOn = "Next" },
}
```
(Write friendly, short texts in Nimbus' voice; phases 2/3 will append steps for the home and the arena.)
* `TutorialService.Init(lobbyInfo, deps)`: tracks each player's step (from the profile; players that joined before
  Init too), advances on server-observed events (NearSpot poll ~2 Hz using SpotService.GetSpot; Rolled via
  PetService roll -> listen to the RouletteResult path: expose/consume a PetService signal `Rolled` (add it in
  PetService if missing — coordinate: the catalog agent adds `PetService.Rolled` Util.Signal Fire(player, petId));
  Equipped via `PetService.PerksChanged` or profile Equipped non-empty; MatchStarted/MatchEnded from
  `MatchService` (use player attribute InMatch true/false transitions); client events via remote `TutorialEvent`
  ("Next", "ShopOpened", "IndexOpened", "Skip") validated against the CURRENT step only. The "spin" step grants
  `Config.Tutorial.GiftTokens` once (Tutorial.Gifted). Finishing grants `Config.Tutorial.FinishReward`. "Skip" ends the
  tutorial (Done = true). Persists via DataService.SetTutorial. Fires `TutorialState` to the player:
  `{ Step = n, Total = #Steps, Id = step.Id, Text = step.Text, Target = step.Target, Done = bool }` on join, on change.
* `TutorialController.Init()`: a compact side panel (left side, below the top-left panel area, never centred):
  a small round portrait of Nimbus (PetBuilder Cloudy Dragon in a ViewportFrame, gently flapping), the step text
  (typewriter reveal, readable size), "Step 3/9", a Next button when CompleteOn = "Next", and a small Skip link
  (asks to confirm). **Guide arrow**: for world targets (Spot, Shop/Roulette machine, Portal) show a 3D bouncing
  arrow above the target plus a dotted Beam trail from the player's HumanoidRootPart toward it (client-side parts in
  workspace.ClientFx); for Menu targets highlight the menu button (pulsing ring around the `MenuButton_<Id>` button
  created by MenuController) and point a small on-screen arrow at it. Fire `TutorialEvent("ShopOpened")` when the
  Shop window opens and `"IndexOpened"` when the Index opens (MenuController/IndexController expose
  `MenuController.WindowOpened` Util.Signal Fire(windowId) — the menu agent adds it). Hidden while in a match except
  the "finish" step text. Celebrate completion with a small confetti burst at the side panel.
* World target positions come from the workspace: Spot = own spot (attribute SpotIndex -> workspace.NimbusLobby
  spot folder with attribute SpotIndex), Shop/Roulette = the roulette machine model (LobbyBuilder names it
  `Roulette_<Id>`), Portal = `Portal_<Id>` model. LobbyBuilder must keep those names (world agent).

## 5. NPC pets (npc agent)
* `shared/NpcDialog.lua`: 6 NPCs: `{ Id, Name, PetId (an existing catalog pet for the look), Scale = 2.2, Lines = {..} }`
  e.g. "Coach Corgi" (how to earn more tokens: harder portals pay more, golden tokens, win bonus),
  "Granny Owl" (pets: roulettes, rarity, odds, Index rewards), "Mayor Panda" (your home spot; the tycoon is coming),
  "Captain Penguin" (co-op tips: revive teammates at checkpoints, Phoenix Feather), "Sparky Fox" (controls: run, dash,
  items 1-4), "Nimbus" is NOT an NPC (it is the tutorial guide). 3-5 short lines each.
* `NpcService.Init(lobbyInfo, deps)`: builds each NPC with `PetBuilder.Build` at `lobbyInfo.NpcSpots[i]` (world agent
  supplies 6 CFrames on the plaza/paths, facing the walkway), a small pedestal/rug, a nameplate billboard (Theme
  fonts, readable) and a `ProximityPrompt` (ActionText "Talk", ObjectText = Name, HoldDuration 0, distance 10).
  Tag each NPC model `NC_Npc` with attribute `NpcId`. Server never animates them.
* `NpcController.Init()`: idles every `NC_Npc` model locally (gentle bob + slow turn toward the nearest player +
  PetBuilder.Animate wing flaps at low frequency) and shows the dialog when the local player triggers the prompt
  (`ProximityPromptService.PromptTriggered` on the client): a side dialog box (bottom-left above the HUD, NOT centred)
  with the NPC's name, a small portrait viewport, typewriter text, Next / Close; cycles through Lines.

## 6. World (world agent: LobbyBuilder + LightingService)
* **Clouds that look like clouds:** build the cloud islands from **smooth terrain** (many overlapping `FillBall`s of
  material Snow tinted soft cloud white/blue with `SetMaterialColor`, plus Glacier/Salt accents) so they are soft and
  organic; keep part-built decor on top. Add `workspace.Terrain` child `Clouds` (Cover ~0.5, Density ~0.6, soft colour)
  for real moving sky clouds.
* **Detailed ground:** plaza and walkways get real materials and structure: terrain Grass (with `Terrain.Decoration =
  true` for grass blades) for lawns, Cobblestone/Pavement/Brick paths with borders, wooden boardwalks (WoodPlanks),
  sand patches, flower beds, hedges, rocks, trees (several shapes), lamp posts, banners/bunting in the difficulty
  colours, fountains. Use part materials (Grass, Cobblestone, Brick, WoodPlanks, Slate, Sand, Fabric) — no more flat
  SmoothPlastic everywhere.
* **More colour:** flowers, banners, roofs, awnings, coloured stones; still calm, not neon-blinding.
* **Home plots (phase-2 ready):** the 16 spots become larger home plots on `Config.Lobby.SpotRingRadius` with a flat
  `Config.Lobby.PlotSize`-square grass yard (fence posts, a gate facing the ring road, a mailbox nameplate, the pet
  podium) — the yard centre stays EMPTY and flat for the phase-2 home. Keep `SpotInfo` fields and add
  `SpotInfo.PlotCFrame` (centre of the flat yard surface, facing the gate) and `SpotInfo.PlotSize`.
* Keep `LobbyInfo` (Portals, Spots, Shop) and add `LobbyInfo.NpcSpots = { CFrame, ... }` (6). Keep names
  `Portal_<Id>` and `Roulette_<Id>` for the portal and roulette models (tutorial targets). Everything stays walkable
  (ramps/bridges/paths; no traps), within performance budget (parts < ~3500; terrain is cheap).
* `LightingService`: slightly brighter and warmer — ClockTime ~14.5, Brightness ~2.0, a warmer ColorShift_Top,
  OutdoorAmbient a little higher, Bloom stays subtle; keep it readable (no blow-out). Keep Technology from the
  project file.

## 7. Sky Dragon (skydragon agent)
`SkyDragonController.Init()`: a large **Sage Dragon** (eastern/serpentine: sage-green scales, cream belly, gold horns
and whiskers, a flowing mane, fins along the spine, a cloud-tuft tail tip) built client-side in `workspace.ClientFx`
from ~24 body segments that follow the head along a smooth closed 3D path (e.g. a slow figure-eight / Lissajous loop
120–240 studs above and around the lobby, period ~70 s), undulating; head with glowing eyes, horns, whiskers that
trail; soft cloud-puff particles trailing. No collisions, no shadows, CanQuery/CanTouch false. One RenderStepped
loop, no per-frame allocation, frozen when far from the lobby (player in a match far away). Max ~180 parts.

## 8. Pets & tokens polish (pets agent)
* **Eyes:** eyes must look set INTO the face: the eye ball's centre sits inside the head so only a lens-shaped front
  shows; pupil and highlight sit exactly on the eye surface (no floating dots); eyelids/lash line optional; cheeks
  flush. Cleaner silhouettes for every species (smooth joins, ears that meet the head, consistent proportions),
  fluffier cloud wings for the Cloudy Dragon. Keep API, part budget <= ~70, Animate contract.
* **Token aura:** the aura/halo must move with the coin. TokenFx animates the whole token (coin + halo) — the halo
  bobs with the coin (it need not spin). TokenService builds it so the client can find it (e.g. a child named
  `Halo` of the token root, or tag it); keep `Config.Tokens.ClientAnimated = true`.

## 9. UI (ui agent + menu agent)
* `Theme`: readability rule above; add `Theme.ScaledSize(basePx)` (uses the screen-height factor) and raise every
  role's default size; text stroke on light backgrounds; keep all existing keys/functions.
* `CloudUI`: a more polished chunky style like the reference (thick dark outline, glossy top strip, bold title bar
  with big title text, red X button, consistent paddings), all sizes via the readability rule. API compatible.
* `HudController`: bigger, cleaner HUD; a **currency stack** at the bottom-left above the HP bar showing Cloud Tokens
  now (big number with K/M abbreviations and the cloud glyph) and ready to show Cash and Gems when those attributes
  exist (phase 2); everything else per the layout map, sized by the rule.
* `MenuController`: the left menu becomes the reference style: square-ish rounded icon tiles with the big glyph and a
  bold label under each (Inventory, Pets, Index, Shop, My Spot, Stats), named `MenuButton_<Id>`; expose
  `MenuController.WindowOpened` (Util.Signal, Fire(windowId) whenever a window opens) and handle
  `OpenPanel("Index")` by calling `IndexController.Open`. Windows sized by the rule (not too big, not too small).
* `HotbarController`, `NotifyController`, `DamageFx`: readable sizes per the rule.

---

## 10. The player's own creature: Stormfang + the Storm Altar (added after the player shared their art)
The player designed this creature themselves and wants it in the game. Reference art (READ these images before
building): `branding/stormfang-concept.webp` (original sheet: three poses of the creature on dark storm clouds plus a
crystal altar ring), `branding/stormfang-art.png` (same, transparent background) and `branding/stormfang-portrait.png`
(close-up of the head). The player uploaded the sheet to Roblox as asset 129423539279679 -> `Config.Art.StormfangImage`.

* **Pet (catalog agent + pets agent):** `Id = "stormfang"`, `Name = "Stormfang"`, `Rarity = "Secret"` (the 4th Secret pet,
  listed first among the Secrets: it is the player's signature creature), `Role = "Combat"`, Special "Storm Pounce"
  (kind `Pounce`, electric blue), stats/perks at the top of the Secret tier (must pass the Secret > best Mythic check).
  New species `"Stormfang"` (added to `PetCatalog.Species` and built by PetBuilder, NOT a recoloured Fox/Cat).
  Look, faithful to the art in the detailed voxel style: a lean, fierce but cute storm lynx; body of layered charcoal
  armour plates (3-4 greys: ~#2a2c33 base, #4b4d57, #70737e, light bevelled edges ~#a3a6ae) with ridge spikes sweeping
  back over the head, shoulders and spine; a white fluffy face mask and cheek ruff (white/very light grey shading);
  tall pointed lynx ears with NEON violet (~#7a3cff) and electric-blue (~#2fb4ff) inner stripes; fierce glowing blue
  eyes with a violet rim (Neon); a cyan diamond gem (~#3fc8ff, Neon core + Glass rim) on the forehead and smaller
  gems on the shoulder and chest plates; big armoured paws with glowing cyan claws (Neon); a fluffy armoured tail
  with neon stripes. Instead of feathered wings it rides a small dark storm cloud (navy #2e3a66 / #44507f / lighter
  #6b77a8 tops with a few white puffs): `WingStyle = "StormCloud"` (new style, added to `PetCatalog.WingStyles`;
  PetBuilder still returns the cloud halves as WingL/WingR so Animate can sway them gently). Animate: hover, the
  cloud drifts, neon parts pulse softly (client only). Budgets: High <= ~350 parts, Low <= ~120.
* **Storm Altar (world agent, lobby landmark), from the ring in the art:** a dark navy storm-cloud island (contrast
  landmark among the white clouds) at the lobby edge, facing the plaza, with a circular dais: a ring of charcoal stone
  blocks (radius ~12 studs) with bevelled tops, 6-8 tall cyan crystal shards (Neon core + Glass) around it (the front
  one biggest), a dark navy portal disc in the middle with a faint glow, and soft electric-blue PointLights.
  A big Stormfang showcase (PetBuilder High, Scale ~3, named `StormfangShowcase`) prowls on the altar; the NPC
  controller-style client animation (hover/pulse) applies to it. A poster/billboard `StormAltarSign` shows
  "STORM ALTAR" and the art (`Config.Art.StormfangImage`). ProximityPrompt "Storm Altar": Phase 1 -> side toast
  "The Storm Altar awakens soon: summon Secret pets with Gems!"; Phase 2 turns it into the gems-only Secret roulette.
  Model name `StormAltar`, part budget <= ~450 (excluding the showcase pet).
* **Pet Index (menu agent):** Stormfang's card is a ??? silhouette until discovered, like every pet; once discovered,
  its detail view also shows the 2D art (`Config.Art.StormfangImage`) as a banner.
* **Tutorial/NPCs:** one NPC tip mentions the Storm Altar and Secret pets.

## 11. Elements, battle teams and the Fusion Machine (asked for by the player during the build)
**Elements (build now, with the Stormfang round):** every pet gets one `Element` besides its rarity. Eight elements
(`Config.Elements`), fitting the sky/cloud world, from the player's list (lightning + wind -> Storm, dark/demonic ->
Shadow, light/angelic -> Celestial) plus Frost for the icy pets:
```
Wheel (each beats the next):  Water > Flame > Frost > Nature > Earth > Storm > (back to) Water
Pair (each beats the other):  Celestial <-> Shadow
Damage: strong x1.5, weak x0.75, otherwise x1.
```
* `PetCatalog`: `Element` on every pet (required, validated against `Config.Elements.Order`), assigned by species, look
  and theme (Phoenix/flame looks -> Flame, Penguin/icy -> Frost, Frog/Axolotl/sea colours -> Water, Bunny/Panda/leafy
  -> Nature, Bear/Dog/earthy -> Earth, Owl/Fox/electric -> Storm, Unicorn/angelic/halo -> Celestial, dark Secrets ->
  Shadow; Stormfang -> Storm). Every element has at least 3 pets and appears across several rarities.
  Helpers: `PetCatalog.GetElements(petId) -> {element...}`, `PetCatalog.ElementMultiplier(attackElement,
  defendElement) -> number` (from Config.Elements), `PetCatalog.ElementsOf(def)`.
* UI: an element badge (coloured pill with the element name, colour from `Config.Elements.Info`; no asset ids)
  on Index cards (only once discovered), the Index detail view (with "Strong vs X / Weak vs Y"), the Pets
  inventory panel and the roulette odds list. A small "Elements" help card in the Index shows the wheel.
* NPC tips: one NPC explains elements.

**Battle teams (Phase 3):** a battle team holds 3 pets; a 4th slot unlocks at Prestige 1 (or for Gems). Up to 3 saved
team presets (`Teams` in the profile). Team synergy shown live in the Team screen: 2 pets of the same element ->
+10% Power for them, 3 -> +20%, 4 -> +30%; 3+ different elements -> "Balanced" +10% Health for the team. Battles use
`ElementMultiplier` on every hit (dual-element attackers use their better element against the target).

**Fusion Machine (Phase 2, needs the per-copy pet data; unlocks at Prestige 1):** a crafted voxel machine built on each player's home plot from its buy pad (`FusionMachine`:
two input pods, a swirling cloud chamber, an output pod; fusion animation on the client). Two tabs:
* **UPGRADE:** 3 copies of the same pet and tier -> 1 of the next tier: Normal -> **Golden** (x1.5 stats/perk bonus,
  gold shimmer material) -> **Rainbow** (x2.5, animated rainbow shimmer). Costs Cloud Tokens by rarity.
* **MIX:** 2 different pets -> a brand-new hybrid: the body/species of the first, the colours, wings, accessory and
  element of the second added (Elements = both, deduplicated), rarity = the higher of the two, stats = average x1.2,
  a generated blended name (e.g. Penguin + Phoenix -> "Pengnix"), built by PetBuilder from a merged Look (the
  procedural pets make every hybrid look unique). Costs Tokens (or Gems for Secret/Mythic inputs). Hybrids live in a
  "Fusions" tab of the Index (not part of group rewards).
* Data: `Pets[petId] = count` stays for Normal copies; add `Tiers[petId] = {Golden = n, Rainbow = n}` and
  `Hybrids[uid] = {Body = petId, Style = petId, Elements = {...}, Name, Rarity, Tier}`; migration + delta save +
  ProfileSync like every other field; fusion is server-authoritative, validated and rate-limited, never consumes
  equipped pets without unequipping them first, and is atomic (inputs removed and output added in one step).

## Phase 2: Tycoon homes, the main mode (detailed by the player during Phase 1; build after the Stormfang round)
The player's words: "make sure the player's spot has the buttons and system working (you press E at the entrance to
obtain it) and you have there a spot purchasable for every tool or objective such as the kitchen (feeding the pet for
xp), machines, gym, fusion machine and everything so the tycoon system will work". So every home plot becomes a
classic Roblox tycoon: claim it at the gate, then build it up with buy pads.

**Claiming (replaces v2 auto-assignment in SpotService).** Each free plot's gate shows a ProximityPrompt "Claim Home"
(E, ObjectText "Free home"). Pressing it claims that plot for the session (one per player; refused during a match).
The SAVED progress is the player's home build (`Home` in the profile), not a plot number: it is rebuilt on whichever
plot they claim. A returning player whose last plot is free gets a side toast "Welcome back! Press E at your gate";
the tutorial arrow and the "My Spot" button lead to that gate (or the nearest free gate). Leaving releases the plot:
the build is removed and the gate shows "Claim Home" again. The nameplate/mailbox shows the owner, Home Level and
Prestige stars.

**Buy pads (the tycoon buttons).** Every purchasable thing has a build pad on the yard: a glowing voxel pad with a
floating sign (icon, name, price in Cash, "Lv 2 -> 3" for upgrades) and a ProximityPrompt "Buy" (E, HoldDuration
0.25). Only the owner sees and can use their pads (prompts disabled locally for everyone else; the server checks
ownership, price and prerequisites on every purchase). Buying deducts Cash, saves, and the structure assembles with a
quick voxel pop-in (client-side animation); new pads unlock in a tree so the yard fills up step by step, like a
real tycoon. Upgrades use the same pad, which stays in front of the built station.

**Stations (all voxel art in the detailed style, all on the plot):**
1. **Cloud Presses** (the money machines): up to 4 presses that puff glowing cloud blocks onto a conveyor into the
   **Collector**. Cash piles up in the Collector (shown on its sign); the owner steps on/presses E at the Collector to
   bank it. Each press upgrades L1-L10 (faster, bigger blocks). The first press pad is free/very cheap on claim.
2. **Pet Garden:** slots where the owner places Economy pets (from the Pets panel or a "Place pet" prompt); each
   placed pet makes Cash per second = Income x RarityScale x level factor x prestige multiplier, added to the
   Collector. Slots unlock with Garden levels.
3. **Kitchen:** cooks pet food with Cash (Snack, Meal, Feast; better recipes and faster cooking with Kitchen
   levels); food goes to the inventory. **Feeding** (from the Pets panel "Feed" button or the feeding bowl next to the
   kitchen): pick a pet and a food -> XP -> pet levels (`PetLevels`), which raise its stats
   (`PetCatalog.GetStats(petId, level)`): Income for Economy pets, Power/Health/Speed for Combat pets.
4. **Gym:** training slots for Combat pets; placed pets gain XP over time (more slots and faster with Gym levels).
5. **Fusion Machine:** section 11 (Upgrade: 3 copies -> Golden -> Rainbow; Mix: 2 pets -> hybrid), built on the plot
   from its pad; its window opens with E at the machine. **Unlocks only after Prestige 1** (the player's rule): before
   that its pad is a locked silhouette with "Unlocks at Prestige 1".
6. **Vault:** raises the Collector's cash cap and pays offline earnings (a % of the hourly income for up to N hours,
   shown in a "While you were away" toast on rejoin).
7. **House:** the home itself: **Cottage -> Villa -> Manor -> Sky Castle**. The player asked that the house upgrade
   only every 10 Home Levels so the castle is hard to get: Villa needs Home Level 10, Manor 20, Sky Castle 30 (the
   House pad shows "Reach Home Level N" until then). Each tier raises the max level of the other stations.
8. **Decor pads:** lamps, fences, flower beds, fountain, banners, a pet podium (the v2 showcase), cheap cosmetics that
   also add to Home Level.
9. **Arena Gate:** visible pad that unlocks pet battles (Phase 3); until then its sign says "Coming soon".

**Home Level and Prestige.** Every purchase or upgrade adds to Home Level. At Home Level 40 with the Sky Castle,
the Prestige pad appears: prestiging resets Cash and station levels (pets, food, decor choices kept) for +1 Prestige
star: a permanent x1.25 income multiplier per star, a Gems reward, a prestige badge on the nameplate, and at
Prestige 1 the Fusion Machine pad and the 4th battle-team slot (section 11).

**Economy.** Cash is the tycoon currency (HUD currency stack already shows it from the Cash attribute); Cloud Tokens
stay the obby/battle currency. Prices and incomes come from `Config.Tycoon` tables produced by an economy simulation
(targets: first purchase within 30 s of claiming, a steady new purchase every 1-3 minutes early on, first Prestige
after about 2-3 hours of active play, later prestiges faster thanks to the multiplier; no dead ends). Gems: developer
products (product ids in Config, placeholders until the owner creates them), idempotent ProcessReceipt; roulettes
also priced in gems (cheap) and the gems-only Secret roulette at the Storm Altar; respect PolicyService
paid-random-items restrictions and always show odds.

**Data.** `Home = {Level, Prestige, Stations = {[stationId] = level}, Garden = {slot -> petKey}, Gym = {slot -> petKey},
CollectorCash, LastSeen}`, `Food = {[foodId] = count}`, `PetLevels`, fusion data (section 11: `Tiers`, `Hybrids`),
all with migration + delta save + ProfileSync like every other field; server-authoritative, validated and
rate-limited; Cash income is computed on the server on a slow tick (1 s) and banked atomically.

**UI.** A Home window (menu tile "My Spot" becomes "Home": station list with levels, upgrade buttons, income per
second, prestige progress, "Go home"), the Feed panel, the Fusion window, readable pad signs (readability rule),
toasts for purchases, level-ups and offline earnings. **Tutorial:** after the Phase 1 steps: claim your home (E at a
gate), buy your first Cloud Press, collect your cash, build the Kitchen and feed a pet. **NPC tips** for the Kitchen
(Granny Owl), Gym (Coach Corgi), Fusion and Prestige.

## Phase 2 build contract (the engineers code strictly to these names)
> Phase 4 note: the station ids below are kept, but their meaning changed: Press1-4 are the food plants (Berry Bush, Carrot Patch, Cloud
> Melons, Starfruit Tree), the Collector is the Coin Magnet, the Kitchen the Food Machine and the Gym the Training Place; the Garden is
> the only money source (see the Phase 4 build contract).
**Ownership**
| Agent | Files |
|---|---|
| economy | `shared/TycoonCatalog.lua` (new), `tools/sim_tycoon.py` (new) |
| data | `server/Services/DataService.lua`, `shared/PetKeys.lua` (new), `server/Services/PetService.lua`, `client/Controllers/PetController.lua`, `client/State.lua` |
| homeworld | `server/Services/HomeBuilder.lua` (new, a module TycoonService requires), `client/Controllers/HomeFx.lua` (new) |
| tycoon | `server/Services/TycoonService.lua` (new), `server/Services/SpotService.lua` |
| care | `server/Services/PetCareService.lua` (new), `shared/PetCatalog.lua` (levels/stats only) |
| fusion | `server/Services/FusionService.lua` (new), `client/Controllers/FusionController.lua` (new), `shared/PetBuilder.lua` (tier finishes + hybrid looks only) |
| gems | `server/Services/GemService.lua` (new) + the Secret/gem roulette path in PetService once the data agent is done |
| ui | `client/Controllers/MenuController.lua`, `client/Controllers/IndexController.lua` (Fusions tab), `shared/TutorialSteps.lua`, `server/Services/TutorialService.lua`, `shared/NpcDialog.lua` |
Lead-owned: Config.lua, Main.server.lua, Main.client.lua, the docs.

**Pet keys (`shared/PetKeys.lua`).** Phase 2 gives pets per-copy variants, so a pet copy is identified by a key string:
`"<petId>"` (Normal), `"<petId>@Golden"`, `"<petId>@Rainbow"`, `"hyb:<uid>"` (a fused hybrid, may also carry `@Golden` /
`@Rainbow`). Profile: `Pets[petId] = count` stays for Normal copies; `Tiers[petId] = {Golden = n, Rainbow = n}`;
`Hybrids[uid] = {Body = petId, Style = petId, Elements = {...}, Name, Rarity, Tier}`; `Equipped` is a list of keys.
API: `Parse(key) -> {PetId, Tier, HybridId}`, `Make(petId, tier)`, `Count(profile, key)`, `Add(profile, key, n)`,
`Remove(profile, key, n) -> ok` (never below 0), `List(profile) -> {key...}`, `DefOf(key, profile) -> def` (catalog def,
or a merged def for hybrids whose Look combines both parents; `Look.Finish = "Golden"|"Rainbow"` for tiers),
`StatMultiplier(tier) -> 1 | 1.5 | 2.5`. Everything that shows or equips pets (PetService, PetController, menus,
Index, podium, NPC-free) works with keys; old profiles (plain petIds) are valid keys.

**Data (`DataService`).** Adds `Home = {Level, Prestige, Stations = {[stationId] = level}, Garden = {[slot] = key},
Gym = {[slot] = key}, CollectorCash, LastSeen}` (migrated from the reserved `Home.Rooms`), `Food = {[foodId] = count}`,
`PetLevels[key] = {Level, Xp}`, `Tiers`, `Hybrids`, `GemReceipts` (bounded set of processed purchase ids) and reserves
`Teams` for Phase 3. Cash/Gems/Food/CollectorCash save as deltas; Stations/Garden/Gym/Tiers/Hybrids/PetLevels per key;
a higher `Home.Prestige` wins the whole `Home` on merge (prestige resets stations). New API: `GetHome(player)` (copy),
`MutateHome(player, fn) -> ok` (fn edits a live table, no yields), `AddCash/SpendCash/GetCash`,
`AddGems/SpendGems/GetGems`, `AddFood/SpendFood/GetFood`, `GetPetLevel(player, key)`, `AddPetXp(player, key, xp)
-> levelsGained`. The player attributes `Config.Attr.Cash` / `Config.Attr.Gems` mirror the balances (the HUD shows them).

**`shared/TycoonCatalog.lua` (economy).** Data + pure functions, balanced by `tools/sim_tycoon.py` (a progression
simulation that proves the targets in the Phase 2 section). Stations (ids): `Press1..Press4` (Cloud Presses),
`Collector`, `Garden`, `Kitchen`, `Gym`, `Vault`, `House`, `FusionMachine`, `ArenaGate`, decor `DecorLamps`,
`DecorFence`, `DecorFlowers`, `DecorFountain`, `DecorBanners`, `DecorPodium`. Each: `{Id, Name, Kind, MaxLevel, Requires
= {Station = level, HomeLevel = n, House = tier, Prestige = n}, Price = {[level] = cash}, Effects = {[level] = {...}},
Slot = plot-local CFrame + Footprint}` (positions inside the `Config.Lobby.PlotSize` yard: house at the back, presses +
conveyor + collector on one side, garden opposite, kitchen/gym/vault/fusion/arena gate around, decor along the fence).
`HouseTiers` = Cottage (start), Villa (Home Level 10), Manor (20), Sky Castle (30), each raising other stations' caps.
`Prestige = {HomeLevel = 40, House = "SkyCastle", IncomeMultiplier = 1.25 per star, GemReward}`. `Foods` (Snack,
Meal, Feast: Price, Xp, CookSeconds, KitchenLevel). `Fusion` costs by rarity. Pet XP curve. API: `Get(id)`,
`PriceFor(id, level)`, `AvailablePads(home) -> {{StationId, NextLevel, Price, Locked = reason|nil}}`,
`HomeLevelOf(home)`, `IncomePerSecond(home, gardenDefs, prestige)`, `CollectorCap(home)`, `OfflineEarnings(home,
seconds, incomePerSecond)`, `XpToNext(level)`, `Validate()`.

**HomeBuilder (homeworld, server module) + HomeFx (client).** `HomeBuilder.Init(lobbyInfo)`, `PreparePlot(spotInfo)`
(gate "Claim Home" ProximityPrompt named `ClaimPrompt`, attribute `SpotIndex`), `SetOwner(spotInfo, player|nil)`,
`SetStation(spotInfo, stationId, level)` (builds or replaces the station's detailed-voxel model `Station_<Id>` with
attributes `StationId`, `Level`, `BuiltAt` under the plot's `Home` folder; level 0 removes it), `SetPads(spotInfo, pads)`
(pad models `Pad_<StationId>` with a readable sign: icon, name, "Lv a -> b", price or lock reason; ProximityPrompt `BuyPrompt`
ActionText "Buy", HoldDuration 0.25, attributes `StationId`, `OwnerUserId`), `SetCollector(spotInfo, cash, cap)` (attribute
updates only), `ClearPlot(spotInfo)`. Whole fully-built plot <= ~900 parts. HomeFx (client): voxel pop-in when a
`Station_*` appears, press puffs + conveyor blocks + collector glow (client-only visuals), disables `BuyPrompt`s whose
`OwnerUserId` is not the local player, and shows the collector amount.

**TycoonService (tycoon).** `Init(lobbyInfo, {DataService, PetService, SpotService})`; claiming via `ClaimPrompt`
(server Triggered; one plot per player; refused in a match); SpotService no longer auto-assigns: `GetSpot(player)`
returns the claimed plot, `Teleport` goes home or to the nearest free gate; on leave the plot is released and cleared.
Purchases via `BuyPrompt` (owner, `AvailablePads`, `SpendCash`, `MutateHome`, `HomeBuilder.SetStation/SetPads`, toast).
Income: a 1 s server tick adds presses + garden income into `Home.CollectorCash` (capped by the Vault); the Collector
(prompt or touch) banks it with `AddCash`; offline earnings on load ("While you were away" toast). Prestige pad.
Remote `HomeAction(action, arg)`: "Upgrade" stationId (from the Home window), "GardenSet" {slot, key|nil}, "Collect",
"Prestige", "GoHome". Signals `HomeChanged(player)`, `Claimed(player, spotInfo)`, `Prestiged(player, stars)`.
API `GetPlot`, `GetHome`, `Buy`, `Collect`, `Prestige`, `IncomePerSecond`.

**PetCareService (care).** Remote `PetCare(action, a, b)`: "Cook" (foodId, qty: Cash, a cooking queue on the Kitchen
with CookSeconds, finished food goes to `Food`), "Feed" (key, foodId: XP, level-ups toast), "GymSet" (slot, key|nil:
Combat pets only; passive XP per minute by Gym level). `PetCatalog.GetStats(petId, level, tier)` scales by rarity,
level and tier and is used everywhere stats show. Economy pets go to the Garden, Combat pets to the Gym.

**FusionService + FusionController (fusion).** Remote `Fusion(action, a, b)`: "Upgrade" (key: 3 copies of the same key
-> the next tier), "Mix" (keyA, keyB: two different pets -> a hybrid). Requires Prestige >= 1 and the FusionMachine
station; atomic; never consumes equipped/garden/gym copies without unequipping them first. PetBuilder: `Look.Finish`
Golden (gold-tinted palette + sparkle accents) and Rainbow (client-side hue shift), hybrid looks merged from both
parents; names blended ("Pengnix"). The window opens with E at the machine. The Index gets a "Fusions" tab (ui agent).

**GemService (gems).** `Config.Gems.Products` (placeholders, product id 0 = not created yet: the owner creates them on
the Creator Hub and pastes the ids), idempotent `MarketplaceService.ProcessReceipt` (GemReceipts), `PolicyService`
paid-random-items check (hide gem-priced roulettes where restricted), roulettes with `GemPrice`, and the gems-only
**Secret roulette** at the Storm Altar (its prompt opens the shop on that roulette; `AllowSecret = true`). Odds always shown.

**UI (ui).** Menu tile "My Spot" becomes "Home": the Home window (stations with levels and Upgrade buttons, income per
second, Collector cash, house tier, prestige progress, "Go home"); the Pets panel gets "Feed", "Place in Garden",
"Train in Gym" and shows tiers/hybrids/levels; the Shop gets a Gems tab; the Index gets the Fusions tab. Tutorial steps
appended (claim home, buy the first press, collect cash, build the kitchen and feed a pet); NPC tips for Kitchen, Gym,
Fusion, Prestige and Gems.

## Phase 3: Pet battles (detailed by the player during Phase 1; build after Phase 2)
The player's words: "create an Arena in the map for players to fight in it; at the arena there will be a special
events system (like in the chicken fight game) like a boss to defeat (everyone gets in this fight for the reward);
a button on the screen for controlling the pet (attack, retreat; works only in an arena or pvp); and a portal for
fighting NPC pets by levels so players can go there and fight for tokens."

**Battle Arena (lobby landmark, world).** A big detailed-voxel colosseum on its own cloud island linked to the plaza by
a bridge: a central battle floor (the boss stage), two or more PvP duel rings, spectator stands, an event board
(next event + countdown), a trophy leaderboard, and the Arena Gate pads of the homes point here. Battle zones are
tagged areas: the battle controls only work inside them (arena floor, duel rings, trial pockets).

**Teams.** Section 11: 3 pets (4th slot at Prestige 1), up to 3 saved presets, element synergy. The battle team
follows the owner into a battle zone and fights there; outside battle zones pets just follow as usual.

**Real-time battles, server-authoritative.** Pets move on the battle floor (10 Hz server sim, client interpolation):
move speed from Speed, melee or ranged by species, damage = Power x level factor x ElementMultiplier x small
variance, HP from Health x level, specials by `Special.Kind` (Blast = area, Heal, Shield, Storm = damage over time,
Pounce = dash strike, Freeze = stun, Beam = line). Client effects: lunges, hit flashes, damage numbers (never in the
screen centre), voxel particle bursts per special and element, knock-out poof; a downed pet returns after the fight.

**Battle controls (on screen, ONLY inside battle zones):** a compact battle HUD at the bottom/side (never centred):
each team pet's HP bar, element badge and special meter; buttons **ATTACK** (pets engage; tap/click an enemy to focus
it), **RETREAT** (pets break off and run back to the owner, take reduced damage and slowly regain HP while retreating;
short cooldown before attacking again) and one **SPECIAL** button per pet (lights up when its meter is full).
Keyboard F = Attack, R = Retreat, 1-4 = specials; gamepad mapped; touch buttons sized for phones.

**PvE: the Trial Portal (lobby).** A portal (named `Portal_Trials`, styled like the difficulty portals) opens a level
list of NPC pet teams: Level 1..30, each harder (higher levels, rarities, element mixes, a mini-boss every 5
levels). Beating level N unlocks N+1; rewards Cloud Tokens (big first-clear bonus, smaller repeat rewards) and pet
XP. Fights run in private battle pockets in the sky (instanced like obby matches) so many players fight at once.

**PvP.** In the arena: walk onto a duel ring and challenge another player (request -> accept), or join the quick
queue. Team vs team; rewards trophies (leaderboard) and tokens; nobody ever loses pets.

**Special events system (arena).** An event scheduler (every ~20 minutes, configurable; announced 2 minutes before by
a side toast to everyone and a countdown on the event board) runs events on the arena floor:
* **Boss Raid** (the main event): a giant detailed-voxel boss (rotating roster, each with an element and mechanics:
  e.g. Storm Titan, Lava Golem, Frost Wyrm, Shadow Hydra) appears; everyone in the arena can join with their team.
  Shared boss HP scales with the number of participants; telegraphed attacks (glowing circles/lines on the floor to
  RETREAT from), minion waves, an enrage timer. Rewards for everyone who took part, scaled by damage contribution
  tier (Tokens, pet XP, a chance of Gems and of an exclusive event pet).
* The scheduler supports more event types later (e.g. Double Rewards hour, King of the Ring).

**Progression.** Pet XP from battles + Kitchen food + Gym; levels raise stats (`PetCatalog.GetStats`). Rewards are
Tokens (shop, roulettes), trophies (rank/leaderboard), rare Gems.

## Phase 3 build contract (the engineers code strictly to these names)
> Phase 4 note: a pet in the Garden may fight now (only a training pet is busy, a read-time filter); evolution and training reach battles
> only through `BattleCatalog.UnitStats` extras; the Champion Ring adds the battle mode "Ring" (see the Phase 4 build contract).
Phases 1 and 2 are merged (Pet Index, tutorial, NPCs, Stormfang, elements, developer tools, tycoon homes, pet keys,
pet levels and stats via `PetCatalog.GetStats(petId, level, tier)`, Golden/Rainbow/hybrid pets, Gems). Phase 3 adds
the battles described above. **Architecture: the server simulates, the clients draw.** Battle pets, enemy pets and
bosses are NOT server-moved parts: the server runs a pure simulation at 10 Hz and sends compact snapshots; every
client builds and animates the models locally (PetBuilder / BossBuilder) and interpolates between snapshots
(Replication rule). Follower pets hide while their owner's team is in a battle.

**Ownership**
| Agent | Files |
|---|---|
| battlecore | `shared/BattleSim.lua` (new), `shared/BattleCatalog.lua` (new), `tools/sim_battle.lua` (new, balance harness) |
| data | `server/Services/DataService.lua` (Teams + Battle fields), `shared/PetKeys.lua` (only if needed) |
| battleservice | `server/Services/BattleService.lua` (new) |
| arenaworld | `server/Services/ArenaBuilder.lua` (new), `server/Services/LobbyBuilder.lua` (arena link + Trial Portal only), `shared/TycoonCatalog.lua` (ArenaGate ComingSoon flag only), `server/Services/HomeBuilder.lua` (Arena Gate prompt only) |
| events | `server/Services/EventService.lua` (new), `shared/BossBuilder.lua` (new), `shared/PetCatalog.lua` (event pets only) |
| battleclient | `client/Controllers/BattleController.lua` (new), `client/Controllers/PetController.lua` (hide followers in battle only) |
| ui | `client/Controllers/ArenaController.lua` (new), `client/Controllers/MenuController.lua` (Team screen + trophies), `shared/TutorialSteps.lua`, `server/Services/TutorialService.lua`, `shared/NpcDialog.lua` |
Lead-owned: Config.lua, Main.server.lua, Main.client.lua, the docs.

**Remotes (Config.Remotes, added by the lead):**
`BattleState` server->client `(kind, payload)`: "Start" {BattleId, Mode = "Trial"|"Duel"|"Raid", Zone (center CFrame +
size), Sides, Units (static info: id, side, owner, key or boss id, species/look ref, max hp, element)}, "Snapshot"
{BattleId, T, Units = {id -> {x, z, hp, state, target, meter}}} (10 Hz, only to participants and nearby spectators,
compact numbers), "Events" {list of {type = "Hit"|"Special"|"KO"|"Telegraph"|"Spawn"|"Enrage"|..., ...}}, "End"
{BattleId, Result, Rewards}. `BattleCommand` client->server `(action, a)`: "Attack" (targetUnitId|nil), "Retreat",
"Special" (teamSlot), "Forfeit". `BattleRequest` client->server `(action, a, b)`: "TeamSet" (preset 1-3, {keys}),
"TeamSelect" (preset), "Trial" (level), "Challenge" (userId), "ChallengeReply" (userId, accept), "Queue", "Unqueue",
"JoinRaid", "LeaveRaid". `ArenaState` server->client `(state)`: next event, countdown, current raid status,
leaderboard top 10. All client->server traffic: type-checked, rate-limited, refused outside the right zone.

**Data (DataService):** `Teams = {Presets = {[1..3] = {key, key, key, key?}}, Active = 1}` (slot 4 usable only at
Home.Prestige >= 1; keys must be owned, unique, and not in the Garden/Gym; fusion/reset removes stale keys);
`Battle = {Trophies, TrialBest, TrialCleared = {[level] = true}, Raids, RaidBestDamage, PvPWins, PvPLosses,
EventPets = {[petId] = true}}` with migration, delta-save rules (Trophies/PvP counters as deltas, TrialCleared and
EventPets grow-only), ProfileSync additions, and API `GetTeams/SetTeam/SelectTeam/ActiveTeamKeys`,
`GetBattle/MutateBattle(player, fn)`, `AddTrophies(player, n)` (n may be negative, floor 0).

**BattleCatalog + BattleSim (battlecore).** `BattleCatalog`: species combat profiles (melee/ranged, range, move speed,
attack interval, hit radius) for every species, the damage formula constants (Power x level/tier scaling x
`PetCatalog.ElementMultiplier` x variance; Retreat damage reduction and regen; special meter gain), special effects per
`Special.Kind` (Blast, Heal, Shield, Storm, Pounce, Freeze, Beam), team synergy (section 11), the 30 Trial levels
(NPC teams built from catalog pets with levels/tiers, a mini-boss every 5 levels, first-clear and repeat rewards), the
boss roster (Storm Titan, Lava Golem, Frost Wyrm, Shadow Hydra: element, HP per participant, attacks with telegraph
shapes and timings, minion waves, enrage timer), the event schedule (Boss Raid every ~20 min announced 2 min ahead,
plus Double Rewards hour) and trophy rules for PvP (win/loss amounts, floor 0). `BattleSim` is a PURE module (no
Instances, no services): `BattleSim.new(setup) -> battle`, `battle:Command(side/owner, action, arg)`,
`battle:Step(dt) -> events`, `battle:Snapshot()`, `battle:Result()`; deterministic for a seed; positions on a 2D floor
(x, z) inside the zone; units move, pick targets (focus target when commanded), attack in range, retreat to their
owner's anchor with reduced damage taken and slow regen, use specials when commanded and the meter is full, die and
stay down until the battle ends; bosses run their attack patterns with telegraphs that units can leave by retreating.
`tools/sim_battle.lua` (run with lupa like the smoke tests) balances it: trial curve vs. typical player power along the
tycoon progression (pet levels from TycoonCatalog XP), PvP fairness between equal teams, boss raids with 1/3/8
players finishing in ~2-4 minutes, no unkillable or one-shot builds, elements mattering but not deciding everything.

**BattleService (battleservice).** `Init({DataService, PetService, PetCareService, TycoonService})`; runs every battle
with BattleSim at 10 Hz on the server; modes: Trial (a private pocket arena per player built by ArenaBuilder, far out
in the sky; teleports in and back), Duel (two players on an arena duel ring; challenge -> accept, or the quick queue),
Raid (the boss floor; EventService starts and stops it; players join in the arena). Owns the battle zones (tagged
`NC_BattleZone`), the BattleCommand / BattleRequest remotes, team validation (active preset, slot 4 rule), rewards
(Tokens, trophies, pet XP via `PetCareService.GrantXp`, Gems chance) paid exactly once, disconnect/forfeit rules (a
leaver loses a duel; nobody loses pets), and the player attribute `InBattle` (battle id) for the client.
API: `StartTrial(player, level)`, `Challenge(a, b)`, `StartRaid(bossId)`/`EndRaid()`, `GetBattle(player)`,
`IsInBattle(player)`, signals `BattleEnded(battleId, result)`.

**ArenaBuilder (arenaworld).** `ArenaBuilder.Build(lobbyInfo) -> ArenaInfo` (called by Main after the lobby): the Battle
Arena island in the detailed voxel style (colosseum floor = the boss stage, 2+ duel rings with challenge pads,
spectator stands, the event board and trophy leaderboard as readable SurfaceGuis, banners), placed so it never
collides with homes, the Storm Altar or the sky dragon's path, and linked to the plaza (a bridge through a free ring
junction if one fits, otherwise an Arena Portal in the plaza + a return portal); the **Trial Portal** `Portal_Trials`
in the plaza (styled like the difficulty portals, prompt opens the Trial window); `BuildPocket(index) -> zone` for
private trial arenas; the home **Arena Gate** becomes a working teleport to the arena (remove TycoonCatalog's
ComingSoon flag). Part budget: arena <= ~2500, each pocket <= ~250 (cloned).

**EventService + BossBuilder (events).** The scheduler (every ~20 min a Boss Raid, announced 2 minutes before with a
side toast to everyone + the ArenaState countdown; a Double Rewards hour type), raid lifecycle through BattleService,
reward tiers by damage contribution, a chance of an exclusive **event pet** (2-3 new pets in PetCatalog with
`EventOnly = true`: never in roulettes, shown in the Index), and BossBuilder: big detailed-voxel bosses
(Storm Titan, Lava Golem, Frost Wyrm, Shadow Hydra) built on the client from BattleCatalog ids, with named parts for
attack animations and telegraph effects.

**BattleController (battleclient).** Builds and animates every battle unit from BattleState (PetBuilder for pets,
BossBuilder for bosses), interpolates snapshots, plays lunges, hit flashes, damage numbers (never in the screen
centre), special VFX per Kind and element, KO poof, boss telegraphs on the floor (glowing circles/lines that fill up
before the hit); the battle HUD (only inside battle zones): team pets' HP bars, element badges, special meters, and the
**ATTACK / RETREAT / SPECIAL** buttons (keys F / R / 1-4, gamepad, touch-sized), tap/click an enemy to focus it;
hides the follower pets during a battle (one line in PetController). Cheap per frame.

**ArenaController + Team screen (ui).** The Team screen in the menu (3 presets, slots 1-3 + slot 4 at Prestige 1,
pick pets with element badges and stats, live synergy bonuses, the element wheel), the Trial window (30 levels with
locks, recommended power vs. your team's power, rewards, first-clear badges), duel challenge/accept prompts and the
quick queue, the raid join prompt and event countdown, the trophy leaderboard panel; tutorial chapter 3 (go to the
Arena, set your team, win Trial 1, see a Boss Raid) and NPC tips for battles, elements in battle, teams and events.


**Interfaces between the Phase 3 modules (so every engineer can code without waiting for the others):**
- *Signals exist at module load* (`Util.Signal()`), so other services can connect before Init:
  `BattleService.BattleEnded:Fire(battleId, result)` with `result = {Mode, Winners = {userId...}, Losers = {userId...},
  Level (Trial), BossId (Raid), Damage = {[userId] = n} (Raid), Forfeit = bool}`; `DataService.TeamsChanged:Fire(player)`
  after SetTeam/SelectTeam. TutorialService and DevService receive `BattleService` (and DevService `EventService`) in
  their Init deps.
- *Duel/queue status*: `BattleState("Lobby", {Queue = {Queued, Waiting}, Invites = {{FromUserId, FromName, Trophies,
  Power, ExpiresIn}}, Sent = {ToUserId, ToName, ExpiresIn} | nil})`, sent by BattleService to a player whenever their
  duel/queue status changes. Refusals and info use the existing `Notify` toasts (side, never centred).
- *Snapshot frame*: `x, z` are studs relative to the zone centre from "Start" (`Zone = {CFrame, Size}`), floor at the
  zone CFrame's height. Static unit info also carries `slot` (the owner's team slot 1-4) so the HUD maps buttons to
  pets. `BattleSim` exposes its state codes and event types as constants (`BattleSim.States`, `BattleSim.Events`).
- *ArenaState* (EventService broadcasts it every ~1 s while a countdown or raid runs, else every ~5 s and on join):
  `{Next = {Kind = "BossRaid"|"DoubleRewards", BossId, StartsIn} | nil, Raid = BattleService.GetRaidStatus() ->
  {Active, BossId, Hp, MaxHp, Players, EndsIn} | nil, Double = {Active, EndsIn} | nil, Leaderboard = {{UserId, Name,
  Trophies} x10}}`. `EventService.StartNow(kind)` lets the developer tools start an event at once (`/raid`, DEV panel).
- *World prompts that open windows* carry the attribute `OpenPanel = "<panelId>"` (`"Trials"`, `"Arena"`); the client
  controller that owns the panel opens it from `ProximityPromptService.PromptTriggered` (like FusionController).
  Trial starts are accepted near `Portal_Trials`; duel challenges and the queue inside the arena; raid joins inside the
  arena while a raid is active.
- *BattleCatalog helpers the UI uses*: `UnitPower(petId, level, tier)`, `TeamPower(list of {PetId, Level, Tier})`,
  `Synergy(list of petIds) -> {{Id, Name, Text}}`, `Trials[level] = {Level, Name, RecommendedPower, MiniBoss,
  Rewards = {Tokens, FirstClear = {Tokens, Gems}}}`, `Bosses[id] = {Name, Element, ...}`, `Specials[Kind] = {Name, Text}`.
- *ArenaInfo* (from ArenaBuilder.Build): `{Model (workspace.BattleArena), Center (CFrame), Floor = {CFrame, Size},
  Rings = {{CFrame, Size, Pads}}, Spawn (CFrame), ReturnCFrame, TrialPortal (BasePart)}`; `ArenaBuilder.BuildPocket(index)
  -> {Model, CFrame, Size, Spawn}` and `ArenaBuilder.FreePocket(zone)`.
- *Ownership additions*: data also owns the DevService reset lines for Teams/Battle; events owns the DevService `raid`
  command and one DevController "Start Boss Raid" button (data and events run one after the other, never together).
- *As built (arenaworld)*: `Portal_Trials` is parented to `workspace.BattleArena` (= `ArenaInfo.TrialPortal`), NOT to
  NimbusLobby (the lobby is at its part budget), but it STANDS on the plaza at `LobbyInfo.TrialSite` next to the climb
  portals: the tutorial and any arrow/beam must target it through ArenaInfo. The arena is
  reached by a bridge from the plaza and by the home Arena Gate (a real station now: 150K Cash after the Gym). The
  board prompts carry `OpenPanel = "Arena"` plus `OpenPanelTab = "Events"` / `"Leaderboard"`; duel pad prompts carry
  `RingIndex` / `PadIndex`. Extra ArenaBuilder API: `ApplyArenaState(state)` (EventService draws the boards),
  `InArena(pos)`, `ZoneAt(pos)`, `GetInfo()`, `GetPocket(i)`, signal `Teleported`.

## Phase 4: pets make the money (asked for by the player after Phase 3; three designs, three judges, one synthesis)

Branch `v3-phase4`, cut from main after the Phase 3 release (Phases 1-3 shipped). Base design: **integration** (the player's late ring rule, the read-time
training lock, new data only in new top-level fields, the rollout fixture, the Food Machine, the ownership waves).
Grafted from **fun**: the four Cloud Presses become **food plants** and the Collector the **Coin Magnet** under the
SAME station ids (zero Home Level migration), Lucky coins, napping pets, the Welcome-back pile, one crowned champion
per round, LegacySlots, auto-remove / auto-return / refund for training, the EVOLVE pill on the floating pet card,
pets diving through the home portal. Grafted from **economy**: the Garden stays built through Prestige
(`ResetLevel = 1`), ring Cash paid as seconds of the climber's OWN garden income, the 3 x 4 garden grid, the
Portal_Trials second prompt as the zero-part fallback. Every must-fix of the three judges is resolved (section 11
lists where). Numbers were re-proved with throwaway prototypes in
`scratchpad/p4design/synth/` (section 3.12 and the appendix): `sim_synth.py` (economy, ALL TARGETS MET),
`ring_proto.lua` (the Champion Ring on the real BattleSim), `veteran_check.py` (300 Phase 3 homes migrated).

The player's words are requirements. Everything else below was decided so a kid can repeat each rule in one sentence.

### 1. What the player asked for -> what we build

| # | The player's words / decision | What we build (section) |
|---|---|---|
| 1 | "add pets health bar, special attack cooldown bar, xp bar (shows also their lvl)"; decision: **above each pet**, other players' pets show only their level | A small floating **pet card** over every own pet: "Lv 12" + XP bar everywhere; in a battle also a green health bar and a gold SPECIAL bar (the existing charge meter, drawn as the "cooldown" filling up). Other players' pets: level only. (3.9) |
| 2 | "not like an old typical boring tycoon (money machines). ... pets eating from the garden they're working on, and they poop the cash (rainbow coins) and the player picks them up (only the house owner can pick his own)" | The Pet Garden is the only money source. Pets in it eat from their bowls and pop out **rainbow coins** onto the garden walks; the owner walks over them to scoop (server-side owner check, no pickup remote). The four Cloud Presses become **food plants** (Berry Bush, Carrot Patch, Cloud Melons, Starfruit Tree) whose fruit flies into the bowls: better food = bigger coins; the Collector becomes the **Coin Magnet** (scoop from farther, bigger piles). No pet in the garden = no coins. (3.1-3.3) |
| 3 | "about the kitchen ... a basic food machine you press to buy food from, and an upgrade option which upgrades food's xp. You press on the machine, then it opens your pets list, there you click on which pet to feed, and each feed costs money and gives them xp" | The Kitchen slot becomes the **Food Machine**: press E -> your pet list -> **Feed $X (+Y XP)** per pet. One feed fills 25% of the pet's XP bar; the machine's upgrade (its pad, also offered inside the window) raises it to 30 / 35 / 42 / 50% for the same price. No stock, no waiting. (3.4) |
| 4 | "The other xp system will be from fights! Pets gain xp from each fight" | Every Trial, duel, raid and Champion Ring round pays XP to every pet that fought (a win pays full, a loss a third when the pets really fought). The ring is the best XP per minute that costs nothing. (3.5) |
| 5 | "first [evolution] at level 20 and the second one at 50"; decisions: an **EVOLVE button** with the animation; **Epic and up** evolve again at 50, Common / Uncommon / Rare stop at their first evolution | "Ready to evolve!" at 20: a glowing EVOLVE button (Pets card, Food Machine row, floating card pill); the evolution plays in the world in front of the player. Epic+ again at 50. Evolved pets: x1.25 power, health and coins (x1.5 after the second). Every rarity can reach level 100 (the player's later rule, section 11). (3.6) |
| 6 | "gym ... 'training place' for stats upgrade: ... choose which pet to train and what to train (attack speed / physique / ability / defense). You cannot have a training pet on you while it's training!" | The Gym slot becomes the **Training Place**: pick a pet and a skill; pay Cash; rank r takes r minutes. Starting takes the pet off you and out of the Garden by itself; it comes back by itself when done; Stop refunds. A training pet cannot be equipped, placed, fused or fielded (presets keep it). (3.7) |
| 7 | "at the start you can put up to 3 pets max (the higher level they are the more cash they produce; economic pets produce 60% more cash than combat pets; it also changes with their rarity and level). Each prestige ... another pet (prestige 1 can put 4 and so on)" | Garden places = 3 + Prestige stars (12 at most; 12 places are drawn). Any pet can work; coin = Food x PetPower, PetPower = rarity x level x Golden/Rainbow x **Economy 1.6 / Combat 1.0** x evolution. Veterans keep old extra places until their next Prestige (LegacySlots). (3.1, 3.2) |
| 8 | "home returning button ... opens a small cool portal only he and his pets can go through, which leads to his house" | **Go home** opens a swirling voxel portal 6 studs ahead for 10 s; only the owner's character is teleported (server check); pets dive in after and pop out of an arrival ring at home (client visuals). (3.10) |
| 9 | "outside the arena / battle area, all other places in the map are safe zones!" | Rule: pets fight only inside battle zones (arena floor, duel rings, Trial and Champion Ring pockets); everywhere else nothing hurts you and no teleport can pull you out of a fight (new InBattle guards). A side toast "Battle Arena" / "Safe zone" when crossing the arena bridge. (3.11) |
| 10 | "another battle system which teleports the player and his pets to a small battle ring fighting against random pet NPCs (best for xp farm). When you win a pet it shows another, stronger one (climb the levels ... make a record). Also each win gives the player cash" | The **Champion Ring**: one crowned champion pet per round, a stronger one every round, every 10th a giant boss champion; every win pays Cash (a few seconds of your own garden income, x3 on a new record) and XP; lose once and the run ends; your best round is your record ("Best in this server" on the portal). (3.8) |
| 11 | "make the pets follow the player from behind instead of being stuck to the player from his sides" | Trailing formation: 4-6.5 studs behind, never ahead while running (prototyped against the smoke windows). (3.9) |
| 12 | Later: "the portal is early available so even new players can go into fights there as long as they have at least 1 pet" ... "he do needs to first atleast a home and a pet" | **Portal_Ring** stands on the plaza next to the Trial Portal. Entry needs a claimed home ("Claim your home first") and at least one owned pet ("You need a pet"); fighters = the Team, else the equipped pets, else the best owned pets. Rounds 1-3 are one handicapped level-1 Common: **every one of the 12 single level-1 starter pets wins all three at 100% (24 seeds, real BattleSim)**. (3.8) |
| 13 | Decisions: Fable for the riskiest pieces, Opus elsewhere; ultracode | Ownership table and waves in section 10; every number proved by a sim; every rule tested. |
| 14 | Not specified -> decided: old presses / Collector / Vault progress and Home Level; house tiers and prestige without machines; offline earnings; coin values, drops, caps; machine prices; training costs / times / effects / caps; level caps; battle balance; the ring's name, place, rewards, record; what "safe zone" means in code; tutorial chapter 2 and NPC tips | Sections 3 and 4: ids kept so Home Level, tiers (10/20/30) and Prestige (40 + Sky Castle) are unchanged; offline coins go into the Welcome-back pile; all numbers in 3.1-3.8; caps 100 (the player's later rule); evolution / training only through `UnitStats` extras (trials unchanged); "Champion Ring" on the plaza; safe zone = outside `NC_BattleZone` parts and obby courses; chapter 2 rewritten in place, chapter 4 appended, NPC tips in section 9. |

### 2. The design in simple words (what the README will say)

* **Your pets make the money.** Build your free Pet Garden and put pets in it (3 places; +1 every Prestige). They eat
  from their bowls and pop out rainbow coins. Walk over the coins to scoop them: only YOU can scoop yours. Economy pets
  make 60% more than Combat pets; rarer, higher-level, Golden / Rainbow and evolved pets make more. Garden pets can
  still follow you and fight.
* **Your presses grew into food plants.** Berry Bush, Carrot Patch, Cloud Melons, Starfruit Tree: tastier food makes
  every coin bigger. The Collector is now a Coin Magnet: coins fly to you from farther away and piles hold more. Same
  pads, same levels, same Home Level: nobody loses a level.
* **Coins wait for you.** A pile holds a few minutes of coins; when it is full the pet takes a nap (Zzz) until you
  scoop. Coins left on the lawn are saved; the Vault adds offline coins; both wait in a big Welcome-back pile by your
  garden gate. Sometimes a sparkly Lucky coin pops out (worth 5): more often with a higher Garden level.
* **Food Machine** (the old Kitchen): press E, pick a pet, press Feed: it costs Cash and fills a quarter of the pet's
  XP bar. Upgrade the machine for bigger meals (up to half a bar) for the same price. Leftover Snacks / Meals / Feasts
  from the old Kitchen are fed first, for free.
* **Every fight gives XP** (a win the full amount, a loss a third if your pets fought). The Champion Ring is the best
  free XP in the game.
* **EVOLVE!** At level 20 a pet glows "Ready to evolve!": press EVOLVE and watch it change. Evolved pets are 25%
  stronger and richer. Epic and rarer pets evolve again at level 50 (50% in total). Every pet can reach level 100;
  each level takes more XP than the one before.
* **Training Place** (the old Gym): press E, pick a pet and a skill (Attack Speed, Physique, Ability, Defense). Rank 3
  takes 3 minutes. A training pet rests at home: it cannot follow you or fight until it is done, then it comes back by
  itself. Stop gives the Cash back.
* **Champion Ring:** the new portal on the plaza. You need a home and a pet. One champion at a time, each stronger than
  the last; every 10th is a giant boss. Every win pays Cash and XP, a new record pays triple Cash, beating a boss round
  for the first time pays 100 Tokens. Lose once and the run ends. Start from round 1 or from any boss round you beat.
* **Pet cards:** a small card above each of your pets shows its level and XP; in battles also health and SPECIAL.
* **Portal home:** Go home opens a small portal only you and your pets can use.
* **Safe zones:** outside the Battle Arena and the battle rings, nothing can hurt you or your pets.
* **Prestige:** Home Level 40 + Sky Castle. Stations and Cash reset (the Garden stays), +1 star: coins x1.25 forever,
  +1 garden place, Gems; prices go up by half after every Prestige (x1.5, x2.25, x3.4 ...). Pets, levels, evolutions,
  training, decor and garden choices are kept. Players from before Phase 4 keep their extra garden places and their
  old prices until their next Prestige.

## Phase 4 build contract (the engineers code strictly to these names)

Sections 1-2 above are the player-facing design; sections 3-11 are the contract. File:line anchors point at the Phase 3
release (main at 35800c0) and may drift by a few lines as the waves land: search for the named function.

**Player update (given after this contract was written; it overrides every "level 50 cap" below): "make the max level for all
pets at level 100 (evolutions stay the same) but obviously it becomes harder from a level to another (xp required)".**
* Every rarity levels up to **100**; the evolutions stay at 20 (every pet) and 50 (Epic and rarer). The XP curve is unchanged and
  keeps rising level after level: 20 XP for L1 -> 2, 10,125 for L49 -> 50, 31,190 for L99 -> 100 (195,880 XP in total to reach
  50, 1,203,340 to reach 100). Every level still adds +10% of the level-1 stats (L50 x5.9, L100 x10.9).
* Landed in wave 0: `PetCatalog.LevelCaps` 100 for every rarity, `PetCatalog.MaxLevel` 100, `TycoonCatalog.PetXp.MaxLevel` 100,
  `tools/sim_tycoon.py` `PET_XP[0]` 100, the README cap line and `p2care_stats`. Nothing may hard-code 50 as a level cap: read
  `PetCatalog.LevelCap` / `MaxPetLevel` (50 stays only where it means the second evolution).
* economy: re-prove EVERY pacing target of 3.12 / 8.3 with pets growing to 100 (the sim's `CAP` list = 100; `FeedPrice` keeps
  following `XpToNext`, so the road from 50 to 100 costs about 5x the road to 50); retune the catalog knobs if a target fails
  (the later prestige runs and the Gems per hour are the ones to watch, because pets keep their levels through Prestige).
* battlecore: Champion Ring champions keep their proven ladder: `BattleCatalog.Ring.ChampionMaxLevel = 50` (the solver's "lowest
  level 1..50" and "level-50 Rainbow boss with Boost" of 3.8 stay as written; the Boost covers the rest), so every ring target of 8.3
  still holds; `sim_battle.lua` adds a level-100 stage to its report (a trained and evolved L100 team: raids still 100-240 s with
  dodging players, no one-shots, mirror duels 35-65%, the practice gap (`DUEL_POWER_GAP`) catches L100 vs L50 duels).
* data: every clamp reads `MaxPetLevel` (100); `/petlevel <1..100>`; check what the frozen Phase 3 DataService does with a level
  above 50 during the rollout (it clamps with its own MaxLevel 50) and record the effect next to the 4.4 table (a Phase 3 server can
  only see the few minutes of a rollout).
* care / careui / ui / docs: every "max level" check and text reads the cap (100): "Lv 57 / 100", the Food Machine's cap refusal,
  level-up toasts ("Ready to evolve!" stays at 20 and 50), the README and the NPC tips.

### 3. Exact rules and numbers

#### 3.1 Stations (TycoonCatalog; the 18 ids, slots and tier caps are UNCHANGED; the tier-cap sums stay 29 / 51 / 78 / 91)

| Id | Display name | Kind | Max | Caps C/V/M/S | Requires | Prices (to reach level 1..max) | Effect per level |
|---|---|---|---|---|---|---|---|
| Garden | Pet Garden | Garden | 8 | 2/4/6/8 | (root) | **0**, 12000, 30000, 110000, 290000, 600000, 1200000, 2400000 | `Lucky` 0, .02, .04, .06, .08, .10, .12, .15 (chance a coin is x5); `ResetLevel = 1` |
| Press1 | Berry Bush | Plant | 10 | 6/8/9/10 | Garden 1 | 15, 55, 130, 360, 1200, 3500, 9000, 20000, 100000, 270000 | `Food` 7, 9, 12, 16, 21, 27, 35, 45, 59, 76 |
| Press2 | Carrot Patch | Plant | 10 | 6/8/9/10 | Press1 2 | 420, 1100, 2500, 6000, 15000, 22000, 38000, 120000, 260000, 680000 | `Food` 19, 24, 32, 42, 53, 69, 91, 118, 153, 199 |
| Press3 | Cloud Melons | Plant | 10 | 0/6/8/10 | Press2 3, House Villa | 18000, 25000, 36000, 88000, 130000, 180000, 290000, 410000, 1100000, 1800000 | `Food` 49, 63, 82, 107, 140, 180, 235, 302, 396, 518 |
| Press4 | Starfruit Tree | Plant | 10 | 0/0/8/10 | Press3 3, House Manor | 160000, 300000, 370000, 490000, 630000, 820000, 1100000, 1400000, 2200000, 3200000 | `Food` 127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339 |
| Collector | Coin Magnet | Magnet | 5 | 2/3/4/5 | Press1 1 | 90, 6000, 45000, 410000, 1400000 | `Radius` 9, 12, 16, 20, 26 studs (6 without); `PileSeconds` 300, 360, 420, 480, 600 (240 without) |
| Kitchen | Food Machine | FoodMachine | 5 | 1/2/4/5 | Press1 1 | 240, 35000, 320000, 680000, 1900000 | `FeedShare` .25, .30, .35, .42, .50 |
| Gym | Training Place | Training | 5 | 1/2/4/5 | Kitchen 1 | 3000, 110000, 420000, 920000, 2200000 | `Slots` 1..5 (pets training at once) |
| Vault | Vault | Vault | 5 | 1/2/4/5 | Press2 2 | 9000, 85000, 370000, 820000, 2000000 | `PileSeconds` +300, +600, +900, +1200, +1800; `OfflinePercent` .1 .15 .2 .25 .3; `OfflineHours` 1 2 3 4 4 (unchanged) |
| House | House | House | 4 | 4/4/4/4 | Collector 1 | 180, 24000, 200000, 880000 | Cottage / Villa (HL 10) / Manor (HL 20) / Sky Castle (HL 30) |
| FusionMachine | Fusion Machine | Fusion | 3 | 1/2/3/3 | Kitchen 1, Prestige 1 | 25000, 340000, 1400000 | TokenDiscount 0 / .1 / .2 (unchanged) |
| ArenaGate | Arena Gate | Arena | 1 | 1/1/1/1 | Gym 1 | 260000 | teleport to the arena (unchanged) |
| DecorLamps / Fence / Flowers | | Decor | 3 | 1/2/3/3 | Collector 1 / Press2 2 / Garden 1 | 1800, 27000, 360000 / 7000, 48000, 490000 / 2700, 36000, 410000 | KeepOnPrestige |
| DecorFountain / Banners / Podium | | Decor | 3 | 0/1/2/3 ; 1/2/3/3 ; 1/2/3/3 | Kitchen 1 + House Villa / Vault 1 / Garden 1 | 45000, 490000, 1500000 / 12000, 110000, 650000 / 9000, 95000, 580000 | KeepOnPrestige |

* `TycoonCatalog.Kinds = { "Plant", "Magnet", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }`.
  Nothing else in the yard moves: plants stand on the press slots (x -26.5, pads at x -19, the `PressLane` path stays),
  the Magnet in the Collector corner (-27.5, -26.5), the Food Machine on the Kitchen slot (25, 24), the Training Place
  on the Gym slot (-24, 29). `Layout.Conveyor` (TycoonCatalog.lua:247) is deleted; the rest of `Layout` stays.
* A fresh home shows exactly ONE pad: the free Pet Garden (today the free Press 1). The tree: Garden -> Berry Bush ->
  (Coin Magnet -> House -> Lanterns), (Food Machine -> Training Place -> Arena Gate; Fusion at Prestige 1; Fountain at
  the Villa), (Carrot Patch (Press1 2) -> Vault -> Banners; Fence; Cloud Melons (Villa) -> Starfruit Tree (Manor));
  Garden -> Flower Beds, Pet Podium. Validate's "no dead end" buildOut (:1481-1507) and the tier-cap-sum rule
  (:1509-1520) pass unchanged (the sim's pad model walks the same tree to the prestige).
* **Prestige** (trigger unchanged: Home Level 40 + Sky Castle): resets Cash, the coins on the lawn and every station
  that is not `KeepOnPrestige`, EXCEPT the Garden, which `StationsAfterPrestige` sets to `def.ResetLevel` (1) so coins
  never stop and pets keep their places. Gains: +1 star (coins x1.25 per star, unchanged), **+1 garden place**, Gems
  (100 - 10 per later star, floor 25, unchanged), Fusion Machine + 4th team slot at star 1 (unchanged). New
  `Prestige` fields: `GardenSlotsBase = 3`, `GardenSlotsPerStar = 1`, `GardenSlotsMax = 12`, `PriceStep = 0.5`.
* **Star price rule:** every station price is `Price[level] x StarPriceMultiplier(home)` with
  `StarPriceMultiplier = (1 + PriceStep) ^ stars` = x1.5, x2.25, x3.38, x5.06 ... (kid rule: "after every Prestige
  things cost half as much again"). `PriceFor(id, level)` stays the base price; pads and `CheckPurchase` use
  `PriceAt(id, level, home)`. Exception: a home with `Home.LegacyPrices = true` (a veteran who prestiged on Phase 3,
  section 4.3) pays base prices until its next Prestige. Food, training and roulettes never scale with stars.
* Prestige confirmation texts (UI): "Resets: Cash, coins on your lawn, stations (your Garden stays). Keeps: pets,
  levels, evolutions, training, decor, garden pets. Gains: coins x1.25 forever, +1 garden place, N Gems. Prices go up
  by half." and "Scoop your coins first!" when coins are waiting.

#### 3.2 Rainbow coins (the whole formula; `TycoonCatalog.Coins` holds the constants)

```
every open garden place with a pet eats one meal every MealSeconds = 8 s (server timer, random start phase)
coin value   = Food(home) x PetPower(pet) x 1.25 ^ stars              (a Lucky coin: x LuckyMult 5)
Food(home)   = GrassFood 12 (a built Garden) + Berry Bush + Carrot Patch + Cloud Melons + Starfruit Tree (Effects.Food)
PetPower     = RarityScale x (1 + 0.1 x (level - 1)) x TierMultiplier x RoleMult x EvolutionBoost
               RarityScale  = Config.PetStats.RarityScale (Common 1, Uncommon 1.5, Rare 2.3, Epic 3.5, Legendary 5.5, Mythic 8.5, Secret 13)
               TierMultiplier Normal 1 / Golden 1.5 / Rainbow 2.5 (unchanged);  RoleMult Economy 1.6 / Combat 1.0 (hybrids: their PetKeys role)
               EvolutionBoost = { [0] = 1, [1] = 1.25, [2] = 1.5 }  (PetCatalog.EvolutionBoost; the STORED stage, never the level)
IncomePerSecond(home, entries, stars) = Food / 8 x sum(PetPower of the open places) x LuckyEV(home) x 1.25 ^ stars
               LuckyEV = 1 + (LuckyMult - 1) x Lucky[Garden level]     (the expected value: "Your pets make $X a minute")
GardenSlots(home) = min(12, max(3 + stars, home.LegacySlots or 0))     (0 while the Garden is not built)
PileSeconds(home) = Magnet PileSeconds (240 without) + Vault PileSeconds;  a place's pile holds PileSeconds x that pet's coin rate
ScoopRadius(home) = Magnet Radius (6 studs without)
```

* Examples (a fresh garden with a Berry Bush L1: Food 19): Common Combat L1 coin $19 every 8 s (2.4/s); Common Economy
  $30 (3.8/s); Rare Economy $70; Legendary Economy $167. A Common Economy at level 20 evolved has PetPower 5.8; a
  Legendary Economy L50 Rainbow Evolved II 5.5 x 5.9 x 2.5 x 1.6 x 1.5 = 195. A fully built home has Food 2144 per meal.
* **Piles.** Each open place owns a pile at its deterministic `CoinPoint(slot)` (3.3). A new meal adds one coin to the
  pile; a pile that holds PileSeconds of coins is full: the pet naps ("Zzz", client) and eats nothing until scooped.
  The **Welcome-back pile** (`Garden.Slot.WelcomePile`) holds everything that was on the lawn when the home was last
  released (old Phase 3 Collector Cash included), plus the Vault's offline coins (`OfflineEarnings`, unchanged maths,
  absences under 120 s pay nothing) paid INTO `Home.CollectorCash` in the same `MutateHome` step that writes
  `LastSeen` (the existing double-pay guard, TycoonService.lua:1387-1429). Toast: "Welcome back! Your pets made $X
  while you were away: scoop it in your garden!".
* **Scooping.** A 0.25 s server loop over players who hold a plot: for every pile with Value > 0 whose point is within
  `ScoopRadius` horizontally and 10 studs vertically of the OWNER's HumanoidRootPart: one `MutateHome`
  (`CollectorCash -= take`) then `DataService.AddCash(take)` (attribute push only, no ProfileSync); if AddCash fails
  the bank is refunded (the pattern of today's `Collect`, :1053-1059). Whole Cash is paid, fractions stay in the bank.
  No button. `HomeAction "Collect"` stays as "scoop every pile in range" (old clients, tests). Invariant: the sum of the
  live piles + the Welcome-back pile == `Home.CollectorCash` (section 4.1). Other players' coins are drawn dimmed and
  never move (one-time hint "Only the owner can pick these up").
* **Garden pets stay available**: they can follow you and fight while they earn at home. Only a TRAINING pet is busy
  (`P3.placedCopies` counts only `Home.Gym`, which Phase 4 empties on load: section 4). A training pet cannot be placed
  in the Garden ("Rocky is training (2:10 left)"); starting training takes a pet out of the Garden by itself (3.7).
* **Offline:** unchanged Vault table (10-30% for up to 1-4 h) on `IncomePerSecond`, into the Welcome-back pile.
* Garden places above the open count (an old Garden L8 after a prestige that removed LegacySlots) keep their key but do
  not eat: the Pets panel says "Resting (garden full)" and the place shows the pet asleep on a closed bed. Nothing is
  ever deleted or returned to the list by code.

#### 3.3 The garden layout (12 places, station frame of `Garden.Slot` = at(24, -1, 90), footprint 22 x 20; -Z is the front)

* `Garden.Slot.Spots` (12): X in { -7.5, -2.5, 2.5, 7.5 } x Z in { -7 (front row, slots 1-4), 0 (middle, 5-8), +7 (back, 9-12) }.
  Cushions 2 x 2 in 3 x 3 beds, a bowl (client-drawn) in front of each toward the nearest walk.
* Two sand walks 3 studs wide at Z = -3.5 and Z = +3.5, joined at both ends; the entrance is the 3-stud gap between
  the front-row cushions at X = 0 (the pad at plot (10, -1) faces it). `Garden.Slot.Walkable` covers the walks.
* `TycoonCatalog.CoinPoint(slot)` (station frame): front row (x, 0, -2.6), middle row (x, 0, -4.4) (both on the front
  walk, two lines), back row (x, 0, +3.5). `Garden.Slot.WelcomePile` = plot-local (13.5, 0, 2.5): beside the entrance,
  off the pad. Validate: every coin point inside the yard, >= 1.5 studs apart, on no pad, inside the footprint or the
  entrance strip.
* Places beyond the open count show a seedling bed with a small sign "Prestige to open". Open empty places carry a
  `GardenSpotPrompt` ("Put a pet here", E; attributes `Slot`, `OwnerUserId`) at the cushion's far edge with
  MaxActivationDistance 3 and RequiresLineOfSight false, so it never pops up for a kid walking the walks (>= 3.5 studs
  away). It opens `OpenPanel("Pets", { Action = "Garden", Slot = n })`.
* Open places come from `HomeBuilder.SetGarden(spotInfo, valid, open)` (the hook TycoonService already calls at
  :666), NOT from the Garden level; the template cache key (:2549-2553) becomes `Garden:<level>:<open>`.
* HomeFx: `K.MAX_GARDEN_SLOTS = 12`; pets on cushions dip into the bowl twice per meal, wiggle, a coin pops out onto
  the pile (the heap model grows with the `CoinPiles` stage); a full pile = the pet lies down with a voxel "Zzz"; fruit
  of the best built plant flies into a random bowl every ~3 s per plant (pooled parts); the Coin Magnet totem spins and
  shows its radius as a faint ring while the owner stands inside it.

#### 3.4 The Food Machine (ids `Kitchen`; `TycoonCatalog.FeedShare`, `FeedXp`, `FeedPrice`)

```
FeedXp(level, machineLevel) = max(1, round(XpToNext(level) x FeedShare[machineLevel]))       FeedShare .25 .30 .35 .42 .50
FeedPrice(def, level)       = XpToNext(level) x RarityScale(def) x FeedBase                  FeedBase = 2.0  (the same price at every machine level)
"Level up"                  = ceil(missing XP / FeedXp) feeds in ONE request, at most 10, charged as one sum
```

* Price per XP = 2 x rarity / FeedShare: a Common pays $8 per XP at machine Lv1 and $4 at Lv5 (Phase 3's Feast was $7.5
  per XP); rarer pets eat fancier food (x1.5 ... x13) and their coins grow the same way, so the payback per level is
  the same for every rarity. Examples (Common, Lv1 machine): L1 feed $40 for 5 XP; L10 $1,590 for 199 XP; L19 $4,450
  for 556 XP. Road L1 -> 20: $139K (Lv1 machine) / $69.5K (Lv5); L1 -> 50: $1.57M / $784K; Legendary x5.5.
* Refusals before any Cash moves: no Food Machine ("Build the Food Machine at home first"), level 100 ("Rocky is at max
  level"), not owned, provisional profile ("Your save is still loading, try again in a moment"), a key in a running
  battle (`BattleService.KeysInBattle`). Cash is spent and the XP written in one non-yielding step; the Cash comes back
  when the XP write gives 0 (the `feed()` pattern, PetCareService.lua:1130-1138).
* **Leftover food** (`Profile.Food` Snack / Meal / Feast): fed first and free; the row's button reads "Feed (free Feast,
  3 left)" and uses the biggest leftover that does not overshoot the cap (the `bowlFood` rule :1156-1169; XP 25 / 150 /
  800). `TycoonCatalog.Foods` stays as data (Price / CookSeconds unused); Validate keeps the three ids.
* The window (CareController, 3.9 / section 6): garden pets first, then followers, then the rest; each row: viewport,
  name, "Lv 12", XP bar, "Feed $340 (+90 XP)", "Level up $1.2K", and the EVOLVE button when ready; footer "Food Machine
  Lv 2: each feed fills 30% of the bar. Upgrade to Lv 3 (35%): $320K" (the same purchase as the pad: `HomeAction
  "Upgrade"`).
* The old cooking queue (`Cook`, `tickKitchen`, refunds, KitchenQueue / KitchenReadyAt / KitchenDishSeconds attributes,
  CookPrompts, FeedBowl) is removed; the deploy is safe because Phase 3 servers refund every queued dish at BindToClose
  (PetCareService.lua:1867) and the queue was never saved. `Cook` / `GymSet` requests answer one toast ("The Kitchen is
  now the Food Machine" / "The Gym is now the Training Place").

#### 3.5 XP, levels and caps

* The curve stays: `XpToNext(L) = round(20 x L^1.6 / 5) x 5`, **MaxLevel 100** (the player's later rule; L20 = 17,375 XP total,
  L50 = 195,880, L100 = 1,203,340; one level costs 20 XP at L1, 10,125 at L49, 31,190 at L99).
* **Level cap 100 for every rarity** (PetCatalog.LevelCaps :946 -> 100 each, landed in wave 0; `FALLBACK_LEVEL_CAPS` PetCareService.lua:96
  too). Caps only rise, so no saved pet is above its cap; pets parked at 35/40/45 simply grow again.
* XP sources (ALL through `PetCareService.GrantXp`, cap-aware, level-up toasts; never `DataService.AddPetXp` directly):

| Source | XP per pet | Rule |
|---|---|---|
| Food Machine | FeedXp (25-50% of the bar) | Cash per feed (3.4) |
| Leftover food | 25 / 150 / 800 | free until the stock is gone |
| Trial win | 20 + 6 x level (26..200), unchanged | first-clear Tokens / Gems unchanged |
| Trial loss | **a third** of the win XP (`TrialRewardRules.LossShare = 1/3`) | only a real loss: the fight lasted >= 20 s OR the team dealt >= 20% of the enemy team's HP, and it was not a forfeit, a leave or a disconnect |
| Duel / Raid | 60 / 25 and tier XP 50..400 (failed 20), unchanged | |
| Champion Ring, round r won | **20 + 6 x r** | the round that ends the run pays a third under the trial-loss gate |

* Level-up toasts gain "Ready to evolve!" at 20 and 50 (`levelUpText` :689). The Gym's passive XP is gone.
* Pacing (sim_synth.py, the kid spends a quarter of the coins on food): the first garden pet reaches level 20 and the
  first EVOLVE happens after a median **1:18** of play (p10 1:12, p90 1:35); a second evolution (Epic+, level 50) is a
  long-term goal (7 of 120 players within three prestige runs). Ring XP per pet (ring_proto.lua run lengths): a Day-1
  team wins ~16 rounds in 4 min = 1,136 XP per pet (17K XP/h), a Prestige-1 team 36 rounds in 6 min = 4,716 (46K/h), a
  maxed team 51 rounds in 7 min = 8,976 (77K/h): the ring is the best XP source that costs nothing; the Food Machine
  turns Cash into XP as fast as you can afford it (a mid-game income of 300/s spending 25% buys ~34K XP/h for a Common,
  ~6K/h for a Legendary).

#### 3.6 Evolution (the EVOLVE button)

* Stage per pet KEY (all copies share it, like levels): 0, 1 (level >= 20, every pet), 2 (level >= 50, stage 1, and
  `PetCatalog.MaxEvolution(def) >= 2`: Epic / Legendary / Mythic / Secret, a DATA mirror of PetBuilder.MaxEvolution
  :6787-6793 so the server never requires PetBuilder). Data: `PetCatalog.EvolutionLevels = { 20, 50 }`,
  `PetCatalog.EvolutionBoost = { 1.25, 1.5 }`, `PetCatalog.EvolutionStage(def, level, stored) -> stored`,
  `PetCatalog.CanEvolve(def, level, stage) -> nextStage | nil`.
* The boost counts only after EVOLVE was pressed (the stored stage, `PetGrowth[key].Evo`), never from the level alone:
  veterans' pets already at 20+ are "Ready to evolve!" on their first Phase 4 login and each gets its own moment.
* Effect: x1.25 (stage 1) / x1.5 (stage 2) on battle Power and Health (and so the special) and on coins. Applied in
  `BattleCatalog.UnitStats(subject, level, tier, extras)` and `TycoonCatalog.PetPower`, NEVER inside
  `PetCatalog.GetStats` (the Index, the Trial solver and `smoke_content` pin the pure level formula). NPC pets (Trials,
  champions) never evolve, so Trials 1-30, RecommendedPower and "trial 30 power 2000-3200" stay exactly as they are.
* `PetCare("Evolve", key)`: owned, loaded and not provisional, level >= the next threshold, stage < MaxEvolution, not in
  a running battle ("Finish your battle first"). A training pet MAY evolve (the animation plays on clones). Writes the
  stage (grow-only), fires `PetCareService.Evolved(player, key, stage)`, toasts "Pebble Pup evolved! +25% to
  everything", refreshes `EquippedInfo`, and sends `OpenPanel("Evolve", { Key, Stage })` to that client only.
* The animation (CareController): the menu slides away, the follower of that key (if any) is parked, `EvolutionFx.Play`
  runs on two fresh `PetBuilder.Build` clones 5-6 studs in front of the player (EvolutionFx needs unwelded rest-pose
  models, EvolutionFx.lua:127-160; a ViewportFrame would lose its Highlight, PointLight and particles :202/:235/:250),
  confetti, a chime; then PetController rebuilds the follower evolved. Where the EVOLVE button appears: the Pets panel
  card, the Food Machine row, and a pulsing gold "EVOLVE!" pill on the floating pet card (tap = opens the Pets panel on
  that pet).
* Looks and budgets: own evolved followers at **Low** detail (EvoLow <= 380 / AscLow <= 520 parts, instead of High
  1560 / 2000); other players' evolved followers Low only within 40 studs and at most 6 at a time (nearest first),
  else the normal Low model with a star on the card; garden / training pets at home: the normal Low model + a star on
  the card (17 evolved home pets would cost ~8.8K parts); battle units: own units evolved Low, NPC and others' normal
  Low. `PetBuilder.GetHeight` has no stage option and caches by a look signature without Evolved (:6840-6874): callers
  pass the stage through `opts.Evolved` only, never on the shared def, and PetController measures its built model
  (`GetExtentsSize`) and caches by `key|stage`. `tools/contract.json`: `petEvoLow 380`, `petEvo2Low 520`.
* Fusion: the result gets the input key's stage and ranks (the higher of each); a Mix (hybrid) starts at stage 0 with
  the parents' higher ranks per skill ("Fusing keeps your pet's evolution and training"); a training input is refused.

#### 3.7 The Training Place (ids `Gym`) and the training lock

| Skill (UI label) | Per rank | At rank 10 | In the engine |
|---|---|---|---|
| Attack Speed (`Speed`) | +4% attacks | +40% | `interval / (1 + 0.04 n)` (the cached `def.Stats.Speed` is never mutated) |
| Physique | +5% max health | +50% | `MaxHp x (1 + 0.05 n)` applied AFTER `scale` (:311-314) so the special does not grow with it |
| Ability | +4% special power, +4% special charge | +40% / +40% | `specialPower x (1 + 0.04 n)`; meter gains x `(1 + 0.04 n)` |
| Defense | -3% damage taken | -30% (cap) | `dmg x (1 - 0.03 n)` in `BattleSim.applyDamage` after the RETREAT halving, before MinHit / shields |

* `BattleCatalog.Training = { MaxRank = 10, Speed = 0.04, Physique = 0.05, Ability = 0.04, AbilityMeter = 0.04, Defense = 0.03 }`;
  `UnitPower = sqrt(Dps x MaxHp / (1 - Defense)) x PowerScale` so TeamPower, ExpectedDps, AverageMaxHp, the duel
  practice gap (`DUEL_POWER_GAP`) and raid boss HP stay honest. Measured on the real BattleSim (integration's
  `train_proto.lua`): all four skills rank 5 = x1.33 team power, rank 10 = x1.73, Evolved II + rank 10 = x2.6; trained
  mirror duels 50-54% with no draws or timeouts; raids stay about dodging (boss damage is a share of pet HP). The fun
  design's x2.0 training is NOT used.
* Cost of rank r: **300 x r^2 x RarityScale** Cash (Common 300 ... 30,000 per rank; all 40 ranks $462K; Legendary x5.5).
  Time of rank r: **r minutes**. Prices do not scale with stars. Kid rule: "Rank 3 takes 3 minutes."
* Spots: the Training Place level = pets training at once (1..5). Starting needs the station (level >= 1) and a free
  spot; running jobs survive a Prestige (the station resets, the jobs finish; new jobs wait for the rebuilt station).
* **The lock** (one source of truth: `DataService.TrainingKeys(player)`): a key with a running job cannot be equipped
  (`PetService.Equip`: "Rocky is training (2:10 left)"), placed in the Garden, fused, or fielded; `ActiveTeamKeys` /
  `FieldableKeys` / `normalizeEquipped` SKIP it at read time (the preset keeps it: `P3.prune` is never taught about
  training because it runs in normalizeProfile, copyProfile, applyDelta and MutateHome's pruneLive and would delete the
  pet for good). Training a key in the caller's running battle is refused (`BattleService.KeysInBattle`).
* **Auto-remove / auto-return / refund** (fun): Start unequips every equipped copy of the key (`PetService.UnequipKey`)
  and clears its Garden slot, remembering `Job.From` = "Follow" | "Garden:<slot>" | "Free". When the job ends the rank
  is added and the pet goes back: "Follow" -> re-equipped if a follow slot is free; "Garden:n" -> back to that place if
  open and empty, else the first free open place, else it stays in the list. `TrainStop` removes the job and refunds
  `Job.Paid` in the same step ("Stop training? You get the Cash back, no rank"). Toasts: "Rocky started Physique
  training (4:00)", "Rocky finished Physique training: Rank 3!", "Training done while you were away!" on load.
* Completion is decided from `os.time() >= Job.Ends` by PetCareService's 1 s tick and on profile load / rebase inside
  `DataService.MutateGrowth` (refused while provisional); the rank is a TARGET value ("rank 3"), so two servers
  completing the same job give rank 3, not 4.
* `Home.Gym` is retired: on every Phase 4 home load PetCareService empties it (old Gym pets come back to the list, one
  toast "The Gym is now the Training Place: your gym pets are back with you"). Old Gym levels = training spots 1:1.
* World: five mats keep the `Spot1..5` attachments on the deck; HomeFx draws the pet on its mat in the skill's pose with
  a pooled voxel prop (treadmill / dumbbell / orb / shield dummy, <= 12 parts each) and a timer on its card.

#### 3.8 The Champion Ring (mode id `Ring`; the endless NPC ladder)

* **Where:** `Portal_Ring` on the plaza, the next free gate of the portal fan beside `Portal_Trials` (LobbyBuilder:
  `L.RingAngle` = the first free position among `PortalAngles[1] - PortalStep` and `TrialAngle + PortalStep` with the
  same >= 30 degree checks as the trial site, LobbyBuilder.lua:1237-1246; a stone patch + path like the trial's;
  exported as `LobbyInfo.RingSite`). Built by ArenaBuilder with `buildTrialPortal` (:2221): title "Champion Ring", info
  "Beat the champion, meet a stronger one", pill "Best in this server: Alex - Round 31" (from the portal attribute
  `RingBoard` = `"Alex|31;Sam|24;Kim|20"`, written by BattleService when a run ends), prompt `RingPrompt` with
  `OpenPanel = "Ring"`, <= 70 parts, parented to `workspace.BattleArena` like Portal_Trials (`ArenaInfo.RingPortal`).
  The arena budget stays **2500**: 2419 + <= 70 = <= 2489. Only if the lead decides the portal cannot fit does the
  zero-part fallback apply (a second prompt on Portal_Trials with `OpenPanelTab = "Ring"`); the cap is never raised.
* **Entry** (the player's rule, checked by the server in this order, each with its toast): a home claimed this session
  (`TycoonService.GetPlot`) else "Claim your home first"; at least one owned pet (`PetKeys.List`) else "You need a pet";
  the fighters: `DataService.ActiveTeamKeys` (training pets skipped), else the equipped keys, else the best owned pets
  by `UnitPower` (training pets skipped; up to `GetTeams().Slots`); then `canBattle` (BattleService.lua:705-729: not in
  an obby match, not in a portal party, not in a battle, alive, server not closing); within 30 studs of Portal_Ring
  ("Walk to the Champion Ring portal"); profile loaded and not provisional ("Your save is still loading, try again in a
  moment"). No prestige, trial clear or purchase needed. `teamOf` (:644-687) gets a `fallback` argument for the ring;
  its empty-team refusal "Pick your battle team first (Menu > Team)" stays for trials and duels.
* **Start round:** 1, or any boss round 10k with `Ring.Best >= 10k` (a picker in the ring window).
* **Rounds** (`BattleCatalog.ChampionTeam(round, runSeed)`, pure and deterministic; one pet per round, always crowned):
  * Rounds 1-3: one level-1 Common at Handicap **0.45 / 0.55 / 0.65** (pebble_pup, pip_penguin, honey_bunny), like Trial 1.
  * Round r >= 4: target TeamPower `FirstPower 3.0 x Growth 1.18 ^ (r - 4)`, x `BossBump 1.15` on every 10th round.
  * Species drawn with the run seed from the round's rarity band: 4-9 Common; 10-15 Common / Uncommon; 16-21 Uncommon /
    Rare; 22-27 Rare / Epic; 28-33 Epic / Legendary; 34-41 Legendary / Mythic; 42+ Mythic / Secret; never EventOnly.
  * Solve: a plain level-1 pet above the target gets `Handicap = max(0.3, target / power)`; else the lowest level 1..50
    (Normal) that reaches it; else the **mini-boss form** (`Boss = true`: HP x3, hits x1.3, model x1.7,
    BattleCatalog.MiniBoss) at the lowest level, Normal -> Golden -> Rainbow; else a level-50 Rainbow boss with
    `Boost = target / power` (> 1: HP and hits x Boost, a NEW entry field read next to Handicap in
    `BattleSim.unitFromDef` :439-511). Endless; power never drops round to round.
  * Measured on the real BattleSim (`synth/ring_proto.lua`, `ring_out.txt`): every one of the 12 single level-1
    starter pets (Economy and Combat Commons / Uncommons) wins rounds 1, 2 and 3 in **24 of 24 seeds**; the average
    single-pet win rate then falls gently: round 4 94%, 5 98%, 6 85%, 7 76%, 8 60% (the judges' "rung-4 cliff" is
    gone); median records per `sim_battle` stage: S1 Day 1 **16**, S2 19, S3 23, S4 24, S5 28, S6 32, S7 Prestige 1
    **36**, S8 38, S9 44, S10 Maxed **51**; fights 5-12 s; a run to the record takes 4-7 minutes. Round 20 = a Golden
    L33 boss owl, round 30 = a L43 Aurora Fox, round 45+ = level-50 Rainbow bosses with Boost x2 ... x208 at round 80.
* **Per round:** time limit 90 s (timeout = loss), a 44 x 44 ring zone, a fresh BattleSim (full HP, new meters),
  **3 s** between rounds with a side card "Round 13 in 3..." (never the screen centre).
* **Rewards per round won** (paid once per round battle through `payOnce` :1384):
  * Cash = `max(20 + 2 x r, floor(IncomePerSecond(player) x RingSeconds(r)))`, `RingSeconds(r) = min(9, 1.5 + 0.1 x r)`:
    "each win pays what your garden makes in a few seconds, more every round, at least $22". A NEW RECORD round pays
    **x3**. Share of garden time over a whole run (ring_proto run lengths): Day 1 ~16%, Mid ~32%, Prestige 1 ~34%,
    Maxed ~50%: worth doing, never better than the garden, which keeps filling its piles meanwhile. A player with no
    garden pets gets the floor only.
  * XP = `20 + 6 x r` per team pet (`GrantXp` source "Ring"); the round that ends the run pays a third under the
    trial-loss gate (3.5).
  * Beating a boss round (10k) for the FIRST time: **+100 Tokens** (decided inside the same `MutateRing` that raises
    `Best` past 10k, so it is paid once).
  * `Ring.Best = max(Best, round)` at every win; `Ring.Runs + 1` when a run ends. Double Rewards (tokens only today)
    does not touch ring Cash.
* **Run end:** a loss, a timeout, Forfeit, leaving the ring (the pocket leash), a disconnect, a respawn elsewhere,
  joining an obby match, or a shutdown (the running round is void, wins already paid stay paid). Back at the portal 4 s
  after the end (TRIAL_RETURN_DELAY) with the result card "12 wins, +$2,571, +806 XP, new record: round 12!".
* **Server flow** (BattleService; one new mode reusing the trial machinery): `BattleRequest("Ring", startRound)` ->
  `BattleService.StartRing(player, startRound)`; `REQUEST_COOLDOWNS.Ring = 1.5` (:224); dispatch next to "Trial"
  (:3143). One `RingRun` table per player: `{ Id, Player, Pocket, Zone, Round, Start, Seed, Keys, Wins, Cash, Xp,
  State = "Fighting" | "Intermission" | "Ending" }`. `Keys` are fixed at the start; the spec is rebuilt from them at
  every round (`teamOf`), so levels won during the run count at once. The pocket comes from the shared pool
  (`St.pocketBusy`, MAX_POCKETS 64) via `ArenaBuilder.BuildPocket(index, "Ring")` (pcall; the trial pocket is the
  fallback). `startRound(run)`: a new battle id, `BattleSim.new({ Mode = "Ring", Zone = {X = 44, Z = 44}, Teams = { spec,
  BattleCatalog.ChampionTeam(round, seed) }, TimeLimit = 90 })`, `newBattle(id, "Ring", ...)`, `b.Ring = run`,
  `addParticipant` (the new `InBattle` id is written BEFORE the old one is released: no gap, followers stay parked,
  GoHome / portals stay refused), `beginBattle`, `St.pocketBusy[index] = id`. `finalizeBody` (:1670-1825): a Ring WIN
  pays (`PAY.Ring = payRing`), sends "End" with `Rewards.Next = round + 1` and `Rewards.Cash`, keeps the participant,
  `task.delay(3, startRound)`; a LOSS / void goes the trial way (`finishTrial` :1575-1597: return teleport, release,
  `FreePocket`). Every mode branch that knows only Trial / Duel / Raid learns "Ring": `present` (:2937, the pocket
  leash), `forceRelease` (:1600), `finalizeBody` (:1804), `payOnce`'s shutdown text (:1396), `monitorBattle` texts
  (:2970-2978), `Forfeit` (:2868; during an intermission it ends the run cleanly with the last round kept), `dropOut`,
  `onPlayerRemoving` (:3176) and `Shutdown` (:3233, also between two rounds when no battle runs), `GetBattle` (+ `Round`),
  `startPayload` (:822: `d.Ring = { Round, Best, Start, Champion = { PetId, Level, Tier, Boss, Name } }`). `BattleEnded`
  fires with `Mode = "Ring", Round, Won`; EventService keeps ignoring non-Raid results; TutorialService listens for
  `RingWon`.
* `BattleSim` (battlecore): `Modes` + "Ring" (timeout = loss like Trial, :2389), `unitFromDef` reads `entry.Boost`,
  `entry.Evo`, `entry.Train`; `unitInfo` (:532-561) adds `evo`, `boss` and, for the owner's own pets, `xp` / `xpNext`
  (static info in "Start" only; the snapshot wire format does not change). `BattleCatalog`: `Zones.Ring = {44, 44}`,
  `TimeLimits.Ring = 90`, `Ring = { EasyRounds, FirstPower 3.0, Growth 1.18, BossEvery 10, BossBump 1.15, MinHandicap 0.3,
  Bands, CashFloorBase 20, CashFloorPerRound 2, SecondsBase 1.5, SecondsPerRound 0.1, SecondsMax 9, RecordMult 3,
  BossTokens 100, XpBase 20, XpPerRound 6, TimeLimit 90, Intermission 3 }`, `ChampionTeam(round, seed)`,
  `RingRewards(round, incomePerSecond, isRecord) -> { Cash, Xp, Tokens }`.
* `ArenaBuilder` (arenaworld): `DEFAULT_ZONES` / `MAX_ZONE` (:167-168) + `Ring = {44, 44} / 45` (today
  `zoneFloorSize` :838 errors on an unknown mode); `BuildPocket(index, kind)`: kind "Ring" builds a round 44-stud ring
  with a gold rim, four crown posts and a small cheering crowd of voxel cloud puffs, <= 220 parts (the pocket test
  window 100..250 holds), zone `Mode = "Ring"`, `ZoneId = "Ring"`; the default stays the trial pocket.
* Client: `ArenaController` opens the ring window from `RingPrompt` (`onPromptTriggered` :2569): record, "Best in this
  server", start picker (round 1 or a beaten boss round), the fighters with their power, "Next win: +$X +Y XP", START ->
  `Request("Ring", start)`. `BattleController`: `Hud.ModeText / TitleText` (:3086-3133) "CHAMPION RING - Round 8 - Best
  12" (today an unknown mode reads "DUEL"); the champion's crown + name tag; an End with `Rewards.Next` shows the side
  card "Round 8 won! +$319 +68 XP - Round 9 in 3" (no result card, floor kept; per-battle cleanup keyed by the battle id
  so `RESULT_SECONDS 12` / `END_LINGER 3.5` tolerate the next Start in the same pocket); the final End shows the result
  card with a Cash line, "Rounds won" and "NEW RECORD".

#### 3.9 Pet cards and the follow-behind formation

* One shared client builder `src/client/UI/PetCard.lua` (pets engineer, wave 2): `PetCard.New(adornee, mode, heightStuds)
  -> card`, `card:SetLevel(level, stage, ready)`, `:SetXp(frac)`, `:SetHp(frac)`, `:SetSpecial(frac, ready)`,
  `:SetTimer(frac, text)`, `:SetMode(mode)`, `:Destroy()`. A pixel-sized BillboardGui (World text rule): "Lv 12" at
  **22 px** bold with a dark stroke on a compact plate, ★ / ★★ for the stage (U+2605, like the HUD's ☁ / ◆ glyphs), bars
  6 px (XP blue, SPECIAL gold) and 9 px (HP green own / red enemy) at 1080p scaled by `Theme.ScaledSize`, card width
  96 px, LightInfluence 0, a fill is written only when it moved by > 0.004 (BattleController's rule :1464), never
  per frame. A pulsing gold "EVOLVE!" pill (an `Active` button) when the pet is ready.
* Modes: own follower / own garden pet: level + XP (MaxDistance 90); own unit in a battle: level + HP + SPECIAL + XP
  (140, `BAR_DISTANCE`); enemy / NPC unit: level + HP; other players' followers: level only (60, at most 12 cards at
  once, nearest first); a training pet at home: + a purple timer bar "2:10". Followers' cards are hidden while the
  owner is InBattle (the followers are parked).
* Data: own pets read `State.PetLevel(key)` + `TycoonCatalog.XpToNext` + `State.PetGrowth(key)` on `State.Changed`;
  other players' pets read the new player attribute **`EquippedInfo`** = `"23:1,5:0,51:2"` (level:stage per
  `EquippedPets` entry, same order), written by `PetService.refreshPlayer` (:305-328) on equip changes, level-ups and
  evolutions (at most every 0.5 s); garden / training pets read the plot attribute `GardenInfo` = `"1=23:1;3=7:0"` and
  `TrainingPets` (3.3, 3.7); battle units read `u.hp`, `u.meter / MeterMax` (already in every snapshot) and the static
  `evo` / `xp` / `xpNext` from Start, refreshed from `End.Rewards`.
* `BattleController.addBar` (:1202-1234) keeps the billboard name `HpBar` and its `Back` / `Fill` children (the fill
  code and tests find them by name) and grows rows under them. The HUD team rows (`rowFor` :2423) keep HP + meter;
  the meter is labelled "SPECIAL" (a charge meter, not a timer: BattleSim semantics do not change).
* **Follow behind** (PetController): `FORMATION` (:137-141) becomes trailing slots `{ side, up, back, ahead }`: 1 pet
  `{0, 2.3, 4.5, 0}`; 2 pets `{-1.8, 2.0, 4.2, 0}`, `{1.8, 2.6, 4.2, 0}`; 3 pets `{-2.2, 1.9, 4.0, 0}`, `{2.2, 2.5, 4.0, 0}`,
  `{0, 2.9, 6.5, 0}`; `ahead = 0` everywhere (RUN_AHEAD unused); `LEAD_H 0.12` kept (it cancels the filter lag); the
  generic fan (`slotOffsets` :216-228): side = sin(a) x 2.4, back = 4 + (1 - cos(a)) x 2.5. Evolved followers: `back`
  x min(1.4, height / 3). Prototyped through the :744-838 filter math (integration's `follow_proto.py`): 4.5 / 4.6 / 6.5
  studs behind at rest, worst lag 7.7 studs at 24 studs/s (< 12), settles at 6.5 (< 8), never ahead while moving.
  Followers dive into the home portal and pop out behind the owner (3.10).

#### 3.10 The home portal

* `HomeAction("GoHome")` (TycoonService.lua:1735-1739) now calls `TycoonService.OpenHomePortal(player)`: refused in an
  obby match ("Finish your match first"), in a battle or ring run ("Finish your battle first!", the Arena Gate's text),
  while locked in a portal party, while dead; cooldown 3 s; one portal per player (pressing again keeps the open one).
  Position: 6 studs in front of the character on the ground (server raycasts: forward stops 1.5 studs before a wall,
  down finds the floor; no floor -> the character's own position). Player attribute **`HomePortal`** =
  `"x,y,z,yaw,closesAt"` (`closesAt = workspace:GetServerTimeNow() + 10`), cleared on use, expiry or leave.
* A 0.2 s server loop: when the OWNER's HumanoidRootPart is within 3.5 studs of the portal point ->
  `SpotService.Teleport(player)` (home `SpawnCFrame`; with no claimed home the portal leads to the suggested free gate
  with the toast "Press E at the gate to claim this home!"), then the player attribute `PortalArrived = serverTime`
  (the arrival swirl) and `HomePortal` cleared. Only the owner is ever checked: "only he and his pets can go through" is
  automatic. The Home tile without a home (`GoToSpot`) opens the same portal toward a free gate.
* `SpotService.Teleport` (:1000-1021) and `onGoToSpot` (:1023) also refuse while InBattle (today a home teleport during a
  trial forfeits it a second later and during a duel costs -10 trophies).
* Client `HomePortalFx.lua` (new): draws every player's portal from `HomePortal` (a pooled ring of <= 30 voxel parts in
  the home's accent colour, sparkles, a 22 px name billboard "Alex's portal"; others' portals faded), shrinks it away
  on use or expiry, plays the arrival ring (<= 20 parts, 1.5 s) at `PortalArrived`. PetController: when its owner's
  portal was just used (a teleport > 35 studs within 0.5 s of the portal closing) the followers fly into the portal
  centre and shrink (0.4 s), then emerge behind the owner (the existing `p.fresh = 2` path). Zero server parts.

#### 3.11 Safe zones (what the sentence means in code)

* Sentence: "Pets fight only inside battle zones: the arena floor, the duel rings, the Trial pockets and the Champion
  Ring. Everywhere else (the plaza, homes, the shop, paths, the arena's forum and stands) is a safe zone: no fights, no
  damage, and nobody can pull you into a battle."
* Already true and unchanged: player damage exists only in obby matches (`DamageService.Damage` returns false unless
  InMatch, DamageService.lua:426); `PlayerService.lobbyTick` heals and rescues falls outside matches; pet HP exists only
  inside a BattleSim; battles start only in `NC_BattleZone` parts; commands work only inside the battle's zone; duels /
  raids need `InArena`.
* New: the ring pocket is an `NC_BattleZone` (Mode "Ring"); every teleport refuses InBattle (GoHome / the portal /
  `SpotService.Teleport` / `GoToSpot`; the Arena Gate already did); `PetCare` Feed / Train / Evolve and Fusion refuse
  keys of a running battle (`BattleService.KeysInBattle(player)`); a side toast when the local player crosses the arena
  boundary (ArenaController, client: "Battle Arena: pets can battle here" / "Safe zone"). No new HUD block
  (HudController is full and untouched).

#### 3.12 The pacing proof (`scratchpad/p4design/synth/sim_synth.py`, port it into `tools/sim_tycoon.py`)

Model: the fun design's player model (best-value pad, scoops every 20 s, 4 s per purchase, the Phase 3 roulette roll
schedule), with the Garden kept at level 1 through Prestige, no snack stock, `FeedBase 2.0`, the kid spending 25% of
the coins on food (the pet closest to evolving first), prices x1.5^stars, every rarity to 50, Monte Carlo 120 players:

```
first paid buy  0:27 (every player: Berry Bush L1 $15 after the free Garden at 0:07)
Cottage 2:07   Villa p10 22:27 median 30:27 p90 37:47   Manor 1:28:47   Sky Castle / 1st prestige p10 1:52 median 2:24 p90 2:50
2nd run median 56:40, 3rd run 42:00; seed 3 over 10 runs: 2:44, 56, 39, 33, 27, 24, 21, 20, 21, 23 min (shortest 19.9)
prestige Gems per hour by run: 37, 96, 122, 126, 131, 127, 117, 91, 71, 65 (570 Gems in 7.1 h = 80/h; Phase 3's own runs 75/53/41/33/27 min gave 100-133/h)
first EVOLVE p10 1:12 median 1:18 p90 1:35; second evolution within 3 runs: 7 of 120 players
income/s by minute (seed 3): 1: 5, 5: 12, 10: 16, 20: 30, 30: 48, 60: 180, 90: 396, 120: 752, 150: 1554
early purchase gap mean 1.34 min (p90 2.67); worst dead time 4.7 min; a Combat-pets-only player prestiges in 184 min
a kid who climbs the ring regularly (+8% income): 1st prestige 2:07, runs 56/37/33/26/23/21/19/20/22 min, Gems <= 136/h
ALL TARGETS MET (13 targets; the sim's TARGETS block is the one `tools/sim_tycoon.py` must carry)
```

Veterans (`synth/veteran_check.py`: 300 Phase 3 homes from the unchanged `tools/sim_tycoon.py`, stopped at random
moments, migrated by section 4.3): Home Level changed in 0 of 300; 77 homes keep extra (legacy) garden places (median
1); 37 homes have no garden pet placed (their income is 0 until they put one in: the welcome toast says so, and the
free Garden pad is the first thing they see). After the veteran fills the open places with their best Economy pets,
coins/s vs their old presses: Cottage homes (<= 30 min old) x0.46 median but the time to their next pad x0.80 (early
pads are cheaper); Villa x0.95 (pad time x0.45); Manor and up x2.4-3.9 (pad time x0.4-0.65); prestiged homes x1.2-2.6.
Nobody is slowed down; Combat pets (ignored by the check) can now work too.

### 4. Data: schema, the migration of Phase 3 saves (no lost progress), merge rules, the rollout

`PROFILE_VERSION` stays 2; every change is additive; new per-pet / per-ring data lives in NEW TOP-LEVEL fields or new
Home keys only. Verified rule: a Phase 3 server still running during the rollout saves through
`keepForeign(toStored(applyDelta(normalizeProfile(old), delta)), old)` (DataService.lua:2584); it rebuilds `Battle`
(`P3.cleanBattle` :1098, `P3.encodeBattle` :1143), `Teams`, `Tutorial` and every `PetLevels` entry (`cleanPetLevel`
:569) and `Home.Garden` / `Home.Gym` values (`cleanSlots` :628 keeps strings only) from the keys it knows, and
`keepForeign` (:1936-1963) restores only UNKNOWN top-level, Home and Stats keys. So nothing new goes inside `Battle`,
`Teams`, `PetLevels` entries or slot values.

#### 4.1 Fields

| Field | Shape | Default / old saves | Cross-server merge | While provisional | Dev reset |
|---|---|---|---|---|---|
| `PetGrowth` (NEW, top) | `{[key] = {Evo 0..2, Speed, Physique, Ability, Defense 0..10, Job = {Stat, Ends, Rank, Slot, From, Paid} or absent}}` | `{}` (left out of the store while empty) | per key: `Evo` and every rank = the HIGHER value; `Job` = the session's value (`false` in the delta clears it); `P4.cleanGrowth` drops a Job whose `Rank` is not above the stored rank of its `Stat` (a job completed elsewhere never re-applies) | `MutateGrowth` refused ("Your save is still loading") | wiped |
| `Ring` (NEW, top) | `{Best = 0..100000, Runs = 0..}` | `{Best = 0, Runs = 0}` (left out while default) | `Best`: the higher wins; `Runs`: +/- delta | `MutateRing` refused; the ring does not start | wiped |
| `Migrations` (NEW, top) | `{P4 = true}` | `{}` | union (grow-only) | allowed (set in the same step as the migration) | kept |
| `Home.LegacySlots` (NEW Home key) | number or nil | nil | with Home (per-key replace; a higher Prestige wins the whole Home, which drops it) | - | wiped with Home |
| `Home.LegacyPrices` (NEW Home key) | true or nil | nil | with Home, same | - | wiped with Home |
| `Home.CollectorCash` | number: the Cash lying on the lawn | unchanged field, new meaning | +/- delta (unchanged, :1730) | allowed (unchanged, MutateHome :3451) | with Home |
| `Home.Stations` | `{[id] = level}`, the same 18 ids | unchanged: Press1-4 = plant levels, Collector = Magnet level, Kitchen = machine, Gym = training spots | per-key replace (unchanged) | - | with Home |
| `Home.Garden` | `{[slot] = key}`, any role, slots 1..12 used | unchanged; extra keys above the open count stay (resting) | per-key replace (unchanged) | - | with Home |
| `Home.Gym` | `{[slot] = key}` | emptied on every Phase 4 home load (KNOWN_HOME keeps "Gym" so Phase 3 writes stay understood; `P3.placedCopies` keeps counting it, harmlessly) | per-key replace (unchanged) | - | with Home |
| `PetLevels` | `{Level, Xp}` | unchanged; every cap now 100 | per-key replace (unchanged) | `AddPetXp` refused (unchanged) | wiped |
| `Food` | counts | leftovers, spent first by the Food Machine | delta (unchanged) | - | - |
| `Battle`, `Teams`, `Tutorial` | unchanged shapes | untouched by Phase 4 | unchanged | unchanged | unchanged |

* `P4.cleanGrowth(raw)`: valid keys only (`validKey`); whole numbers clamped (Evo 0..2, ranks 0..10); `Job.Stat` one
  of Speed / Physique / Ability / Defense, `Job.Ends` a sane time (`sanitizeTime`), `Job.Rank` = that stat's rank + 1
  (else dropped), `Job.Slot` 1..5, `Job.From` a string <= 16 chars, `Job.Paid` >= 0; an all-zero entry without a Job is
  dropped. Size: ~80 bytes per trained / evolved key (150 keys = ~12 KB of the 4 MB limit).
* **Garden pets are no longer busy for battles**: `P3.placedCopies` (:996-1010) counts only `Home.Gym` (empty after the
  first Phase 4 load). Training is the only busy state and it is a READ-TIME filter: `FieldableKeys` (:3617) and
  `ActiveTeamKeys` (:3646) skip `TrainingKeys`; `normalizeEquipped` (:891-906) drops training keys on load (a Phase 3
  server may have equipped one during the rollout); `P3.checkTeam` (:3529) keeps accepting them in presets; `P3.prune`
  (:1015) is NOT taught about training.

#### 4.2 DataService touch points (data engineer; follow `PetLevels` / `Teams` line by line)

New table `P4` next to `P3` (:488) holds every helper (`cleanGrowth`, `copyGrowth`, `diffGrowth`, `applyGrowth`,
`cleanRing`, `cleanMigrations`, `migrate`): one new top-level local (157 -> 158). `OVERWRITABLE` (:211) and `KNOWN_TOP`
(:218): + `PetGrowth`, `Ring`, `Migrations`. `KNOWN_HOME` (:224): + `LegacySlots`, `LegacyPrices`. `newProfile`
(:522), `newHome` (:472), `cleanHome` (:680), `homesEqual` (:706), `homeVisiblyEqual` (:717: LegacyPrices alone is
not worth a snapshot), `copyProfile` (:1166), `normalizeProfile` (:1199), `profilesEqual` (:1276), `overwriteValues`
(:1384), `diffProfiles` (:1572: `P4.diffGrowth` = every changed key -> the whole clean live entry, a vanished key ->
false; `Ring` -> `Best` when it rose, `Runs` as a delta; `Migrations` -> new keys), `isEmptyDelta` (:1650), `applyHome`
(:1702: LegacySlots / LegacyPrices replace), `applyDelta` (:1740: `P4.applyGrowth` = max per number, Job replaced, then
`cleanGrowth`; Ring max / delta; Migrations union), `toStored` (:1880: defaults left out like Teams / Battle),
`keepForeign` (:1936: unchanged logic, the new keys are now known), `writeHome` (:1986), `replaceContents` (:1999),
`buildSnapshot` (:2254: `PetGrowth`, `Ring`), the header (:1-180) and the ResetFields notes (:2981-2988).
Public API (functions on `DataService`, no new locals): `GetGrowth(player, key)` (a copy, zeros when absent),
`GetGrowthMap(player)`, `MutateGrowth(player, fn) -> ok` (non-yielding; refused while provisional or not loaded; the
result is cleaned and no Evo / rank may go down; `SyncSoon`), `TrainingKeys(player) -> {[key] = true}`,
`GetEvolution(player, key)`, `SetEvolution(player, key, stage)` (only up), `GetRing(player) -> {Best, Runs} | nil`,
`MutateRing(player, fn) -> ok` (Best only up; refused while provisional), `IsMigrated(player, name)`,
`MarkMigrated(player, name)`. `State.lua`: `State.PetGrowth(key)`, `State.Ring()`, `State.Home().LegacySlots`.

#### 4.3 The one-time Phase 4 migration (`P4.migrate`, idempotent, runs on ProfileLoaded / ProfileRebased of a loaded, non-provisional profile with `Migrations.P4 ~= true`, in ONE non-yielding step)

1. **Extra garden places:** `oldSlots = Home.Stations.Garden` (a Phase 3 Garden's level WAS its slot count, 1..8);
   if `oldSlots > 3 + Prestige` then `Home.LegacySlots = oldSlots`. Kid rule: "You keep your extra garden places until
   your next Prestige."
2. **Old prices:** if `Home.Prestige > 0` then `Home.LegacyPrices = true` (no star price multiplier until the next
   Prestige: a Prestige 3 veteran is not hit with x3.4 prices in the middle of a run).
3. **The old Gym:** `Home.Gym = {}` (those Combat pets are free again; their Gym XP is already in `PetLevels`).
4. `Migrations.P4 = true`.
Then, on the first claim, one toast: "Welcome to the new home! Your presses grew into food plants, the Collector is now
a Coin Magnet, and your old Collector Cash waits in a coin pile by your garden. Put pets in your garden: they make the
money now!"

Everything else needs NO data change, by construction:

| Phase 3 data | Phase 4 meaning | Why nothing is lost |
|---|---|---|
| Press1-4 levels | Berry Bush / Carrot Patch / Cloud Melons / Starfruit Tree levels | same ids, same Home Level, same tier gates, same `Home.Level` from `HomeLevelOf` |
| Collector level | Coin Magnet level | same id |
| `Home.CollectorCash` (unbanked Cash) | coins on the lawn -> the Welcome-back pile | same delta field; scooped = paid exactly once |
| Garden level (slots 1..8) | Garden level = Lucky coins; places = 3 + stars, LegacySlots until the next Prestige | extra places kept for the run |
| Kitchen level / cooking queue | Food Machine level / (gone, never saved; refunded by Phase 3 servers at shutdown) | same id |
| `Food` (Snack / Meal / Feast) | leftovers, fed first and free | same field |
| Gym level / `Home.Gym` slots | Training Place spots / cleared | the XP those pets earned is kept |
| Vault level | Vault level (bigger piles + offline coins) | same id, same offline numbers |
| `PetLevels` | same; caps raised to 100 | caps only go up; a pet at 20+ / 50 is "Ready to evolve!" and gets its own EVOLVE moment |
| Prestige stars | + garden places, x1.25 coins, old prices this run | same field |
| `Tutorial.Step` | same index rule; chapter 4 appended | section 9 |
| `Teams` presets | unchanged (garden pets may now fight; training pets are skipped at read time) | no pruning |
| Equipped pets | unchanged | a training key is dropped on load (none exist at migration) |

No one-time Cash payout anywhere (a payout plus a marker can double-pay across two servers; every credit above is data
that merges idempotently).

#### 4.4 Rollout: Phase 3 and Phase 4 servers live at the same time (publish, then "Migrate to Latest Update")

| Situation | What happens | Why it is safe |
|---|---|---|
| A Phase 4 save is opened and saved by a Phase 3 server | `PetGrowth`, `Ring`, `Migrations`, `Home.LegacySlots / LegacyPrices` come back untouched | `keepForeign` restores unknown top-level and Home keys |
| ... its Battle / Teams / PetLevels | rebuilt from Phase 3's known keys | Phase 4 adds nothing inside them |
| A training pet on a Phase 3 server | it can be equipped and fight there; the job still completes later | ranks are target values; the lock returns on Phase 4 |
| A Phase 3 Collector banks the coin pile | the same Cash goes to the balance | same field, same meaning |
| A Phase 3 server puts a pet in the Gym / fills 8 Garden slots | Phase 4 empties the Gym on load; extra garden keys rest (do not eat) | idempotent, nothing lost |
| A Phase 3 server cooks food at shutdown | refunded as Food (`onClose` PetCareService.lua:1867-1896), fed for free in Phase 4 | Food stays a known field |
| A Phase 3 prestige on a migrated home | `LegacySlots / LegacyPrices` survive (foreign keys) until the next Phase 4 prestige | a small, temporary extra; no Cash involved |
| A Phase 4 player at tutorial step 19-21 on a Phase 3 server | "done" there, Step not rewritten (`newTrack` :1389-1391) | resumes chapter 4 on Phase 4 |
| A Phase 3 server sees `Garden` at level 1 with no `Press2` | valid (Requires are only checked when buying) | both versions read the same ids |

Fixture test `p4data_rollout`: the lead freezes today's `src/server/Services/DataService.lua` as
`tools/fixtures/DataService_phase3.lua` in wave 0; the test loads it as a second module against the same mock
DataStore, saves a Phase 4 profile through it ("a Phase 3 server") and checks that Phase 4 reads back `PetGrowth`,
`Ring`, `Migrations`, the legacy Home keys, the station levels and the Home Level unchanged. Fallback if the mock cannot
host two copies: compare the frozen file's `KNOWN_TOP` / `KNOWN_HOME` / `P3.encodeBattle` field lists with Phase 4's
new keys (none may sit inside a rebuilt table).

#### 4.5 Developer reset and fusion
`DevService.cmdReset` (:536-629) wipes `PetGrowth`, sets `Ring = {Best = 0, Runs = 0}`, leaves `Migrations`, adds both
to the `ResetFields` list (:609), calls `PetCareService.ClearSessions(player)` and `TycoonService.ClearCoins(player)`
instead of `ClearKitchen` (:573-576); new owner command `/petlevel <1..100>` sets every equipped pet's level (to try
EVOLVE quickly; dev-only, same rules as the others). `FusionService` (:900-940 commit) carries `PetGrowth` as in 3.6
through `DataService.MutateGrowth` in the same non-yielding commit, refuses training inputs, and places a fused result
back into a freed Garden slot whatever its role (no Gym placement; `freeHomeSlots` :791-850).

### 5. Remotes, payloads and APIs (NO new RemoteEvent; `Config.Remotes` keeps its list, only the comments :100-107 change)

#### 5.1 Remote actions

| Remote | Action (args) | Server checks | Rate limit | Answer |
|---|---|---|---|---|
| HomeAction | `Upgrade` (stationId) | unchanged + `PriceAt` (star price unless LegacyPrices) | unchanged | unchanged |
| HomeAction | `GardenSet` ({Slot, Key} or {Slot}) | slot 1..GardenSlots(home), ANY role, owned free copy, not training, not in a running battle | unchanged | toast |
| HomeAction | `Collect` | scoops every pile in range (kept for old clients / tests) | unchanged | - |
| HomeAction | `Prestige` | unchanged | unchanged | + "Garden place N unlocked!" toast |
| HomeAction | `GoHome` | not in a match / battle / ring run / portal party, alive | 3 s | `HomePortal` attribute |
| PetCare | `Feed` (key, opts) with `opts = nil` (machine food) or a table `{Food = "Snack"|"Meal"|"Feast"}` (a leftover) or `{Count = 1..10}` ("Level up"); a plain string in `b` is read as `Food` (old clients) | owned, level < 100 (the cap), machine built (machine food), Cash, loaded, not in battle | 0.1 s + the shared burst 12 / 6 per s | toast + one sync |
| PetCare | `Evolve` (key) | owned, level >= 20 / 50, stage < MaxEvolution, not in battle, not provisional | 1 s | `OpenPanel("Evolve")` |
| PetCare | `Train` (key, stat) stat in Speed / Physique / Ability / Defense | owned, station, free spot, not training, not in battle, rank < 10, Cash | 0.25 s | toast |
| PetCare | `TrainStop` (key) | a job exists | 0.25 s | toast (refund) |
| PetCare | `Cook`, `GymSet` | retired: one toast | - | - |
| BattleRequest | `Ring` (startRound: 1 or a beaten boss round) | section 3.8 | 1.5 s | Start / toast |
| BattleCommand | `Forfeit` | during a ring intermission ends the run cleanly (last round kept) | unchanged | - |
| GoToSpot | () | the no-home Home tile: opens the portal toward a free gate | unchanged (0.25 s) | `HomePortal` |
| OpenPanel (S->C) | `("Pets", {Action = "Feed"})` from the Food Machine prompt; `("Pets", {Action = "Garden", Slot})` from a garden spot; `("Train")`; `("Evolve", {Key, Stage})`; `("Ring")` | - | - | - |
| BattleState (S->C) | `Start` + `Ring = {Round, Best, Start, Champion}` + unit `evo` / `boss` / own `xp`, `xpNext`; `End` + `Rewards.Cash`, `Rewards.Next`, `Rewards.Record`, `Rewards.Tokens` | - | - | - |

Every action: type / range / NaN checks, a per-action cooldown and the shared per-player burst budget (HomeAction burst
10 refill 5/s; PetCare 12 / 6 per s; BattleRequest token bucket); refusal toasts throttled (existing patterns).

#### 5.2 Prompts (server-made ProximityPrompts; HomeFx's owner-only rule hides home prompts from visitors; `applyOwnerAttr` writes `OwnerUserId`)
* `GardenSpotPrompt` "Put a pet here" on each open empty place (attributes `Slot`, `OwnerUserId`; MaxActivationDistance 3) -> client `OpenPanel("Pets", {Action = "Garden", Slot})`.
* `FeedPrompt` "Feed pets" on the Food Machine's `Hopper` part (PetCareService `ensurePrompts` :1620-1660 replaces the CookPrompts; `CARE_SIG` gains a "p4:" marker so stale Kitchen prompts rebuild) -> server `OpenPanel("Pets", {Action = "Feed"})`.
* `TrainPrompt` "Train pets" on `Station_Gym` -> `OpenPanel("Train")`.
* `RingPrompt` "Champion Ring" on `Portal_Ring` with attribute `OpenPanel = "Ring"` (opened on the client like Portal_Trials, ArenaController `onPromptTriggered` :2569).
* Removed: `CollectPrompt`, `CollectPad`, the Collector routes (`underCollector` / `onCollectPrompt` TycoonService.lua:1594-1654), `CookPrompt`s, the Kitchen `FeedPrompt` on the FeedBowl.

#### 5.3 Attributes (written only on change)

| On | Name | Format | Writer | Readers |
|---|---|---|---|---|
| Player | `EquippedInfo` (Config.Attr) | `"23:1,5:0"` level:stage per EquippedPets entry | PetService.refreshPlayer | PetController (others' cards, evolved models) |
| Player | `HomePortal` (Config.Attr) | `"x,y,z,yaw,closesAt"`, removed when closed | TycoonService | HomePortalFx, PetController |
| Player | `PortalArrived` (Config.Attr) | server time | TycoonService | HomePortalFx |
| Player | `InBattle` (kept) | battle id; a ring run swaps ids with no gap | BattleService | many |
| Plot folder | `CoinPiles` | `"1=3;2=5F;4=2*;W=5"`: slot = heap stage 0-5 (coins 0 / 1-2 / 3-5 / 6-11 / 12-23 / 24+), `F` full (the pet naps), `*` a Lucky coin on top, `W` the Welcome-back pile (5 while it holds anything); ~0.2 writes/s per plot | TycoonService | HomeFx |
| Plot folder | `CollectorCash` (kept name) | Cash waiting on the lawn | TycoonService | MenuController ("Coins waiting"), HomeFx |
| Plot folder | `IncomePerSecond`, `HomeLevel`, `Prestige` | kept | TycoonService | MenuController, SpotService nameplate |
| Plot folder | `GardenPets` | kept format `"1=cat;3=fox@Golden"` (any role) | TycoonService | HomeFx |
| Plot folder | `GardenInfo` | `"1=12:0;3=20:1"` level:stage per placed slot | TycoonService | HomeFx cards |
| Plot folder | `GardenSlots` | the open place count | TycoonService | HomeFx (seedlings vs cushions), MenuController |
| Plot folder | `TrainingPets` (replaces `GymPets`) | `"1=cat:Physique:1760000000;2=fox@Golden:Speed:1760000420"` mat = key:stat:Ends | PetCareService | HomeFx (PET_STATIONS :174-177 renamed) |
| Portal_Ring | `RingBoard` | `"Alex|31;Sam|24;Kim|20"` | BattleService | ArenaBuilder's pill SurfaceGui |
| NC_BattleZone | `Mode` | + "Ring" | ArenaBuilder | ArenaBuilder.ZoneAt |
| Removed | plot `CollectorCap`, `GymPets`; player `KitchenQueue`, `KitchenReadyAt`, `KitchenDishSeconds`; Home folder `CollectorCash` / `CollectorCap` (`HomeBuilder.SetCollector`) | | | |

#### 5.4 Module APIs (new or changed; signals exist at module load because TutorialService.Init runs first, Main.server.lua:335-383)
* `TycoonCatalog`: data `Coins = { MealSeconds 8, GrassFood 12, LuckyMult 5, BaseRadius 6, BasePileSeconds 240, HeapStages {1, 3, 6, 12, 24} }`,
  `Prestige.GardenSlotsBase / GardenSlotsPerStar / GardenSlotsMax / PriceStep`, `FeedShare`, `FeedBase 2.0`, `Training = { MaxRank 10, CostBase 300, MinutesPerRank 1 }`;
  functions `FoodOf(home)`, `PetPower(entry, level, tier, stage)`, `GardenSlots(home)`, `IncomePerSecond(home, entries, prestige) -> cash/s, { Food, Pets, Lucky, Multiplier }`
  (same signature; no Collector condition), `LuckyChance(home)`, `ScoopRadius(home)`, `PileSeconds(home)`, `CoinPoint(slot)`, `OfflineEarnings` (unchanged API),
  `FeedXp(level, machineLevel)`, `FeedPrice(def, level)`, `TrainCost(def, rank)`, `TrainSeconds(rank)`, `TrainingSlots(home)`, `StarPriceMultiplier(home)`,
  `PriceAt(id, level, home)`, `XpToNext`, `Validate` (new per-kind rules: Plant Food rising, Garden Lucky non-decreasing <= 0.5 and >= 12 Spots, Magnet Radius /
  PileSeconds rising, FoodMachine FeedShare rising <= 1, Training Slots rising, Vault PileSeconds rising, coin points inside the yard and off pads, the
  WelcomePile off pads). Removed: `PressIncome`, `CollectorCap` (alias kept one release returning `PileSeconds x income`), `KitchenSpeed`, `CookSecondsFor`,
  `FoodsFor`, `GymXpPerMinute`, `GymSlots` (-> `TrainingSlots`); `PetIncome` kept as an alias of `PetPower x FoodOf / 8`.
* `PetCatalog` (lead, LANDED in wave 0): `LevelCaps` all 100 (`MaxLevel` fallback 100; `TycoonCatalog.PetXp.MaxLevel` 100), `EvolutionLevels {20, 50}`, `EvolutionBoost {1.25, 1.5}`, `EvolveTwice` (the Epic+ rarity set),
  `RoleMult = { Economy 1.6, Combat 1 }`, `MaxEvolution(subject)`, `EvolutionStage(subject, level, stored)`, `CanEvolve(subject, level, stage)`,
  `EvolutionMultiplier(stage) -> 1 | 1.25 | 1.5`, `RoleMultiplier(subject) -> 1.6 | 1` (a subject is a def, a rarity id, a pet id or a pet key; a hybrid key needs
  its def from `PetKeys.DefOf`); `StatsOf` / `GetStats` unchanged; `StatNames.Income` reads "Coins".
* `BattleCatalog`: `Zones.Ring`, `TimeLimits.Ring`, `Ring`, `ChampionTeam`, `RingRewards`, `Training`, `UnitStats(subject, level, tier, extras)` with
  `extras = { Evo, Train = {Speed, Physique, Ability, Defense}, Boost }` (also read from an entry table), returning `Defense`, `MeterRate`, `Evo`;
  `UnitPower` / `TeamPower` / `ExpectedDps` / `AverageMaxHp` honour them; `TrialRewardRules.LossShare = 1/3`, `LossMinSeconds = 20`, `LossMinDamage = 0.2`.
* `BattleSim`: `Modes` + "Ring"; entry fields `Evo`, `Train`, `Boost`; `unitInfo` + `evo`, `boss`, `xp`, `xpNext`; Defense in `applyDamage`; meter gains x `meterRate`.
* `DataService`: section 4.2. `PetService`: `Equip` refuses training keys; `UnequipKey(player, key)` (all copies); `Refresh(player)` writes `EquippedInfo`.
* `PetCareService`: `Feed(player, key, opts) -> ok, {Xp, Levels, Level, Cap, Paid, Free}`, `Evolve(player, key) -> ok, stage | reason`,
  `Train(player, key, stat) -> ok, {Rank, Ends, Cost} | reason`, `TrainStop(player, key)`, `GrantXp` (kept), `LevelCap` (kept), `ClearSessions(player)`;
  signals `Fed` (kept; foodId "Machine" for machine food), `LevelUp` (kept), `Evolved(player, key, stage)`, `TrainingStarted(player, key, stat)`,
  `TrainingDone(player, key, stat, rank)`. Removed: `Cook`, `GymSet`, `GetQueue`, `ClearKitchen`, `Cooked`, `GymChanged`.
* `TycoonService`: `Init(lobbyInfo, deps{DataService, PetService, SpotService, BattleService})`, `GetPlot`, `GetHome`, `Buy`, `Collect(player) -> ok, amount`
  (scoop in range), `Prestige`, `IncomePerSecond(player)`, `PileSeconds(player)` (+ `CollectorCap` alias), `CoinsWaiting(player)`, `GardenSet(player, slot, key)`,
  `GoHome(player)` = `OpenHomePortal(player)`, `ClearCoins(player)`; signals `HomeChanged`, `Claimed`, `Prestiged`, `Released` (kept),
  `CoinsScooped(player, amount)`, `PortalUsed(player)`.
* `SpotService.Teleport(player)` and `onGoToSpot` refuse InBattle. `BattleService`: `StartRing(player, startRound) -> ok, battleId | reason`,
  `KeysInBattle(player) -> {[key] = true}` (battle or ring run), `BattleEnded` results carry `Round`, `Won` for Mode "Ring".
* `HomeBuilder`: `SetGarden(spotInfo, valid, open)` (the existing hook), `SetTraining(spotInfo, pets)` (optional, HomeFx reads the attribute),
  `Art.Plant` (4 looks by `def.Id`), `Art.Magnet`, `Art.FoodMachine`, `Art.Training`, `Art.Garden(def, level, open)`; `SetCollector` removed.
* `ArenaBuilder`: `BuildPocket(index, kind)`, `ArenaInfo.RingPortal`, zone Mode "Ring". `LobbyBuilder`: `LobbyInfo.RingSite`.
* Client: `PetCard.lua` (3.9), `CareController.lua` (new: `Init`, `Open(panelId, args)` for "Feed" | "Garden" | "Train" | "Evolve", `Close`, `IsOpen`),
  `HomePortalFx.lua` (new: `Init`, `Stop`), `PetController.PlayEvolution(key, stage)`, `CloudUI.PetViewport(holder, def, size, {Spin, Evolved})`.
* `Main.server.lua` (lead): BattleService passed to TycoonService / PetCareService / FusionService Init deps (module tables exist before Init);
  `Main.client.lua`: `CareController`, `HomePortalFx` in the controller list and `OPTIONAL`. `Config.Attr`: `EquippedInfo`, `HomePortal`, `PortalArrived`.
  `tools/contract.json`: the new public functions, `partBudget.petEvoLow 380`, `petEvo2Low 520`.

### 6. Client vs server responsibilities and budgets (the Replication rule, feature by feature)

| Feature | Server (authority; never per-frame motion) | Client (visuals; per-frame motion allowed) |
|---|---|---|
| Rainbow coins | meal timer (the 1 s `tickPlayer`), piles, `CollectorCash`, the 0.25 s owner proximity scoop, `AddCash`, attributes | pooled voxel coins and heaps, eat / poop animation, fruit flights, "Zzz", the scoop zip with rising dings, the "+$1,234" pixel label AT THE PILE (never over the player's head: in third person that is the screen centre), the Magnet ring (HomeFx) |
| Food Machine | price, XP, Cash, level-ups, refusals | the feed list + XP bars (CareController), hopper / chute animation (HomeFx) |
| Evolution | rules, stage write, OpenPanel | EvolutionFx on clones in the world, the evolved follower model (PetController) |
| Training | jobs, `os.time()` timers, ranks, the lock, auto-return | mats + per-skill poses + props + timers (HomeFx), the training window (CareController) |
| Champion Ring | one BattleSim per round, chaining, rewards, record, `RingBoard` | HUD texts, the "Round 13 in 3..." side card, the result card (BattleController), the ring window (ArenaController) |
| Pet cards | `EquippedInfo`, level / XP in Start | BillboardGui cards (PetCard in PetController, BattleController, HomeFx) |
| Follow behind | nothing | formation (PetController) |
| Home portal | position, owner check (0.2 s), teleport, `HomePortal` / `PortalArrived` | portal ring + swirl + name, arrival ring, followers' dive (HomePortalFx, PetController) |
| Safe zones | damage only in matches; battles only in zones; InBattle guards | the "Battle Arena / Safe zone" side toast (ArenaController) |

| Budget | Today | Phase 4 | Held by |
|---|---|---|---|
| Home plot parts (test cap 950, `smoke_p2_homeworld.lua:543-544`) | 911 fully built | ~900-925: presses 41-48 x4 + Collector 53 + belt ~25 + Garden 58 + Kitchen 50 + Gym 57 out; plants <= 45 each, Magnet <= 55, Garden (12 places, server) <= 85, Food Machine <= 55, Training Place <= 90 in; bowls, fruit, props, heaps and coins are CLIENT parts | per-station BUDGET table (`:181-182`): Plant 45, Magnet 55, Garden 85, FoodMachine 55, Training 90, House 150, Fusion 90, Fence 60, default 80; measured by `render_model.py homeplot:SkyCastle:pads` |
| Arena world (`smoke_p3_arenaworld.lua:219`) | 2419 of 2500 | + Portal_Ring <= 70 -> <= 2489; the cap stays 2500 | portal art trimmed before anything else |
| Ring pocket | trial pocket <= 250 | <= 220, built on demand, freed after the run | the pocket pool (MAX_POCKETS 64 shared with trials) |
| Lobby | 6382 of 6500 | unchanged (Portal_Ring is parented to BattleArena) | |
| Client coins | - | heaps <= 13 per home x <= 40 parts (Welcome heap <= 60), only homes within PET_NEAR 110; flying coins pooled <= 40; fruit <= 24; props <= 5 x 12; bowls 2 x 12 | HomeFx pools (the block-pool pattern :1096-1129) |
| Follower models | 3 x High 350 | own evolved Low <= 380 / 520; others' evolved Low within 40 studs, max 6 | PetController; contract.json `petEvoLow / petEvo2Low` |
| Home portal | - | <= 30 client parts per portal, drawn within 150 studs, 0 server parts | HomePortalFx |
| Pet cards | - | BillboardGuis: 3 own + <= 12 others' + home pets within 40 studs; one per battle unit (raids ~64; only own units get the 4-row card) | pixel sizes, event-driven writes |
| Server CPU | 1 s income tick | + 0.25 s scoop loop (16 plots x <= 13 piles), 0.2 s portal loop (<= 16), 1 s training tick, one BattleSim per ring run (like a trial) | no per-frame server loops |
| Network per client | - | `CoinPiles` ~0.2 writes/s x ~60 B per plot (< 0.3 KB/s with 16 plots); `CollectorCash` / `IncomePerSecond` <= 1 write/s per plot (as today); `GardenInfo` / `TrainingPets` / `EquippedInfo` on change; a ring = a trial-sized stream (~10 snapshots/s, a few KB/s) + one Start (2-4 KB) per round; ProfileSync stays <= 4/s (scoops use AddCash only; "Level up" is one request and one snapshot; a ring win grants XP to 3-4 keys -> one coalesced snapshot) | `p3bs_net`, the new `p4garden_net` check |
| DataStore | autosave cadence | unchanged; + <= ~12 KB worst case | additive fields |
| Lua locals (limit 200) | DataService 157, PetCareService 146, TycoonService 127, BattleService 134, MenuController 184, ArenaBuilder 180, HudController 155, HomeFx 152 | each file + at most 3 | ONE helper table per file (`P4` in DataService, `Coins` / `Portal` in TycoonService, `Care` in PetCareService, `RingRun` in BattleService); every new window in `CareController`; HudController untouched; engineers re-run `count_locals.py` before handing in |

### 7. Exploits and how they are closed

| # | Attempt | Closed by |
|---|---|---|
| X1 | Forge a coin pickup | There is no pickup remote: the server reads the OWNER's HumanoidRootPart every 0.25 s (ScoopRadius / 10 studs) |
| X2 | Pick up someone else's coins (touch, standing in their garden) | Only `plots[player]`'s owner is checked; coins are not Parts |
| X3 | Teleport-sweep or speed-hack the garden | Only sweeps coins the pets already made; production is server-timed; the pile cap bounds AFK gains (PileSeconds per pet + the Vault's offline share) |
| X4 | Pay a pile twice / across servers / on rebase | Pickup = `MutateHome(CollectorCash - take)` then `AddCash` in one non-yielding step, refund on failure; the bank is delta-merged; the live ledger is rebuilt from `CollectorCash` as the Welcome-back pile on load, claim and `ProfileRebased` (TycoonService re-runs `onHomeLoaded` on rebase, :1831-1834) and every pickup is clamped to the bank |
| X5 | Churn the meal timer (remove and re-place a pet right after a coin) | `GardenSet` keeps the slot's `NextMealAt` when the same key returns within one meal, and a NEW placement's first coin waits a full MealSeconds |
| X6 | Pay offline coins twice | Added to the bank in the same `MutateHome` that writes `LastSeen` (the existing pattern) |
| X7 | Junk Feed counts / prices / batch pricing | `Count` whole 1..10; each feed is priced at the level it is eaten at (the sum is recomputed server-side feed by feed); Cash taken only after every check, inside one step; refund when the XP write gives 0 |
| X8 | Spend a leftover Snack twice on two servers | Food is a delta merge clamped at 0; XP is per-key replace |
| X9 | Evolve early / twice / mid-battle / force a stage from the client | level, stage and rarity checked on the server; stage only up (max merge); refused in a battle or ring run; free (nothing to dupe) |
| X10 | Train, then equip / fight / fuse / garden / sell | one `TrainingKeys` source in Equip, normalizeEquipped, ActiveTeamKeys, FieldableKeys, GardenSet, Fusion, teamOf and the ring start |
| X11 | Complete a training twice (two servers) / stop and complete | the rank is a target value, max-merged; a stale Job is dropped by the sanitizer; Stop refunds `Paid` in the same step that removes the Job (a stale server completing the same Job can only set the same target rank: at most one refund + one rank in the rollout minutes) |
| X12 | Clock tricks | `Ends` is server `os.time()`; the client only displays it |
| X13 | Farm ring round 1 / low rounds | Cash per round is seconds of the climber's own garden income with a $22 floor: rounds 1-10 pay about $300-400 for ~3 minutes; runs restart at 1 or a beaten boss round; 1.5 s request cooldown; `payOnce` per battle id; the record x3 and the boss Tokens are paid once ever (`Ring.Best` grow-only, decided inside `MutateRing`) |
| X14 | Out-earn the garden in the ring | Cash is bounded to <= 9 s of garden income per round: a whole run is 16-50% of what the garden made meanwhile (3.8); a player with no garden pets gets the floor only; Double Rewards does not touch ring Cash |
| X15 | Keep loss XP by quitting / leaving the pocket / instant-forfeit farming at the Trial Portal | loss XP only for a real loss (>= 20 s or >= 20% damage dealt; never forfeit / leave / disconnect / shutdown) |
| X16 | Swap the team mid-run / add a pet from the garden mid-run | the run's key list is fixed at start (levels refresh per round) |
| X17 | Start the ring from afar / in a match / without a home or a pet / on a provisional save | the start checks of 3.8, in order, each with its toast |
| X18 | Use someone's home portal / escape a battle or a match by portal or home teleport | only the owner's root is checked; refused InBattle / InMatch / portal party in TycoonService AND SpotService.Teleport / GoToSpot |
| X19 | Spam GoHome / Feed / Train / Evolve / Ring | cooldowns 3 / 0.1 / 0.25 / 1 / 1.5 s + the shared burst budgets |
| X20 | More garden places than allowed; a Phase 3 server filling 8 slots during the rollout | `GardenSet` checks slot <= `GardenSlots(home)`; extra keys rest (do not eat); LegacySlots only from the one-time migration and cleared by the next Prestige |
| X21 | Rapid prestiges to farm Gems | prices x1.5^stars keep every run of the first ten >= 20 min (sim); Gems/h stay at Phase 3's level (3.12) |
| X22 | Veterans dodging the star price forever | `LegacyPrices` is set once by the migration and cleared by the next Prestige (a higher Prestige wins the whole Home on merge) |
| X23 | Pull a player into a fight outside the arena | battles only start in zones; duels need both players in the arena; damage only in matches |
| X24 | Junk remote arguments | every new action type-checks, clamps (slot 1..64, key <= 48 chars, stat in the 4 names, round 1..100000) and goes through the existing burst budgets |

### 8. Tests and sims to add or update

#### 8.1 New smoke files (each owner registers their own file in `tools/smoke.py`; smoke.py fails on an unwired `tools/smoke_*.lua`, :407-410)

| File | Worlds | Owner (wave) | Covers |
|---|---|---|---|
| `smoke_p4_data.lua` | server (pure + booted) | data (W1) | PetGrowth / Ring / Migrations schema and cleaning, `MutateGrowth` / `MutateRing` rules, provisional refusals, merges (two servers completing one rank = one rank; Evo max; stale Job dropped; Ring Best max / Runs delta), `TrainingKeys` filters (ActiveTeamKeys / FieldableKeys / normalizeEquipped skip, presets kept), `P3.placedCopies` = Gym only, `P4.migrate` (LegacySlots / LegacyPrices / Gym cleared / marker; idempotent; two servers), snapshot fields, dev reset, `/petlevel`, and `p4data_rollout` (4.4) |
| `smoke_p4_economy.lua` (rewrite of `smoke_p2_economy.lua`, same scenario name `p2_economy`) | server, pure | economy (W1) | the same 18 CONTRACT_IDS; Kinds; a fresh home shows ONE pad (the free Garden); the re-rooted tree ("Needs the Villa" for Cloud Melons, "Unlocks at Prestige 1" for Fusion); `PriceAt` x1.5^stars and the LegacyPrices exemption; `FoodOf`, `PetPower` (Economy / Combat == 1.6 at equal rarity / level / tier; evolution x1.25 / x1.5), `IncomePerSecond` with Lucky EV; `GardenSlots` 3 / 4 at 1 star / 12 max / LegacySlots; `PileSeconds` / `ScoopRadius` by Magnet + Vault; `OfflineEarnings`; `FeedXp` / `FeedPrice`; `TrainCost` / `TrainSeconds`; Validate; layout (12 Spots, coin points off pads, no Conveyor); parity with the constants block of `tools/sim_tycoon.py` (>= 60 constants) |
| `smoke_p4_garden.lua` | server (W2 tycoon) + client (W3 homefx) | tycoon, then homefx | an Economy pet drops a coin after 8 s and a Combat pet 1/1.6 of it; Lucky by Garden level (seeded RNG); the pile cap -> `F`; scoop by the owner within the radius pays exactly once (Cash + CollectorCash sum constant), a second player on the lawn scoops nothing; the Magnet radius; leave + rejoin -> the Welcome-back pile; offline pay into the pile with LastSeen; rebase rebuilds the ledger; prestige zeroes bank + piles and keeps the Garden at L1; LegacySlots honoured; resting keys above the open count do not eat; `GardenSet` any role, training refusal, timer churn (X5); attribute formats; no Instance per coin on the server; `CoinsScooped` fires; client: heaps follow `CoinPiles`, the zip and "+$" only for the owner and at the pile, others' piles dimmed, pools <= 40, nothing in the screen centre |
| `smoke_p4_portal.lua` | server (W2 tycoon) + client (W3 homefx) | tycoon, then homefx | GoHome sets `HomePortal`; walking in lands within 6 studs of SpawnCFrame; another player at the portal does not move; refused InBattle / InMatch / PortalLocked; expires after 10 s; cooldown; no home -> a free gate; `PortalArrived`; client: the ring drawn from the attribute and removed, the followers' dive |
| `smoke_p4_care.lua` (replaces `smoke_p2_care.lua`'s kitchen / gym / shutdown scenarios) | server (booted) | care (W2) | Food Machine: no machine refused before paying, price and XP per level, "Level up" batch priced per feed, leftovers first and free, cap refusal, refund on a failed XP write, `Fed` fires, `Cook` / `GymSet` answer the toast; Evolve at 19 / 20 / 49 / 50 x rarities, Common never stage 2, refusals (battle, provisional), stage stored, OpenPanel sent, a training pet may evolve; Training: start pays / unequips every copy / clears the Garden slot / remembers From, equip + GardenSet + Fusion refusals, team skip with the preset kept, finish after the time (mock clock) adds the rank and returns the pet (Follow / Garden / Free), offline finish on load, Stop refunds once, spots, rank cap 10, two-server completion = one rank, prestige keeps jobs, `Home.Gym` emptied once with a toast; fusion carry-over; `ClearSessions` |
| `smoke_p4_ring.lua` | server (booted) | battleservice (W2) | refusals in order (no home / no pet / far / in a match / provisional) with their texts; team -> equipped -> best owned fallback; a single level-1 pet wins round 1; chaining keeps InBattle and the pocket (no gap); rewards once per round; Cash = seconds of the climber's income with the floor; record x3 and boss Tokens once; `Ring.Best` max-merge, `Runs` delta; checkpoint start; the loss-XP gate; Forfeit in an intermission vs in a fight; leave / respawn / shutdown between and during rounds; the pocket freed; `RingBoard`; trial loss XP (>= 20 s or 20% damage, not forfeit) |
| `smoke_p4_pets_client.lua` | client + phone | pets (W3) | own follower card "Lv n" + XP fill = xp / xpToNext at 22 px with a stroke; another player's card shows the level from `EquippedInfo` only; cards hidden InBattle; >= 14 px on 390x844; pets behind the owner while walking (travel-direction offset <= +0.5 studs) and the 2-7 / < 12 / < 8 windows; evolved Low followers within `petEvoLow`; the 6-model cap for others; `PlayEvolution` parks and restores the follower; the portal dive |
| `smoke_p4_careui.lua` | client + phone | careui (W3) | CareController feed list (garden pets first, Feed / Level up prices from the catalog, leftovers line, EVOLVE button), the garden picker (`Action = "Garden"`), the training window (4 skills, rank bars, cost / time, Stop confirm), EvolutionFx on clones in the world, the Pets panel (Garden for any pet, "Coins $/s" pill, Lv n / 100, Equip disabled while training, evolution badge), the Home window (Garden card: coins waiting, coins/min, places N/12, the legacy lines, no Collect; new station names / effects; the prestige texts; Portal home sends `HomeAction "GoHome"` and closes), all at 1920x1080 / 1280x720 / 390x844 / 844x390 with nothing in the screen centre |
| `smoke_p4_ui.lua` | server (content + booted chapter flow) + client | ui (W3) | tutorial chapters 2 and 4 (index rule: chapter starts 10 / 15 / 19, ids, targets, texts 20-200 bytes, mid-chapter resume from indices 10-14 on a migrated save, a finished Phase 3 tutorial resuming into chapter 4, the 300-token reward once, skipped players never see it), NPC tips (lengths, needles from the catalogs), the ring window (record, start picker, refusal texts), the safe-zone toast |
| `smoke_p4_flow.lua` | server + client | flow (W4) | end-to-end with 3-6 players: a new player (claim -> free Garden -> place a pet -> coins -> Food Machine -> feed -> ring rounds 1-3 with one level-1 pet -> `/petlevel 20` + EVOLVE -> train (lock, auto-return) -> prestige with garden place 4 and the Garden still built); a migrated Phase 3 save (presses + Collector Cash + leftover Feasts + Gym pets + a 6-pet Garden L6: Home Level and tier unchanged, plants built, the Welcome-back pile, LegacySlots, Gym pets back, leftovers fed, Ready to evolve); a veteran resuming chapter 4; a leave / rejoin mid-training and mid-run; the two-server merge |

#### 8.2 Existing tests that change (the old pins on the money machines, the kitchen and the gym)

| File | Owner (wave) | Change |
|---|---|---|
| `smoke_p2_economy.lua` | economy (W1) | rewritten as `smoke_p4_economy.lua` (scenario name kept so smoke.py's anchors hold); the 18 ids stay, "free Press 1 first" (:459) becomes "free Garden first", income / cap / food / layout blocks (:549-623, :681-771) follow 8.1 |
| `smoke_p2_tycoon.lua` | tycoon (W2) | p2tycoon_progress: Station_Press1 / Collector / CollectorCash fill / Collect prompt / CollectPad (:466-572) -> Garden free pad, plants built with Level, coins, scoop; the greedy buy to prestige stays; prestige keeps the Garden at L1 and adds a place; p2tycoon_exploits (:875) "Combat refused" -> "Combat earns 1/1.6", (:890) Gym refusal -> training refusal; p2tycoon_claim GoHome (:379-407) -> the portal (walk in, then within 6 studs); p2tycoon_offline -> the Welcome-back pile |
| `smoke_economy.lua` | tycoon (W2) | GoToSpot (:591-636) -> a portal toward a free gate + an InBattle refusal; the tutorial "press" (:381, :389) -> "garden" |
| `smoke_p2_homeworld.lua` | homeworld (W2 server half), homefx (W3 client half) | per-station budgets (Plant 45, Magnet 55, Garden 85, FoodMachine 55, Training 90); "presses never shrink" -> plants grow; Conveyor (:556-561) and Collector (:585-603) checks deleted; `Station_Press1` is a Berry Bush; Garden `Spot1..12` + `GardenSpotPrompt`; `FeedPrompt` on the Hopper; `TrainPrompt`; plot <= 950; the server never moves a part (:705-716) extended to "no Instance per coin"; client (:940-960): press puffs + belt -> coin heaps, eating rhythm, fruit, props, cards |
| `smoke_p2_visual.lua`, `smoke_p2_fix_client.lua` | homeworld (W2) / homefx (W3) | plants, Magnet, Food Machine, Training Place renders; 12 garden + 5 training pets under the per-frame build budget (17 pets, pool) |
| `smoke_p2_care.lua` | lead (W0: caps -> 50 in p2care_stats :412-429, :820-860), then care (W2) | p2care_kitchen / p2care_gym / p2care_shutdown deleted; p2care_feed / p2care_exploits moved into `smoke_p4_care.lua`; p2care_stats keeps GetStats (caps 50, the Economy / Combat Income ratio check moves to `PetPower`) |
| `smoke.py` | lead | the p2care line becomes `["p2care_stats"]` + the p4care scenarios; the `"p2care_kitchen" if ... else "shutdown"` anchors (:378-398) fall back to "shutdown" by themselves; new files registered |
| `smoke_fix_server.lua` | care (W2) | `fixsrv_kitchen_prestige` (:278-312) -> "prestige keeps training jobs, clears the coin piles, keeps the Garden at L1"; the other three unchanged |
| `smoke_fix_leave.lua` | battleservice (W2) | `fixleave_refund` -> `fixleave_ring`: the leave-time write is now `Ring.Runs + 1` (and `Best`) written by BattleService's PlayerRemoving handler (:3176-3183) after DataService's deferred leave save was scheduled; same assertions (in the leave save itself; with an outage, through the orphan retry); `fixleave_rejoin` likewise |
| `smoke_p2_fusion.lua` | care (W2) | no Gym placement of a fused result; training inputs refused; growth carried |
| `smoke_p2_data.lua`, `smoke_p3_data.lua`, `smoke_polish_data.lua`, `smoke_dev.lua` | data (W1) | new fields (sanitize, defaults, merges, provisional, snapshot); the busy checks (p3data :285-290, :351-363): a garden pet now joins teams and is not pruned, the Gym cases become `TrainingKeys` (read-time skip, preset kept); forward compatibility: a Phase 3 fixture keeps the new fields; reset wipes PetGrowth / Ring; `/petlevel` |
| `smoke_p2_ui.lua` | careui (W3) | chapter-2 ids (:77-80) `claim,garden,coins,machine,feed`, checks (:113-118), known CompleteOn (:84-86 + GardenPlaced, CoinsScooped, TrainingStarted, RingWon, PortalUsed), NPC needles (:147-153: Food Machine, Feed, EVOLVE, Training Place, Champion Ring, Pet Garden, rainbow coins), Home window rows (Station_Press1 upgrade still sends `Upgrade Press1`; Station_Press4 "Needs"; no Collect), Pets panel actions, FeedPicker -> the CareController list |
| `smoke_p3_ui.lua` | ui (W3) | chapter-3 loops (:91 / :101 / :129) stop at `ChapterStart[4] - 1`; p3ui_tutorial end step (:307) = `ChapterStart[4]`; NPC needles (:179: Training Place, Food Machine; the kept coach_corgi "Trial Portal", granny_owl "Gems", professor_axolotl "Fusion Machine" / "Storm Altar") |
| `smoke_p3_flow.lua` | battleservice (W2), then flow (W4) | a lost trial >= 20 s now gives 1/3 XP (:1488); GymSet (:1533-1539) -> Train (skipped, preset kept); Cy's garden pet may join his team (:22, :384, :1357); the migrated save (:1107 / :1263) keeps `Press1 = 2` as a Berry Bush |
| `smoke_p3_battlecore.lua`, `sim_battle.lua` | battlecore (W1) | Modes + "Ring", Zones / TimeLimits, `ChampionTeam` monotonic with no ceiling (Boost > 1 from about round 45), `UnitStats` extras, Defense in `applyDamage`, `MeterRate`; the trial numbers (:206-223) unchanged |
| `smoke_p3_battleservice.lua`, `smoke_p3_fix_server.lua`, `smoke_p3_fixcheck.lua` | battleservice (W2) | trial loss XP; teamOf extras and the ring fallback; Mode names; `KeysInBattle`; GoHome refused InBattle |
| `smoke_p3_arenaworld.lua` | arenaworld (W2) | arena <= 2500 WITH Portal_Ring; `RingPrompt` + `OpenPanel = "Ring"`; a Ring pocket 100..250 parts with a Ring-mode zone; `ZoneAt`; the Arena Gate sample (:699) unchanged |
| `smoke_client_v2.lua`, `smoke_release_client.lua`, `smoke_polish_worldtext.lua` | pets (W3) | follower labels (:1792 / :1805 / :1819 / :1858) "beside" -> "behind" + the walking check; cards; `EquippedInfo`; evolved follower budgets; 6 players x 3 pets with cards: one root write per pet unchanged; the card's "Lv" >= 22 px with a stroke, the portal name tag, the "+$" scoop pop |
| `smoke_p3_battleclient.lua`, `smoke_p3_fix_client.lua`, `smoke_p3_visual.lua` | battleclient (W3) | unit card rows (own: HP + SPECIAL + level + XP; enemy: HP + level; fills only on change); ring HUD texts; the next-round side card; the result card's Cash / Rounds / Record lines; End -> Start in one pocket |
| `smoke_p2_final.lua` | docs (W4) | README numbers: station table, Food Machine, Training Place, Garden (places, Economy x1.6, Lucky), Vault, Prestige (x1.5 prices, +1 place), the ring table, evolution, pet cards, chapter 2 / 4, NPC table; a `checkPhase4` beside `checkPhase3` |
| `smoke_p2_flow.lua` | flow (W4) | rewritten as the Phase 4 home flow (it walks presses, Collector, Kitchen, Gym today) |
| `tools/dump_gui.lua`, `tools/render_gui.py` | careui (W3) | scenarios `home[:coins]`, `feed`, `garden`, `train`, `ring[:view]`, `petcards`; the `menu` scenario gains Action / Key args; `tutorialPayload` passes `Chapter` |
| `tools/dump_model.lua`, `tools/render_model.py` | homeworld (W2) | `home:Press1:5` draws the Berry Bush (and the other plants, Magnet, Food Machine, Training Place), `homegarden` with 12 places + piles, `pocket:ring`, `portal:home` |

#### 8.3 Sims (`python3`, `lupa`)
* `tools/sim_tycoon.py` (economy, W1) becomes the port of `synth/sim_synth.py` (constants block by id, the coin model, feeding by share, prices x1.5^stars,
  the Garden kept at L1, `--ring 0.08`). TARGETS (Monte Carlo 120, 3 runs; the sim must print ALL TARGETS MET): first paid purchase <= 60 s; early mean gap
  0.5-3 min and p90 <= 3 min; Villa 25-40 min; first prestige 2-3 h; later prestiges faster; every run of the first 10 >= 12 min; prestige Gems <= 135/h on
  runs 2-10; dead time <= 6 min (a Combat-only player included); a Combat-only player prestiges <= 240 min; first EVOLVE 40-100 min; an active player never
  fills a pile (>= 10x the scoop gap); offline <= 2 h of income. `--check` compares the effect tables (Food, Lucky, Radius / PileSeconds, FeedShare, Slots,
  Vault) and `AvailablePads` parity incl. `PriceAt` with stars. `--migrate` (the port of `synth/veteran_check.py` against the frozen
  `tools/fixtures/sim_tycoon_phase3.py`): 300 old homes: Home Level unchanged in 300 / 300, no dead end, the income and pad-time ratios printed by tier and
  stars (gate: median pad-time ratio <= 1.0 for every tier / star bucket), the count of homes with no garden pet.
* `tools/sim_battle.lua` (battlecore, W1): new sections `training` (all four skills rank 5 x1.25-1.4 team power, rank 10 x1.6-1.85; Evolved x1.25 / x1.5;
  trained mirror duels 35-65% with no draws or timeouts; a trained team vs a raid still 100-240 s with dodging players), `ring` (rounds 1-3 won >= 95% by
  EVERY single level-1 rollable Common / Uncommon; the single-pet average >= 85% at rounds 4-5 and >= 50% at round 8; median stage records S1 13-19, S3 20-26,
  S5 25-31, S7 33-39, S9 41-47, S10 48-54; the record never falls with the stage; fights 4-40 s; power monotonic to round 120; Boost > 1 from round 40-50),
  `progression` (:1130-1145) switches from the Feast to the Food Machine price. `SIM.Stages` unchanged. `p3battle_balance` runs a short subset.
* Each wave's gate: `python3 tools/syntax.py`, `node tools/check.mjs`, `bash tools/run_checks.sh --quick` with the wave's scenarios green; the lead keeps a
  "known red until wave N" list that only shrinks; the release gate is the full `bash tools/run_checks.sh` plus `--smoke --strict`, the Rojo 7.7.1 rebuild and
  `tools/verify_place.py`.

### 9. Tutorial chapter 2 (rewritten in place), chapter 4 (appended) and the NPC tips

Saved progress is the step INDEX (`Profile.Tutorial.Step`, TutorialSteps.lua:5-9), so chapter 2 keeps EXACTLY five steps at indices 10-14 with the
ChapterEnd at 14, chapter 3 stays at 15-18, and chapter 4 is APPENDED at 19-21. Finished players (stored Step 19 = old #Steps + 1) resume at chapter 4 by
the existing "a Done tutorial whose Step points into a later chapter carries on" rule (`resumable` :314); skipped players (1000) never see it; no chapter
reward can be paid twice because no index moves. Every new step passes at once (`satisfied()`) for a player who already has what it asks for, and no step
waits on a removed mechanic ("Collected" stays in `KNOWN_COMPLETE_ON` but is no longer used).

| # | Id (old -> new) | Title | Nimbus says (97-125 bytes) | Target | CompleteOn (satisfied at once when) |
|---|---|---|---|---|---|
| 10 | claim | Claim Your Home | unchanged | `{Kind="Spot", Gate=true}` | Claimed |
| 11 | press -> **garden** | Your Pet Garden | "Your pets make the money! Build your free Pet Garden, then press E on a garden spot to put a pet in it." | `{Kind="Spot", Pad="Garden", Station="Garden", GardenSpot=true, Label="Pet Garden"}` (the pad until built, then the first empty open place) | **GardenPlaced** (a pet sits in an open place) |
| 12 | collect -> **coins** | Rainbow Coins! | "Garden pets eat and pop out rainbow coins. Only you can scoop yours: just walk over them!" | `{Kind="Spot", Station="Garden", Coins=true, Label="Your coins"}` (the fullest pile from `CoinPiles`) | **CoinsScooped** (event; a mid-chapter veteran with `Kitchen >= 1` passes at once) |
| 13 | kitchen -> **machine** | The Food Machine | "Spend coins on the glowing pads: plants make bigger coins! Follow my arrow and build the Food Machine." | `{Kind="Spot", Pad="Kitchen", Path=true, Label="Food Machine pad"}` | Built, Station "Kitchen" (`Kitchen >= 1`) |
| 14 | feed (kept, ChapterEnd, +$1,000 once) | Snack Time! | "Press E at the Food Machine, pick a pet and press Feed. Fed pets level up, and at level 20 they EVOLVE!" | `{Kind="Spot", Station="Kitchen", Food=true, Label="Food Machine"}` | Fed (unchanged signal) |
| 19 | **train** (new, chapter 4) | Training Time | "Your Training Place makes pets stronger: pick a pet and a skill. Training pets rest at home until they're done!" | `{Kind="Spot", Pad="Gym", Station="Gym", Path=true, Label="Training Place"}` | **TrainingStarted** (any Job or any rank in PetGrowth) |
| 20 | **ring** (new) | The Champion Ring | "Claim your home, then press E at the Champion Ring portal on the plaza. Beat the champion: Cash and XP!" | `{Kind="Arena", Place="Ring", Label="Champion Ring"}` -> `ArenaInfo.RingPortal` | **RingWon** (`Ring.Best >= 1`, or a Ring win in `BattleEnded`) |
| 21 | **portal** (new, ChapterEnd, +300 Tokens once) | Portal Home | "Tap Home, then Go home: a magic portal opens just for you and your pets. Hop in!" | `{Kind="Menu", Id="Home"}` | **PortalUsed** (event) |

* Chapter 1 "equip" text (TutorialSteps.lua:132, in place): "... equip your buddy so it follows right behind you ..." (was "flies right beside you"). The
  trial step text (:246) becomes "... SPECIAL when its gold bar is full!".
* TutorialService (ui engineer; constants are lead-listed here): `KNOWN_COMPLETE_ON` (:112-131) + GardenPlaced, CoinsScooped, TrainingStarted, RingWon,
  PortalUsed; `buildSteps` (:263-306) copies the target flags `GardenSpot`, `Coins`; `resolveStep` (:982) and `refreshTarget` (:1356) route Spot targets with
  them to `homeTarget` (:714-786), which gains: GardenSpot -> no pet owned: the Shop ("Spin a roulette for a pet"); Garden not built: the free pad; else the
  first empty open place ("Press E on a garden spot") or the Pets menu; Coins -> the fullest pile ("Walk over your rainbow coins"); Food -> the machine
  ("Press E at the Food Machine, then Feed") else the pad path. The Collector hints (:756, :778), `stationPosition`'s CollectPad lookup (:622-636),
  `checkCollected` (:1333-1349), `collectorCash` (:424-430), the CashSeen baselines (:1149-1150), the poll branch (:1644-1649) and the `Cooked` nudge
  (:1790-1794) go. Signals hooked in `Init` (:1764-1795): `TycoonService.CoinsScooped`, `TycoonService.PortalUsed`, `PetCareService.TrainingStarted`,
  `BattleService.BattleEnded` (Mode "Ring", Won). `impossible()` (:1225-1251): GardenPlaced / CoinsScooped need `TycoonService.GardenSet` + homes;
  TrainingStarted needs `PetCareService.Train`; RingWon needs `BattleService.StartRing`; PortalUsed needs `TycoonService.OpenHomePortal`.
  `payChapter` (:1108-1131): an explicit `chapter >= 4` branch FIRST: `RING_FINISH_TOKENS = 300` ("Pets tutorial complete! +300 Tokens"); `HOME_FINISH_CASH`
  1000 stays. `fieldablePets` / `teamFilled` (:870-891) keep using `FieldableKeys` (garden pets now count, so a one-pet kid whose pet sits in the Garden is
  never stalled at chapter 3's team step). Rollout: a Phase 3 player mid-chapter-2 continues at the same index with the new meaning; the tests resume from
  every index 10-21.
* TutorialController: no new client events (every new CompleteOn is server-observed); the pip count follows `Total`; a new Menu target id is not needed.
* NPC tips (`shared/NpcDialog.lua`; 3-5 lines per NPC, <= 125 bytes, no `< > &`; numbers read from the catalogs at load: `FeedShare[1]` 25%,
  `EvolutionBoost[1]` 25%, `Prestige.GardenSlotsBase` 3, `RoleMult.Economy` 60%, `Prestige.GemReward` 100). Helpers `foodLine` / `gymNumbers`
  (:296-323) become `feedLine` / `trainLine`; `gymLow / High / Slots` (:378) go. Keep the p3ui needles (coach_corgi "Trial Portal", "30 levels", "Team",
  "+20 trophies"; granny_owl "Gems"; professor_axolotl "Fusion Machine", "Storm Altar").
  * Mayor Panda (keywords: free gate, press E, Pet Garden, rainbow coins, Berry Bush, Economy pets, Home Level, Prestige, portal): 1 unchanged (claim a
    home). 2 "Your pets eat in your Pet Garden and pop out rainbow coins. Only you can scoop yours: just walk over them!" 3 "Grow a Berry Bush, a Carrot Patch
    and more: tastier food makes bigger coins. Economy pets make 60% more!" 4 "Home Level 40 and a Sky Castle? Prestige! You get x1.25 coins forever, 100 Gems
    and one more garden place." 5 "Tap Home in the menu to see your stations. Go home opens a magic portal just for you and your pets!"
  * Granny Owl (keywords: roulette, shop island, Mythic, Pet Index, Gems, Food Machine, Feed, EVOLVE): 1-3 unchanged. 4 "Hungry pets grow! Press E at your
    Food Machine, pick a pet and press Feed: each feed fills 25% of its XP bar." 5 "At level 20 a pet glows gold: press EVOLVE and watch it change! Epic and
    rarer pets evolve again at 50."
  * Coach Corgi (keywords: yours to keep, Trial Portal, Training Place, Champion Ring, record, Team, trophies): 1, 2, 5 unchanged. 3 "Your Training Place makes
    pets tougher: train Attack Speed, Physique, Ability or Defense. They rest at home while they train!" 4 "Try the Champion Ring on the plaza: one champion
    after another, each stronger. Beat your record for triple Cash!"
  * Captain Penguin: line 5 becomes "Outside the Battle Arena and the battle rings it's a safe zone: no pet battles. In the arena, RETREAT out of glowing circles!"
  * Sparky Fox and Professor Axolotl: unchanged.

### 10. Ownership (parallel build engineers) and the ordered build plan

Rule: one owner per file at a time. A file that changes owner between waves is listed under both, with the wave. "Fable" for the riskiest pieces
(save data and merges, the coin ledger, the battle lifecycle, care money and timers), "Opus" elsewhere (the player's rule). Engineers never edit
`ARCHITECTURE_V3.md`, `Config.lua`, `PetCatalog.lua`, `Main.*.lua`, `tools/contract.json` or `tools/run_checks.sh`: they hand contract questions to
the lead (as deviations in their report). In `tools/smoke.py` each engineer edits only the registration lines of the test files they own (re-read
the file right before each small edit: others edit their own lines in the same wave). Every new helper goes into the file's helper table
(section 6); every new window into `CareController`.

#### 10.1 Ownership table

| Role | Model | Wave | Source files (exclusive) | Test / tool files (exclusive in that wave) |
|---|---|---|---|---|
| lead | - | 0, gates, 5 | `ARCHITECTURE_V3.md` (this contract), `src/shared/Config.lua` (Attr `EquippedInfo` / `HomePortal` / `PortalArrived`, Remotes comments), `src/shared/PetCatalog.lua` (caps 50, `EvolutionLevels / EvolutionBoost / RoleMult / MaxEvolution / EvolutionStage / CanEvolve`, header text), `src/server/Main.server.lua` (deps), `src/client/Main.client.lua` (`CareController`, `HomePortalFx` OPTIONAL) | `tools/smoke.py`, `tools/contract.json`, `tools/check.mjs` (new names), `tools/fixtures/DataService_phase3.lua` + `tools/fixtures/sim_tycoon_phase3.py` (frozen byte copies, excluded from the game-code scans), `smoke_p2_care.lua` (W0 only: caps -> 50), `tools/run_checks.sh` |
| data | Fable | 1 | `src/server/Services/DataService.lua`, `src/client/State.lua`, `src/server/Services/DevService.lua` | `smoke_p4_data.lua` (new), `smoke_p3_data.lua`, `smoke_p2_data.lua`, `smoke_dev.lua`, `smoke_polish_data.lua` |
| economy | Opus | 1 | `src/shared/TycoonCatalog.lua` | `smoke_p4_economy.lua` (new, replaces `smoke_p2_economy.lua`), `tools/sim_tycoon.py` |
| battlecore | Opus | 1 | `src/shared/BattleCatalog.lua`, `src/shared/BattleSim.lua` | `smoke_p3_battlecore.lua`, `tools/sim_battle.lua` |
| tycoon | Fable | 2 | `src/server/Services/TycoonService.lua`, `src/server/Services/SpotService.lua` | `smoke_p4_garden.lua` + `smoke_p4_portal.lua` (new, server halves), `smoke_p2_tycoon.lua`, `smoke_economy.lua` |
| care | Fable | 2 | `src/server/Services/PetCareService.lua`, `src/server/Services/PetService.lua`, `src/server/Services/FusionService.lua` | `smoke_p4_care.lua` (new), `smoke_p2_care.lua` (W2), `smoke_p2_fusion.lua`, `smoke_fix_server.lua` |
| battleservice | Fable | 2 | `src/server/Services/BattleService.lua` | `smoke_p4_ring.lua` (new), `smoke_p3_battleservice.lua`, `smoke_p3_fix_server.lua`, `smoke_p3_fixcheck.lua`, `smoke_p3_events.lua`, `smoke_fix_leave.lua`, `smoke_p3_flow.lua` (W2) |
| homeworld | Opus | 2 | `src/server/Services/HomeBuilder.lua` | `smoke_p2_homeworld.lua` + `smoke_p2_visual.lua` (W2 server halves), `tools/dump_model.lua`, `tools/render_model.py` |
| arenaworld | Opus | 2 | `src/server/Services/ArenaBuilder.lua`, `src/server/Services/LobbyBuilder.lua` | `smoke_p3_arenaworld.lua`, `smoke_p3_visual.lua` (W2 arena half), `smoke_polish_portals.lua` |
| pets | Opus | 2 (PetCard, PetController) | `src/client/UI/PetCard.lua` (new), `src/client/Controllers/PetController.lua` | `smoke_p4_pets_client.lua` (new), `smoke_client_v2.lua`, `smoke_release_client.lua`, `smoke_polish_worldtext.lua` |
| homefx | Opus | 3 | `src/client/Controllers/HomeFx.lua`, `src/client/Controllers/HomePortalFx.lua` (new) | client halves of `smoke_p4_garden.lua`, `smoke_p4_portal.lua`, `smoke_p2_homeworld.lua`, `smoke_p2_visual.lua` (W3), `smoke_p2_fix_client.lua` |
| battleclient | Opus | 3 | `src/client/Controllers/BattleController.lua` | `smoke_p3_battleclient.lua`, `smoke_p3_fix_client.lua`, `smoke_p3_visual.lua` (W3 client half) |
| careui | Opus | 3 | `src/client/Controllers/CareController.lua` (new), `src/client/Controllers/MenuController.lua`, `src/client/Controllers/EvolutionFx.lua`, `src/client/UI/CloudUI.lua` (`PetViewport` Evolved option only) | `smoke_p4_careui.lua` (new), `smoke_p2_ui.lua`, `smoke_p3_evolved.lua` (EvolutionFx checks), `tools/dump_gui.lua`, `tools/render_gui.py` |
| ui | Opus | 3 | `src/client/Controllers/ArenaController.lua`, `src/server/Services/TutorialService.lua`, `src/shared/TutorialSteps.lua`, `src/client/Controllers/TutorialController.lua`, `src/shared/NpcDialog.lua` | `smoke_p4_ui.lua` (new), `smoke_p3_ui.lua` |
| docs | Opus | 4 | `README.md`, `tools/README.md` | `smoke_p2_final.lua` |
| flow | Opus | 4 | (none: reports cross-module bugs to the lead, who reopens the owner) | `smoke_p4_flow.lua` (new), `smoke_p2_flow.lua`, `smoke_p3_flow.lua` (W4) |

Untouched on purpose: `HudController.lua` (155 locals, the HUD is full; the safe-zone toast is a side toast), `NotifyController.lua`, `PetBuilder.lua`
(every evolved form exists; stages pass through `opts.Evolved`), `Voxel.lua`, `BossBuilder.lua`, `EventService.lua` (verify it keeps ignoring non-Raid
results), `PlayerService.lua`, `DamageService.lua`, `PortalService.lua`, `MatchService.lua`, `GemService.lua`, `IndexService.lua`, `ItemService.lua`,
`NpcService.lua`, `TokenService.lua`.

Interfaces each pair codes against (all fixed in this document): economy <-> everyone (TycoonCatalog API, 5.4); battlecore <-> battleservice /
battleclient (`Ring`, `ChampionTeam`, entry fields, `unitInfo`); data <-> care / tycoon / battleservice (field names, `MutateGrowth`, `TrainingKeys`,
`MutateRing`, `KeysInBattle`, `AddCash`); homeworld <-> tycoon / care (prompt names + attributes, `SetGarden(spot, valid, open)`, the Hopper part);
arenaworld <-> battleservice (`BuildPocket(index, "Ring")`, `ArenaInfo.RingPortal`, `RingBoard`); pets <-> homefx / battleclient (`PetCard` API);
careui / ui <-> care / tycoon / battleservice (remote actions, OpenPanel args, the signals the tutorial listens to).

#### 10.2 The ordered build plan

**Wave 0 - lead, contract freeze (nothing else runs; the two open choices of section 11 are settled). DONE: baseline = the Phase 3 release run
(7254 smoke checks pass, 0 fail; main 35800c0 has the same tree as 3878ba2), fixtures frozen, this contract pasted, the shared edits below landed.**
1. Baseline: `bash tools/run_checks.sh --quick` on the Phase 4 branch (green), keep the log.
2. Freeze `tools/fixtures/DataService_phase3.lua` and `tools/fixtures/sim_tycoon_phase3.py` (byte copies).
3. Paste this contract into ARCHITECTURE_V3.md as "Phase 4" + "Phase 4 build contract"; add a one-line note to the Phase 2 contract (presses -> plants).
4. Shared edits: `Config.Attr` + Remotes comments; `PetCatalog` caps 50 + evolution / role data and helpers (+ the p2care_stats cap expectations);
   `Main.server.lua` deps; `Main.client.lua` controller list; `contract.json` (`petEvoLow` 380, `petEvo2Low` 520, the new public names).
5. Gate: syntax + check.mjs + quick smoke green.

**Wave 1 - foundations (3 in parallel): data (Fable), economy, battlecore.** Pure modules with the APIs every later wave calls. Gate: their scenarios +
both sims on target (`python3 tools/sim_tycoon.py` ALL TARGETS MET and `--check` and `--migrate`; `sim_battle` quick: trials unchanged, `training`, `ring`).
Known red until wave 2: the booted home scenarios that read the new catalog (p2tycoon_*, p2home_*, p2visual_*, p2flow_*, p2ui_tutorial, the home parts of
p3flow_*); TycoonCatalog keeps the `PetIncome` / `CollectorCap` / `GymSlots` aliases for one release so the Phase 3 services still boot during wave 1.

**Wave 2 - services, worlds and the pet client (6 in parallel): tycoon (Fable), care (Fable), battleservice (Fable), homeworld, arenaworld, pets.**
Each builds against wave 1's real modules and the contract's hooks (`HomeBuilder.SetGarden(spot, valid, open)`; `ArenaBuilder.BuildPocket(index, "Ring")`,
which BattleService calls in a pcall with the trial pocket as fallback; `PetCard` for wave 3). Gate: every server scenario green except the flows (p2flow /
p3flow wait for wave 4) and the UI tutorial flows (wave 3); `render_model.py` iterations (>= 3) for the plants L1 / L5 / L10, the Magnet, the Food Machine
L1-5, the Training Place L1-5, the garden with 12 pets, Portal_Ring, the ring pocket; the plot budget measured.

**Wave 3 - clients and UI (4 in parallel): homefx, battleclient, careui, ui.** Gate: every client and phone scenario green; render audit
(`dump_gui.lua` + `render_gui.py` at 1920x1080 / 1280x720 / 390x844 / 844x390 for the feed list, the garden picker, the training window, EVOLVE, the Home
window's Garden card, the ring window, the pet cards, the next-round card), at least three iterations each; nothing in the screen centre.

**Wave 4 - docs and flows (2 in parallel), then the lead.** docs rewrites the README (the section-2 bullets, the station table, "Homes from before Phase
4", the ring, training, evolution, controls, the tutorial, the dev commands incl. `/petlevel`, "Publish, then Migrate to Latest Update") and its checks;
flow writes `smoke_p4_flow.lua` and repairs the two old flows; bugs they find go back to the file's owner (a short fix wave). Lead: full
`bash tools/run_checks.sh`, `--smoke --strict`, Rojo 7.7.1 rebuild of `play/NimbusClimb.rbxlx`, `tools/verify_place.py`.

**Wave 5 - review and fix.** Independent reviewers by lens: save data and merges (incl. the rollout table and the fixture test), money paid exactly once
(coins, feed, training refund, ring, record bonus), battle lifecycle (ring chaining, every end path, InBattle gaps, the loss-XP gate), economy numbers
(sim vs catalog vs README), client budgets and readability (cards, coins, portal, phone sizes, screen centre), tutorial / NPC / README accuracy. Fixes go
to the owner in the table; the release gate is re-run.

Critical path: W0 -> data (W1) -> tycoon / care / battleservice (W2) -> careui / ui (W3) -> flow (W4). The worlds (homeworld, arenaworld), pets and the
pure clients (battleclient, homefx) have slack.

### 11. Open risks, the two questions for the player, and where each judge must-fix landed

**The two choices the player's words left open (settled by the lead before Wave 0; the player may still change them):**
1. "Common, Uncommon and Rare pets stop at their first evolution (level 20)" is read as "they evolve ONCE", and only Epic and rarer pets evolve a
   second time at 50. The player then confirmed it and raised the cap: **"make the max level for all pets at level 100 (evolutions stay the same) but
   obviously it becomes harder from a level to another (xp required)"**: every pet levels up to 100, the XP curve keeps rising (see the player update
   at the top of this contract).
2. **The four Cloud Presses become food plants** on the same pads (Berry Bush, Carrot Patch, Cloud Melons, Starfruit Tree) and the Collector the Coin
   Magnet. This is the player's own picture ("pets eating from the garden they're working on"): the plants are what the pets eat, and the pets make ALL
   the money (no pet in the garden = no coins; better plants = bigger coins). It keeps every player's Home Level, house and prestige exactly as they are.
   The documented fallback if the player ever wants no plants at all: the integration design's `LegacyStations` (presses hidden, counted for Home
   Level until the next Prestige, +3% coins per old level) with its 13-station table: a different catalog, sim and migration.

| # | Risk | Mitigation |
|---|---|---|
| R1 | Real players pace differently from the model (prestige too fast or slow; feeding more or less than 25% of the coins) | every knob is data in TycoonCatalog (plants, Lucky, FeedShare / FeedBase, Prestige.PriceStep, Training); the sim parity test keeps sim and game equal; a README "Tuning" table for the owner; the sim's `--ring` and feed-share knobs show the sensitivity (a heavy feeder shortens later runs: the compounding price step absorbs it) |
| R2 | Coin ledger exactly-once across rejoins, rebases and outages | one persisted number (`CollectorCash`) with its existing delta merge; piles are session memory rebuilt as the Welcome-back pile; pickups clamped to the bank; tests for rejoin / rebase / outage / prestige |
| R3 | Ring chaining: InBattle swaps, pocket reuse, client End vs the next Start, shutdown between rounds, a missed mode branch forfeiting climbers after 1 s or leaking pockets | reuse the trial machinery; an explicit run state; the next InBattle id written before the old one is released; client cleanup keyed by battle id; one test per end path and per mode branch (3.8 lists them) |
| R4 | Lua's 200-local limit (MenuController 184, ArenaBuilder 180) | helper tables; new windows in CareController; engineers re-run the locals count before handing in |
| R5 | A missed path lets a training pet fight / follow / fuse / work | one `TrainingKeys` source, one test per path (X10) |
| R6 | Veterans at the Cottage tier see fewer coins per second than their presses made | their pads are cheaper (time to the next pad x0.8); the Home window's Garden card shows coins/min, places and "Put pets in your garden!"; the welcome toast; the Villa and above gain 1-4x |
| R7 | A veteran with NO pet in the garden earns nothing until they place one (37 of 300 homes) | the welcome toast and the Home window say it; the free Garden pad glows; the Pets panel's "Garden" button works for every pet |
| R8 | "My garden got smaller" after a veteran's next Prestige (LegacySlots end) | that Prestige adds a place; resting pets keep their place and show "Resting (garden full)"; the prestige confirmation says it |
| R9 | Trained / evolved teams stomp untrained ones in duels | training capped at x1.73 (rank 10, all skills), Defense <= 30%, trophy matchmaking and the existing practice rule for big power gaps (`DUEL_POWER_GAP`) |
| R10 | Evolved follower models cost parts in crowded servers | own evolved at Low; others' evolved only within 40 studs and at most 6; home pets never evolved models |
| R11 | Tutorial index meaning changes for players in the middle of chapter 2 | same chapter, same count; every step completes from the current state; tests resume from indices 10-21 |
| R12 | Plot part budget is tight (911 -> ~900-925 of 950) | bowls, fruit, props, heaps, coins are client parts; per-station caps; trim decor details first; the homeworld engineer measures each level |
| R13 | Home portal geometry (no floor, inside a wall, a slope) | server raycasts with fallbacks to the character's own spot; only the owner walking in teleports |
| R14 | Leftover Feasts give veterans a burst of free XP at launch | bounded by their stock (food they already paid for) |
| R15 | Phase 3's "a garden pet cannot fight" rule is dropped | one function (`P3.placedCopies`); the affected tests are listed in 8.2; the README says it in one line |
| R16 | A kid who climbs the ring all day earns up to ~50% more than the garden alone and leaves it at 136 Gems/h at Prestige 5 | bounded by construction (seconds of own income, 9 s cap per round); Phase 3 itself ran 100-133 Gems/h; if the owner wants fewer Gems, `Prestige.GemRewardStep` is one number |
| R17 | Sounds for the scoop "ding" | engine sounds (`rbxasset://sounds/...`) only if the project allows them; otherwise the scoop stays visual |
| R18 | Test churn: Phase 2 / 3 tests pin presses, Collector, Kitchen cooking and Gym XP in many files | the station ids, remote names, `ChapterStart[2] == 10` and the chapter-3 ids are kept to limit it; 8.2 lists every file and owner |
| R19 | Rollout window (Phase 3 servers alive for minutes): a Phase 3 prestige keeps LegacySlots / LegacyPrices; a Phase 3 server may equip a training pet or fill 8 garden slots | temporary and harmless (4.4); "Publish, then Migrate to Latest Update" in the README |

**Where the judges' must-fixes landed:** the ring's home + pet checks, refusal texts, team -> equipped fallback and single-pet rounds 1-3 (3.8, proved);
the rung-4 cliff (3.8: 94 / 98 / 85 / 76 / 60% at rounds 4-8); the record stored outside `Battle` (`Ring` top level, 4.1); the record bonus bounded (x3 of
a bounded Cash, boss Tokens once); ring Cash never outpacing the garden (seconds of own income, 3.8); the training lock as a read-time filter, never
`P3.prune` (3.7, 4.1); training capped near x1.7 (3.7); the Food Machine without a stock, priced per feed at the level eaten (3.4, X7); the EVOLVE
animation in the world, not a ViewportFrame (3.6); the 12 garden places pinned on a grid with coin points, walks and prompts that do not pop up on the
walks (3.3); the "+$" pop at the pile (section 6); the Garden kept through Prestige (3.1); veterans exempt from the star price for one run and their
pacing measured (3.12, 4.3); a gentler, compounding price curve that keeps every run >= 20 min and Gems at Phase 3's level (3.12); LegacySlots instead of
compaction or forever-slots (3.2, 4.3); garden places growing to 12 (3.2); the pet-card level text at 22 px (3.9); training auto-remove / auto-return /
refund and evolve allowed while training (3.7, 3.6); the arena cap kept at 2500 (3.8); the `PetCare("Feed")` payload packed in a table (5.1); evolved
heights measured by the client (3.6); the sim knobs baked into the design and the sim (3.12); the economy's NPC trial teams left unevolved (3.6); the Battle
field, forfeit XP farming (X15) and the coin-attribute bandwidth (`CoinPiles` stages, 5.3) fixed; old `Home.Gym` pets freed on load with a toast (3.7).

### Appendix: the prototypes behind the numbers (throwaway, in the lead's scratchpad `p4design/synth/`; the engineers get the path)

| Script | Run | What it proves |
|---|---|---|
| `sim_synth.py` | `python3 sim_synth.py --mc 120` (defaults: compound x1.5 per star, FeedBase 2.0, feed share 25%) and `--ring 0.08` | 3.12: ALL TARGETS MET; outputs `econ_final.txt`, `econ_ring.txt` |
| `ring_proto.lua` | `cd nimbus-climb && FIRST=3.0 GROWTH=1.18 SEEDS=12 python3 -c "import lupa.luajit21 as L; r=L.LuaRuntime(); r.execute(open('<path>').read())"` | 3.8: rounds 1-3 24/24 for all 12 single level-1 pets; the single-pet slope; stage records 16 .. 51; the round table; output `ring_out.txt` |
| `veteran_check.py` | `python3 veteran_check.py 300` | 3.12 / 4.3: 300 Phase 3 homes migrated; Home Level unchanged; income and pad-time ratios; output `veteran_out.txt` |
| integration's `train_proto.lua`, `follow_proto.py`, `count_locals.py`, `npc_lines.py`, `tutorial_texts.py` (`scratchpad/p4design/integration/proto/`) | as documented there | the training multipliers (x1.33 / x1.73 / x2.5), the follow-behind filter numbers, the locals counts, the text lengths |
