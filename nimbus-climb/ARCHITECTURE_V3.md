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

## ART RULE (player, 2026-10-20; overrides ART DIRECTION below and "no asset ids"): Blender models only
* From now on **no Roblox-built models**: every new or reworked model (pets, enemies, bosses, NPCs, props, decor,
  buildings, portals) is made in **Blender** (scripts in `blender/`, exported as FBX) and used in game as a MeshPart.
* No Toolbox / Creator Store models. No new Part-built (voxel / block) models.
* Mesh asset ids live in Config; the uploaded FBX source stays in `blender/`.
* **Style (player, 2026-10-20):** NOT the more realistic Phase 5 look. Go back to the pre-Phase-5 style (Phase 4 release,
  commit 7aa0df2: bright, cute, colourful voxel / pixel look of "ART DIRECTION") but with **finer voxels, more detail, more
  aesthetic**. Blender models are detailed fine-voxel models (greedy-merged outer faces, 2-3 shades per colour region).
* **Portals / gates:** look like they did before Phase 5 (7aa0df2), just more detailed.

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
(close-up of the head). The sheet is uploaded as Image 101827417487186 = `Config.Art.StormfangImage` (branding/stormfang-art.png, transparent pixels recoloured dark blue; an ImageLabel needs an Image id, not a Decal id. The first upload, Decal 129423539279679, had a checkerboard baked in).

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
* Re-proved in wave 1 (`python3 tools/sim_tycoon.py`, pets growing to 100, the contract's numbers unchanged: ALL TARGETS MET, also with
  `--ring 0.08`; `--check` and `--migrate` OK): first paid pad 0:27; Villa median 30:27; first Prestige median 2:23:47 (p10 1:52, p90 2:51);
  2nd run 1:04, 3rd 0:57 (later runs on seed 3: 68, 62, 59, 43, 37, 37, 33, 28, 24 min); prestige Gems at most 84 per hour; first EVOLVE
  median 1:18; Food Machine road for a Common L1 -> 100: $9.6M at a level-1 machine, $4.8M at level 5. These replace the cap-50 pacing
  numbers of 3.12 (later runs are a little longer: levels past 50 cost more per coin gained).
* Level-ups are announced with ONE toast per XP grant (a feed, a fight, a "Level up" batch), never one toast per level: a big grant can
  now cross many levels at once (the client_replay GUI-size check pins it).

**Wave 1 decisions (landed; the lead accepted them, they are contract now):**
* Duels only (`BattleCatalog.Damage`): `Overtime = { Modes = {Duel}, At = 75, PerSecond = 0.15 }` (after 75 s every duel hit grows
  by 15% per second, BattleSim event `Overtime`), `MaxHit = { Modes = {Duel}, Share = 0.6 }` (no single hit takes more than 60% of a
  pet's max HP) and `DoubleKoByDamage = { Duel = true }` (both last pets fall in one step: the side that dealt more damage wins).
  Without them a fully trained Shield / Heal mirror never ends and an Evolved II level-100 Pounce one-shots. Trials, raids and the
  ring keep the Phase 3 rules. `ExpectedDps` counts Ability with `SpecialDpsShare = 0.3` (raid boss HP stays honest for trained
  teams; untrained it is the Phase 3 number).
* Champion Ring: every 10th round is ALWAYS the giant mini-boss champion; a round's goal is `max(target, previous round's power)`;
  Boost also scales the special. New BattleCatalog helpers: `RealLoss`, `LossXp`, `RingPower`, `RingTarget`, `RingSeconds`,
  `TrainingSkills`; `unitInfo.boss = true` marks a mini-boss pet (raid bosses keep their boss id string).
* Data: `Migrations.P4Veteran` (a migrated profile that had a home) and `P4Welcome` (TycoonService marks the welcome toast as shown,
  in any later session); a cleared training Job travels as `false` + `JobDone`, and a stored job of the same skill at a HIGHER rank
  survives a stale clear; `MutateGrowth` keeps an owned key's Evo / ranks even if fn deletes its entry; `MutateHome` clears
  `LegacySlots` / `LegacyPrices` itself when Prestige rises; extra API `MigratedNow`, `Migrated` (signal), `SetPetLevel`.
* Economy: `TycoonCatalog.Version = 4`; kinds renamed Press -> Plant, Collector -> Magnet, Kitchen -> FoodMachine, Gym -> Training (ids
  unchanged); extras `LuckyEV`, `CoinValue`, `HeapStage`, `XpForLevel`, `CheckPurchase`, `StationsAfterPrestige`; the Phase 3 compat
  aliases are deleted in wave 4.

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
* `TycoonCatalog.CoinPoint(slot)` (station frame): front row (x, 0, -4.4), middle row (x, 0, -2.6) (both on the front
  walk, two lines, each 2.6 studs from its own cushion so a pet's coins land next to it), back row (x, 0, +3.5). `Garden.Slot.WelcomePile` = plot-local (13.5, 0, 2.5): beside the entrance,
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

## Phase 5: the Big Sky Update (asked for by the player after the first real playtest of Phase 4; four designs, one synthesis)

Branch `v3-phase5`, cut from main after the Phase 4 release (Phases 1-4 shipped). Four area designs (battle, dungeon, home, world; in
the lead's scratchpad `p5design/design:<area>/design.md` with their prototypes) were merged by the lead into this one contract. Every
conflict between them is settled below (section 0); where the designs agree the contract repeats their names so the engineers can read
either. The numbers were re-checked in `p5design/lead/proto_check.py` (ALL OK: the level formula table, the dungeon totals and the
Trial -> floor mapping, the gate-court geometry, the stamina bar, the berry prices).

The player's words are requirements. Everything else below was decided so a kid can repeat each rule in one sentence.

### 1. What the player asked for -> what we build (the checklist; every item of `phase5_request.md` has a row)

| # | The player's words / decision | What we build (section) |
|---|---|---|
| 1 | "When a pet is evolved, show the evolved version in ALL places" | ONE rule, `State.PetStage(key)` -> `opts.Evolved`, evolved models always Low, applied at the 14 call sites of 3.7 (Pets panel, Index, Team, Fusion, Food Machine / Training / Garden rows, roulette reveal, Ring cards, battle units + helper portraits, followers, home pets, Pet Podium) |
| 2 | "a level-up gives +stats; the 1st evolution makes the level stat BONUS x1.50; the 2nd x1.25 more (x1.875 total)" | `PetCatalog.LevelFactor(level, stage) = 1 + 0.1 x (level - 1) x {1, 1.5, 1.875}[stage]`, applied ONCE in `StatsOf` / `GetStats(.., stage)`; the flat x1.25 / x1.5 is deleted everywhere (3.1) |
| 3 | "Economy pets must be as useful as combat pets in fights: SUPPORTERS (~70% damage; heal / shield / damage boost / speed boost)" | Role **Support** in battle (`BattleCatalog.Roles.Support` Power x2.6 / Health x1.5 -> measured 0.71 of a Combat pet's DPS); each of the 15 Economy pets gets ONE of Heal / Shield / Rally / Haste as its special AND its helper buff (3.2) |
| 4 | "replace the Trial portal with a DUNGEON game mode (anime dungeon style)" | **The Dungeon**: 12 floors x 4 rooms (3 wave rooms + a boss room), loot per room, first-clear Tokens + Gems, solo or a party of 4; Trial progress -> unlocked floors (`Best = min(10, floor(TrialBest / 3))`); everything "Trial" deleted (section 5, 4.2, 10) |
| 5 | "ONE portal per game mode; the obby gets one portal with a level picker (all 5 levels kept); move the other portals close to each other" | `Portal_Obby` + `ObbyPick` remote + `shared/ObbyLevels.lua` (unlocks derived from `Stats.BestTimes`: no migration); six gates in one **Gate Court** (Home, Obby, Dungeon, Ring, Arena, Altar) built by one `WorldStyle.BuildGate` (6.1-6.3) |
| 6 | "less cute, more high-quality, serious-game looking (still optimistic and happy)" | Art rules (real materials, plinth / body / cap, chamfers, muted big surfaces, neon inlays only), `Lighting.Technology = Future`, light budgets; rebuild order LightingService -> LobbyBuilder -> HomeBuilder (every station) -> ArenaBuilder (`arenaart`, W4); the obby courses and the Storm Altar keep their cloud look on purpose (6.4) |
| 7 | "GUI: use the style of 21.png; GUIs must not blind the screen" | `NeonKit` (dark navy cards, neon borders, glossy icon orbs, GothamBlack with a stroke); every window is a right side panel <= 44% of the width (landscape) or a bottom sheet <= 56% tall (portrait); the five full-screen backdrops are deleted; measured coverage 40-56% on phones (was 78-85%) (6.6) |
| 8 | "House: too many food options: make it clear and obvious" | ONE food (**berries**), ONE **Feed** button (spends berries, never Cash); the Berry Farm grows them for free, the Food Machine turns them into XP; a 4-tile flow strip in the Home window and three world signs say the whole loop (3.4) |
| 9 | "Economy pets wander freely, go to eat, then poop Cloud Cash (the obby token look, animated)" | `shared/HomeRoam.lua`: a deterministic roam plan shared by server and clients; pets eat at the Food Bowl, walk out, poop **Cloud Cash** (`shared/TokenLook.lua`, the obby token geometry), idle, walk back; the server computes only poop times / points (3.5) |
| 10 | "too many decor options: compact, cheaper; fewer things in the house but more detailed and meaningful" | 18 -> **11 stations**: 4 plants -> one 40-level **Berry Farm** (id `Press1`), the Coin Magnet folded into the Garden, decor 6 -> 3 at 40% of the old price; the removed levels come back as Home Level credit (`FoldLegacy`) so no Home Level drops (3.3, 4.3) |
| 11 | "Big pets touch each other while following; follow without fusing, less attached to the player" | `PetController.FormationFor(widths)`: slots from the measured model width, a 1.2-stud camera channel, a V for 3, softer filter + a 2-pass separation (prototype: gaps >= 0.4 studs in every manoeuvre, never ahead) (3.8) |
| 12 | "A sky like 23.png" | Blender skybox (6 x 1024 px, committed as `branding/sky/*.png`), the owner pastes 6 asset ids into `Config.Sky.Faces`; until then a tinted fallback (Atmosphere + pink Clouds + lavender ambient + 3000 stars) (6.5) |
| 13 | "More stamina" | `Config.Physics`: MaxStamina 100 -> **150**, regen 22 -> **45**/s (the bar refills in 3.3 s instead of 4.5), 4 dashes from full, dash ticks on the HUD bar (3.9) |
| 14 | "A bigger lobby" | Plaza radius 110 -> **150** (x1.81 area), homes ring 300 -> **340** (bridges keep 130), shop at 196 (6.2) |
| 15 | "A loading screen" | `src/first/LoadingScreen.client.lua` (ReplicatedFirst): 5 real progress stages, tips, SKIP after 6 s (7.1) |
| 16 | "A menu for the game (main menu before playing)" | The loading screen, then the main menu BEFORE the character spawns: the server keeps `CharacterAutoLoads = false` and spawns on the `MenuPlay` remote (90 s fallback); Scriptable camera over the Gate Court, PLAY / SETTINGS (music, sfx, graphics, shake, saved in `Profile.Settings`) / UPDATES; the tutorial waits for PLAY (7.2) |
| 17 | "NEW BATTLE SYSTEM (24.png): team of 3, fight with 1 FIGHTER (attack / element / special / dash), 2 HELPERS with buffs; swap mid-fight; same system in Dungeon, Ring, duels, raids; the 4th team slot removed" | One `BattleSim` for every mode: the player's character is the fighter's body and moves at the fighter's battle speed (`MovementController.SetBattleSpeed`, so the server fighter always keeps up), server-authoritative hits with client-predicted motion, helpers = one BUFF button each + SWAP (10 s) + auto-swap on KO = 3 lives, NPC wind-ups the dash can dodge; HUD per 24.png; Teams = 3 keys (`P3.MAX_SLOTS 3`, the 4th key dropped from the preset, the pet stays owned) (section 4) |
| 18 | "you decide which model and which effort; use the skills that improve this build" | Fable for the riskiest builders (battle core, BattleService, Dungeon server, save data, the coin ledger), Opus elsewhere, effort high (section 11); skills applied: roblox-architecture / security / performance / datastores / ui / new-system, design-critique on renders, Blender for the sky |

### 2. The design in simple words (what the README will say)

* **Fight with one pet, bring two helpers.** Your team is 3 pets. The first is your FIGHTER: you move it (at its own speed: fast pets are faster), you press ATTACK,
  ELEMENT (cooldown), SPECIAL (when the energy bar is full) and DASH to dodge. Your two HELPERS float behind you: each has one
  BUFF button (Support pets heal, shield, boost damage or speed; other pets give their element's buff, like Earth = stone skin).
  SWAP puts a helper in as the fighter. If your fighter goes down, the next pet steps in: three lives. Same controls in the
  Dungeon, the Champion Ring, duels and boss raids.
* **Economy pets are Supporters.** They hit for about 70% of a Combat pet and their special heals, shields or boosts (the Pets panel shows their battle power). Best as
  helpers, but they can fight.
* **Levels and evolutions.** Every level adds +10% of the level-1 stats. After the first evolution that bonus grows x1.5 per
  level, after the second x1.875. Nobody gets weaker: every evolved pet is a little stronger than before.
* **The Dungeon** (where the Trial Portal was): 12 floors. A floor is 4 rooms: three rooms of enemy waves and a boss room.
  Every room pays Cash, Tokens and XP to everyone who fought in it (standing still pays nothing); clearing a floor for the first time pays
  big Tokens and Gems and unlocks the next floor. Go alone or with up to 3 friends (each with their own fighter and helpers). Your old Trial record already unlocked floors.
* **One portal per mode, all together.** The Gate Court: Home, Obby (pick your level: beating one unlocks the next), Dungeon,
  Champion Ring, Arena, Storm Altar. The lobby, the homes and the arena island are rebuilt from stone and wood under a pink-purple cloud sky with stars; the obby courses
  and the Storm Altar keep their cloud look on purpose.
* **Your home, simpler.** One Berry Farm (40 levels) instead of four plants; the Pet Garden also pulls your coins to you; three
  decorations instead of six, much cheaper. Your garden pets roam the yard, eat at the Food Bowl and poop Cloud Cash: walk over
  it to scoop. Extra berries fill your Berry Basket; at the Food Machine ONE button, Feed, turns berries into XP. No Cash for food.
* **Evolved pets look evolved everywhere.** Followers, garden, Pets panel, Index, Team, Fusion, battles.
* **Pets follow better.** They keep their distance from you and from each other, and stay out of the camera.
* **More stamina**: 150, refills faster, 4 dashes from full.
* **New look and feel.** Dark neon menus that never cover the whole screen, a loading screen, then a main menu with settings before your character appears.
* **Nothing is lost.** Pets, levels, evolutions, Cash, Gems, Tokens, homes and records all carry over; old Trial clears become
  dungeon floors; a 4th team pet goes back to your list.

## Phase 5 build contract (the engineers code strictly to these names)

Sections 1-2 above are the player-facing design; sections 0 and 3-12 are the contract. File:line anchors point at the Phase 4
release (main at 7aa0df2) and drift as the waves land: search for the named function. The Phase 4 contract stays in force where
this one is silent (the Champion Ring, the Food Machine's XP shares, training, the home portal, safe zones, the pet cards).

### 0. Conflicts between the four designs and how the lead settled them (these rulings win over the design files)

| # | Topic | Ruling |
|---|---|---|
| C1 | Dungeon combat API: battle proposed ONE open encounter per run with a moving zone (`SetEncounterZone`); dungeon proposed a fresh BattleSim per room | **One encounter per ROOM** (a fresh BattleSim, full HP, like the Ring's rounds; proven chaining). `SetEncounterZone` is not built. Names in 4.6: `OpenEncounter`, `SpawnWave`, `FinishEncounter`, `RemoveEncounterTeam`, `EncounterStatus`, `TeamSpec`; per-encounter callbacks in the spec (`OnEnd / OnWave / OnBossHp / OnDown / OnLeave`) instead of global signals |
| C2 | Who pays dungeon XP (battle: BattleService at Finish via `DungeonXp`; dungeon: DungeonService per room) | **DungeonService pays everything** (Cash, Tokens, XP, Gems, chest) per room through `payOnce`-style marks; `PAY.Dungeon = nil`; `BattleCatalog.DungeonXp` is not built, `DungeonRewards` (5.2) is the formula; the loss third uses `BattleCatalog.RealLoss` |
| C3 | Dungeon lighting: server `LightingService.Push / Pop` vs client `LightingStack` | **Client `LightingStack`** (`src/client/LightingStack.lua`, 6.4); the server never writes Lighting after boot |
| C4 | Where the mode gates live and who builds them | All six gates stand in the Gate Court under `workspace.NimbusLobby.Gates` (lobby budget 8000) and are built with `WorldStyle.BuildGate`: LobbyBuilder (Home, Obby, Altar), ArenaBuilder (Ring, Arena), `DungeonBuilder.BuildPortal` (Dungeon). The arena island budget drops its portals |
| C5 | Dungeon save record: battle wanted counters inside `Battle`; dungeon a new top-level `Dungeon` | **Top-level `Dungeon`** (the Phase 4 rollout rule: nothing new inside `Battle`) |
| C6 | `PetCatalog` edits (battle: battlecore owns them) | **Lead, wave 0** (the Phase 4 ownership rule): `LevelFactor` / `EvolutionBonus` / `StatsOf` / `GetStats(.., stage)` / `EvolutionBonusOf`, `SpecialKinds` + the 15 Support specials, `Validate`. `EvolutionBoost` / `EvolutionMultiplier` stay as deprecated aliases (old values) until the lead deletes them in the wave-3 gate |
| C7 | `MovementController` (battle: `SetDashKeys` + free battle dash; home: `EXHAUST_RESUME`) and `HudController` (home: dash ticks; world: pills / vitals) | MovementController -> **battleclient (W3)** does both; HudController -> **neonkit (W2)** does both (one owner per file per wave) |
| C8 | `MenuController` (battle: Team 3 slots; home: Home strip / Pets / stage; dungeon: Stats line; world: tile grid + Dock) and `ArenaController` (battle: Trial window out + Practice; dungeon: deletions + prompt hand-off; home: Ring card stage; world: Dock) | MenuController -> **careui (W3)**, ArenaController -> **dungeonclient (W4)**; each does every area's lines (listed in 11.1). `NeonKit` / `CloudUI` / `Theme` land in **W2** so every window owner adopts them in W3-W4 |
| C9 | Tutorial / NPC edits wanted by all four areas | ONE **tutorial** owner in W4 (TutorialService, TutorialSteps, TutorialController, NpcDialog) with the merged step table of section 8 |
| C10 | Economy: battle raises late coins +15-20% (LevelFactor), dungeon adds +~8% Cash, home re-prices stations x1.25 | The home sim already carries LevelFactor; the economy engineer runs `sim_tycoon.py --ring 0.08 --dungeon 0.1` and must print ALL TARGETS MET (Gems <= 135/h: the sim shows 97); if it fails, `Dungeon.RoomSeconds` shrinks first, never the home prices |
| C11 | `Config.Attr.InBattle` (BattleService notes it is missing from Config) | Added in W0: `InBattle = "InBattle"`; BattleService reads `Config.Attr.InBattle` with its own string as the fallback |
| C12 | Ring portal location (Phase 4: `RingSite` beside `Portal_Trials`, parented to BattleArena) | `LobbyInfo.RingSite = GateSites.Ring`; `Portal_Ring` is still built by ArenaBuilder (`Ring.buildPortal` calls `WorldStyle.BuildGate` + its crown, <= 120 parts) but parented under `NimbusLobby.Gates`; `ArenaInfo.RingPortal` keeps pointing at its pad |
| C13 | PetBuilder `Wild` look for dungeon enemies (optional in the dungeon design) | Built by **pets (W3)**: `opts.Wild = { Tint, Eyes }`; the dungeon works without it (unitInfo `wild = true` just picks a Low model) |
| C14 | Berries attribute vs ProfileSync | `Profile.Berries` rides in ProfileSync like Cash (the player attribute `Berries` is the fast path, written only by DataService, <= 2 writes/s); a Berries-only change never triggers a sync |
| C15 | Judge B1: the character (16 / 27 studs/s) outruns a server fighter capped at the pet's MoveSpeed x 1.6 (9-18): attacks refused, slow pets leashed out | **The character moves at the fighter's legal battle speed** (`Fighter.WalkOf` 12..20 walk, x1.3 run) via `MovementController.SetBattleSpeed`; the server cap is the legal run x `MoveSlack 1.25`; the leash measures the gap AFTER the legal step (4.3, 4.4; `p5design/lead-fix/leash_fix.py`: zero leashes, 0% time > 6 studs behind, for every species) |
| C16 | Judge M2: BattleService must not require DungeonService (recursive require; `loadOptionalService` would nil one of them) | `BattleService.SetRunProvider({ KeysInRun, GetRun })` called last in `DungeonService.Init`; BattleService boots and works without it (4.4) |
| C17 | Judge M7: the approved "menu BEFORE spawning" vs the client-only gate | The server holds the character: `CharacterAutoLoads` stays false, `MenuPlay` (or a 90 s fallback) spawns it; `PlayerService.lua` gets an owner (menu, W3); every ScreenGui except loading / menu / notify is gated (deny-list) (7.2) |
| C18 | Judge M5: two owners per shared tool file in one wave | Named per-owner blocks created empty by the lead in W0 in `dump_gui.lua`, `dump_model.lua`, `smoke_p5_gui.lua`, `smoke_p3_ui.lua`, with the smoke.py "own block only, re-read before each edit" rule; `render_*.py` stay lead-owned (11) |

### 3. Pets, stats and the home: exact rules and numbers

#### 3.1 The level formula (PetCatalog, lead W0; the ONE source for battle, coins and UI)

```
PetCatalog.LevelBonus = 0.1
PetCatalog.EvolutionBonus = { [0] = 1, [1] = 1.5, [2] = 1.875 }      -- multiplies the LEVEL BONUS, not the stat
PetCatalog.LevelFactor(level, stage) = 1 + LevelBonus x (clampedLevel - 1) x EvolutionBonus[stage]   (stage nil -> 0)
PetCatalog.StatsOf(def, level, tier, stage) / GetStats(subject, level, tier, stage)   -- stage 0..2 = the STORED stage,
    cleaned by EvolutionStage(def, level, stored); the level alone never evolves a pet
PetCatalog.EvolutionBonusOf(stage) -> 1 | 1.5 | 1.875      ("Level bonus x1.5" in texts)
```
Rarity 1 examples: L1 1.0 (unchanged), L20 evo1 3.85 (was 3.625, +6%), L50 evo2 10.19 (was 8.85, +15%), L100 evo2 19.56 (+20%);
nobody gets weaker (`proto_check.py`). Every old flat-bonus site switches to `GetStats(.., stage)` / `LevelFactor`: `BattleCatalog`
`P4.evoMult` (battlecore), `TycoonCatalog.PetPower = RarityScale x LevelFactor(level, stage) x TierMultiplier x RoleMult` and
its `MIRROR.EvolutionBoost` (economy), `PetCareService` evolve toast "Level bonus x1.5!" / "x1.875!" (care), `CareController`
:2422 text (careui), `NpcDialog` :330 (tutorial), `MenuController` Pets panel stats and `ArenaController` :1484 (`GetStats(key,
level, nil, State.PetStage(key))`), `tools/sim_tycoon.py` (`EVOLUTION_BONUS = [1.5, 1.875]`). `PetGrowth[key].Evo` is untouched:
no save migration (`p5data_evo_untouched`).

#### 3.2 Roles and specials (battle 2.3-2.4; PetCatalog data by the lead, BattleCatalog by battlecore)

* `BattleCatalog.Roles = { Combat = { Power 1, Health 1, Name "Fighter" }, Support = { Power 2.6, Health 1.5, Name "Support" } }`,
  `BattleCatalog.RoleOf(def) -> "Support"` when `def.Role == "Economy"`. Applied in `UnitStats` only (measured DPS ratio 0.71,
  HP 0.72-0.80: "about 70%"). Garden income is untouched (`RoleMult` Economy 1.6 stays).
* `PetCatalog.SpecialKinds = { "Blast", "Heal", "Shield", "Storm", "Pounce", "Freeze", "Beam", "Rally", "Haste" }` (+ Rally:
  fighter damage +35% for 8 s; Haste: attack + move speed +35% for 8 s). The 15 Economy pets (all of `Role = "Economy"`) get
  exactly one Support kind, ids kept, names kept where they fit: **Heal** honey_bunny, sleepy_owl ("Drowsy Lullaby"), blossom_bunny,
  cherry_panda, starlight_unicorn; **Shield** mochi_slime, pip_penguin ("Snow Wall"), sunbeam_bear, phantom_kitsune; **Rally**
  waffle_corgi ("Sunny Bark"), shroomie_frog ("Spore Cloud"), hydralotl ("Void Fangs"); **Haste** pebble_pup ("Fetch Dash"),
  candy_unicorn ("Sugar Rush"), nebula_axolotl ("Stardust Swirl"). Combat pets keep their specials (the three Combat Shield pets
  keep Shield). `PetCatalog.Validate`: every Economy pet's kind in {Heal, Shield, Rally, Haste}; every pet has an Element.

#### 3.3 Stations: 18 -> 11 (`TycoonCatalog.Version = 5`; home 2.1; economy W1)

`TycoonCatalog.Kinds = { "Farm", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }`.

| Id | Name | Kind | Max | Caps C/V/M/S | Requires | Base prices (level 1..max) | Effects |
|---|---|---|---|---|---|---|---|
| Press1 | Berry Farm | Farm | 40 | 10/22/37/40 | Garden 1 | `FARM_PRICE` (home 2.1: 15, 70, 160, 450, 520, 1400, 1500, 3100, 4400, 7500, 11000, 19000, 22000, 25000, 28000, 31000, 45000, 48000, 110000, 120000, 150000, 160000, 200000, 220000, 320000, 340000, 360000, 380000, 460000, 510000, 610000, 790000, 850000, 1000000, 1400000, 1500000, 1800000, 2200000, 2800000, 4000000) | `Food` = `FARM_FOOD` (7, 9, 12, 15, 19, 25, 32, 41, 54, 69, 77, 90, 105, 122, 143, 166, 194, 227, 264, 309, 360, 420, 444, 483, 526, 573, 624, 680, 740, 806, 878, 956, 1041, 1133, 1234, 1344, 1463, 1585, 1838, 2132) |
| Garden | Pet Garden | Garden | 8 | 2/4/6/8 | (root) | 0, 15000, 38000, 140000, 360000, 750000, 1500000, 3000000 | `Lucky` 0 .02 .04 .06 .08 .10 .12 .15; **`Radius`** 8 10 12 14 16 19 22 26; **`PileSeconds`** 300 330 360 390 420 480 540 600; `ResetLevel = 1` |
| Kitchen | Food Machine | FoodMachine | 5 | 1/2/4/5 | Press1 1 | 300, 44000, 400000, 850000, 2400000 | `FeedShare` .25 .30 .35 .42 .50 |
| Gym | Training Place | Training | 5 | 1/2/4/5 | Kitchen 1 | 3800, 140000, 520000, 1200000, 2800000 | `Slots` 1..5 |
| Vault | Vault | Vault | 5 | 1/2/4/5 | Press1 6 | 11000, 110000, 460000, 1000000, 2500000 | unchanged |
| House | House | House | 4 | 4/4/4/4 | Press1 2 | 180, 24000, 200000, 880000 (NOT scaled) | Cottage / Villa (HL 10) / Manor (20) / Sky Castle (30) |
| FusionMachine | Fusion Machine | Fusion | 3 | 1/2/3/3 | Kitchen 1, Prestige 1 | 31000, 420000, 1800000 | unchanged |
| ArenaGate | Arena Gate | Arena | 1 | 1/1/1/1 | Gym 1 | 320000 | unchanged |
| DecorFence | Yard Fence | Decor | 3 | 1/2/3/3 | Garden 1 | 2800, 19000, 200000 | picket + tulips / hedge + cloth banners / cloudstone + royal banners + starflowers |
| DecorFountain | Fountain | Decor | 3 | 1/2/3/3 | Kitchen 1 | 18000, 200000, 600000 | basin + 4 wood lanterns / tiered + 6 brass / sky + 8 crystal |
| DecorPodium | Pet Podium | Decor | 3 | 1/2/3/3 | Garden 1 | 3600, 38000, 230000 | unchanged looks |

* Station prices are the Phase 4 prices x1.25 (feeding no longer costs Cash; the sim needs it to keep the 13 pacing targets);
  House and decor are not scaled; decor = 0.4 x Phase 4. Tier-cap sums 24 / 45 / 72 / 80. `HomeLevelOf(home) = sum of station
  levels + (home.DecorCredit or 0) + LegacyMagnetLevel(home)`. Prestige, stars (x1.5^stars), LegacyPrices, Gems: unchanged.
* Layout (plot-local, 72 x 72, `PlotSize` unchanged; `TycoonCatalog.PlotSize` is read by LobbyBuilder, which may NOT change it):
  Berry Farm `at(-26.5, 0.25, -90)` footprint `V3(36, 12, 7)` pad `padAt(-19, 0, -26.5, 0)` (the four press slots merged; the
  `PressLane` path stays); **Kitchen and Gym swap places**: Food Machine `at(-24, 29, 0)` footprint `V3(16, 10, 10)` pad
  `padAt(-19, 22.5, -24, 29)`; Training Place `at(25, 24, 0)` footprint `V3(18, 10, 9)` pad `padAt(19.5, 14.5, 25, 24)` (its
  `Spot1..5` attachments move with it); Garden unchanged `at(24, -1, 90)` `V3(22, 4, 20)` with a new interior: `Garden.Slot.Bowl =
  { Center = V3(0, 0, 0), Radius = 2.5 }` (the Food Bowl), `Garden.Slot.Beds` (12, nearest the entrance first): (-9, -6.5), (9, -6.5),
  (-9, -2.5), (9, -2.5), (-9, 1.5), (9, 1.5), (-9, 5.5), (9, 5.5), (-6, 7.8), (6, 7.8), (-2, 7.8), (2, 7.8); `Garden.Slot.Fence` 0.6
  studs on the footprint edge with `Garden.Slot.Entrance = { Center = V3(0, 0, -10), Width = 4 }`; `WelcomePile` V3(13.5, 0, 2.5)
  unchanged. The Collector corner and the old decor strips become lawn. `Validate`: beds inside the footprint, >= 3 studs apart,
  >= Radius + 1.5 from the bowl, off the entrance; the WelcomePile outside the fence and off every pad; `RoamLayout()` yields
  >= 300 nodes with every bed and eat point reachable; the "no dead end" build-out from a fresh home and from stars 1-3.
* **Pad signs** (`TycoonCatalog.SignedPads(pads, cash, maxSigns) -> {[id] = true}`, pure; `SignRules.MaxSigns = 3`): the Prestige
  pad when unlocked; then the 3 cheapest not-Locked pads with `Price <= cash`; none affordable -> the single cheapest. Locked pads
  never get a sign (their reason only within `K.LOCKED_SIGN_NEAR 6` studs). HomeFx hides every other `PadSign` (state "Unsigned").
* Economy proof (home `sim_p5.py`, 120 players x 3 runs, with LevelFactor): first paid buy 0:27, Villa median 26:07, first Prestige
  median 2:05 (p10 1:37, p90 2:29), runs 2-3 53 / 47 min, first EVOLVE median 1:17, Gems <= 97/h, Combat-only 2:16: ALL 13
  TARGETS MET. `tools/sim_tycoon.py` becomes this model (constants block by id, `BERRY = [0.25, 30]`, `--migrate5`, `--dungeon`).

#### 3.4 Berries: ONE food, ONE Feed button (home 3; economy W1 data, care W2 service, careui W3 window)

```
TycoonCatalog.Berries = { Share = 0.25, BasketMinutes = 30, BasketMin = 500, LegacyFood = { Snack = 200, Meal = 1200, Feast = 6400 } }
every Cloud Cash poop of value V adds V x Share berries to Profile.Berries (whole berries; the fraction stays in the server ledger), clamped so the
  poop never lifts Berries above BasketCap (TycoonService clamps the addition; a cap that drops below the berries, e.g. a pet taken out, removes NONE;
  offline berries and the P5Home food conversion ignore the cap)
BasketCap(home, incomePerSecond) = max(BasketMin, floor(incomePerSecond x Share x 60 x BasketMinutes))     -- 30 minutes of berries
FeedBerries(def, level) = round(XpToNext(level) x RarityScale x FeedBase 2.0)   -- = the Phase 4 FeedPrice in Cash (1 berry = $1 of food)
FeedXp(level, machineLevel) unchanged (25..50% of the bar);  Vault offline coins add offline x Share berries in the LastSeen step
```
* `PetCare("Feed", key)` -> `PetCareService.Feed(player, key) -> ok, { Xp, Levels, Level, Cap, Berries }`. Checks in order (each a
  toast, nothing moves before the last): loaded and not provisional; owned; below the cap; not in a running battle or dungeon run
  (`BattleService.KeysInBattle`); Food Machine built ("Build the Food Machine at home first"); berries >= cost
  ("Not enough berries: a feed needs 340 (you have 120). Your garden pets grow more!"). Then ONE non-yielding step: spend
  (`DataService.SpendBerries`; the old `Food` items were converted into berries ONCE by the P5Home step of 9.2, so there is no leftover path), `GrantXp`;
  XP write 0 -> refund in the same step. A `{Count}` / `{Food}` second argument from an old client is ignored (one feed). Rate
  limit unchanged. `Fed:Fire(player, key, "Berries", levels)`. Deleted: the Cash path (`spendCash` refunds), `{Count}` "Level up",
  `{Food}` leftover mode, `Care.planFeeds` multi-feed branch, "Feed (free Feast, 3 left)".
* Kid rule (README, Home strip, signs): "Your Berry Farm grows berries. Pets eat at the Food Bowl and poop Cloud Cash; the extra
  berries fill your Berry Basket. At the Food Machine, Feed turns berries into XP." A full basket toasts "Basket full! Feed your
  pets" (coins never stop). Berries survive Prestige. Pets panel "Feed" becomes "Food Machine" (opens the window on that pet).
* World signs (HomeBuilder, World text rule): Berry Farm "Berry Farm Lv 13 / Grows berries for your pets" (MaxDistance 70);
  Food Bowl "Food Bowl / Pets eat here, then poop Cloud Cash!" (40); Food Machine "Food Machine / Berries -> XP: press E" + a
  basket line "1,240 / 3,000 berries" rewritten by HomeFx from the player attribute `Berries` and the plot attribute `BerryCap`.

#### 3.5 Roaming pets and Cloud Cash (home 4; `shared/HomeRoam.lua` + `shared/TokenLook.lua` by economy+roam W1, ledger by tycoon W2, HomeFx W3)

```
HomeRoam.Version = 1;  Cycle 24 s = 3 meals;  EatSeconds 3;  PoopSeconds 1.5;  MinSpeed 4 / MaxSpeed 9 studs/s;  WalkBudget 16.5
HomeRoam.Build()  (lazy, once per VM: a 2-stud grid over |x|,|z| <= 33 minus EVERY station footprint built or not (+1 stud), pads
                   (+0.5), the garden fence (entrance open), bowl and beds, from TycoonCatalog.RoamLayout(); 8-neighbours in a FIXED order)
HomeRoam.Plan(seed, slot, cycle) -> { Out = {{x,z}...}, Poop = {x,z}, PoopAt, Speed, OutLen, Idle }   -- Park-Miller PRNG seeded
                   seed x 7919 + slot x 104729 + cycle x 1299709; eat [0,3) at the eat point (bowl centre + 5 studs at (slot-1) x 30 deg),
                   walk out at clamp(2 x OutLen / 16.5, 4, 9), poop ON the path at arc fraction 0.35..0.7 (rounded to 0.1 stud, pulled
                   back from the Welcome pile), stop 1.5 s, idle, walk back to arrive at 24 s; cache <= 3 cycles per (seed, slot)
HomeRoam.At(seed, slot, epoch, now) -> x, z, state ("Settle"|"Eat"|"Walk"|"Poop"|"Idle"), dirX, dirZ
HomeRoam.PoopTime(seed, slot, epoch, cycle);  HomeRoam.BedPoint(slot);  HomeRoam.EatPoint(slot)
RoamSeed = (OwnerUserId % 2147483646) + 1;  epochs are workspace:GetServerTimeNow() values on both sides
```
* Server ledger (`TycoonService` `Coins` helper, 1 s tick, no motion): poop value = `CoinValue(home, PetPower, stars) x PoopMeals 3`
  (Lucky x5 by `LuckyChance`); a NEW key in a slot gets `Epoch = now + SettleSeconds 20` (first poop >= 24 s later; churn-proof),
  the same key back within one cycle keeps its epoch; a fresh ledger staggers `Epoch = now + Rng x 24`; at most 2 catch-up poops
  per slot per tick; a slot whose lawn value >= `PileSeconds(home) x its coin rate` naps (`:N<cycle>`, no poop) and wakes after a
  scoop below the cap (`Epoch = now + the back walk`); `DropsPerPet 3` then merge into the nearest drop; coins -> `CollectorCash`
  and `value x Share` -> `Profile.Berries` in ONE `MutateHome` + `AddBerries` step per tick. Scoop (0.25 s loop) unchanged rules,
  `ScoopRadius(home) = max(Garden Radius, LegacyMagnet radius)` (6 without a Garden), `PileSeconds(home) = max(Garden PileSeconds,
  LegacyMagnet pile) + Vault`. Invariant every step: `sum(drops) + Welcome == Home.CollectorCash`. API: `TycoonService.Drops(player)
  -> { {Slot, Cycle, Position, Value, Lucky} }`; `Piles` stays as per-slot sums; `Collect` / `CoinsWaiting` / `ClearCoins` unchanged.
* Attributes (plot folder, written on change): `RoamSeed` (int), `RoamVersion` (= `HomeRoam.Version`; a mismatch parks pets on
  their beds and hides coins), `Roam` = `"1=1760001234.5;3=1760001240.0:N812"` (slot = epoch [`:N<cycle>` napping]), `CoinDrops` =
  `"1=812:1,813:2*;3=40:1;W=5"` (slot = cycle:stage[`*` Lucky], `W` the Welcome pile; <= 0.5 writes/s, <= 400 B; stages by poops
  `DropStages {1, 2, 4, 8}`), `BerryCap` (whole; <= 1/s); player `Berries` (`Config.Attr.Berries`, whole berries, written ONLY by DataService inside `AddBerries` /
  `SpendBerries`, throttled <= 2/s with a trailing write so the last value always lands; nobody else writes it). Removed: `CoinPiles`.
* `TokenLook.Build(opts) -> Part` (the obby token geometry moved out of `TokenService.MakeTokenPart`, output unchanged; opts
  `{ Position, Parent, Palette = "Cloud"|"Golden"|"Cash"|"GoldenCash", Scale, Light, Sparkles, Phase }`), `TokenLook.Palettes`,
  `TokenLook.Motion = { Spin 2.0, GoldenSpin 2.6, Bob 0.45, GoldenBob 0.6, BobSpeed 2.2 }`; `MakeTokenPart` calls it, then adds its
  attributes / tags / animation record as today (the `token` smoke targets do not change).
* HomeFx (client): homes within `K.PET_NEAR 110` (every 2nd frame beyond 60): each garden pet posed every frame from `HomeRoam.At`
  (yaw eased 7/s, `K.ROAM_SCALE 0.85`; Walk bob, Eat head dips at the bowl pushed out by half its width, Poop squat + a Cloud Cash
  coin arcs 0.35 s onto the poop point with a 3-cube puff, Idle sniff, Nap lies down with "Zzz", Settle hops from its bed); a
  client-only soft separation (<= 1.5 studs) from the same deterministic positions. Coins: pooled `TokenLook.Build({ Palette =
  "Cash", Scale 0.8/1.0/1.15/1.3 by stage, Light = false })`, Lucky "GoldenCash" + sparkles; a coin spawned at PoopAt is pending
  until `CoinDrops` lists (slot, cycle), fades after 2.5 s unconfirmed; others' coins dimmed and still; the zip + "+$" label at the
  drop. Budgets per client: <= 24 posed pets (own home first, then the nearest homes), <= 36 coins x 6 parts, puffs / berries pooled <= 16, plans <= 0.5/s per home.
* Deleted: `TycoonCatalog` `CoinPoint`, `Garden.Slot.CoinPoints / Spots`, `GARDEN_COIN_Z`, `GARDEN_WALKS`, `Foods` (-> `LegacyFood`
  values), `HeapStages`, kinds `Plant` / `Magnet`, station defs `Press2-4`, `Collector`, `DecorLamps / Flowers / Banners`,
  `Prestige.TeamSlotUnlock`, `MIRROR.EvolutionBoost`, `CollectorCap`; `TycoonService` `Coins.meals / applyDrops / pointOf /
  pilesText`, the per-slot `Piles` state; `HomeBuilder` `Art.Plant` x4, `Art.Magnet`, `Station_Collector`, the three old decor
  builders, cushion bowls, the sand walks; `HomeFx` heaps per CoinPoint (the Welcome heap stays), per-cushion bowls, fruit flights,
  the dip animation, the Magnet spin, `K.EVO_MAX`.

#### 3.6 HomeBuilder art (homeworld W2; home 9 + world 4.1)
`Art.Farm(level)` (3 rows of bushes along the lane: L1-10 red berries, L11-22 a blue row, L23-37 golden trellis, L38-40 the glowing
Starberry tree; crates + a little barn; Wood / Grass / Slate via Voxel; <= **150** parts), `Art.Garden(def, level, open)` (fence ring with
the entrance, 12 beds: open = cushion + tiny roof, closed = seedling + "Prestige to open"; the Food Bowl + sign; <= **95**),
`Art.Fence` / `Art.Fountain` with the absorbed looks (<= **90** / **80**), `Art.FoodMachine` + `Hopper` and `Art.Training` + `Spot1..5`
on their swapped slots, the three signs of 3.4; **restyled as well** (judge M8): `Art.House` (4 tiers: Slate plinth, WoodPlanks / Brick walls,
ClayRoofTiles, warm lanterns, <= 150), `Art.Vault` (Slate body, Metal door, a glass gem case, <= 80), `Art.Fusion` (Marble ring, Neon inlays, Metal
pipes, <= 90), `Art.ArenaGate` (a half-size `WorldStyle.BuildGate` look in Red, <= 80); renders `home:House:1..4`, `home:Vault:3`,
`home:FusionMachine:2`, `home:ArenaGate:1` at the W2 gate. Rules of 6.4 (materials, plinths, chamfers, muted big faces, `NC_Detail` tags on
pure decor). Per-station BUDGET table: Farm 150, Garden 95, FoodMachine 55, Training 90, House 150, Fusion 90, Fence 90, Fountain 80,
default 80; a fully built plot <= **950** parts (`render_model.py homeplot:SkyCastle:pads`). Prompts: `GardenSpotPrompt` on each open
EMPTY bed (attrs `Slot`, `OwnerUserId`, MaxActivationDistance 3), `FeedPrompt` on the Hopper, `TrainPrompt` on `Station_Gym` (both
move with the swap; `CARE_SIG` gains "p5:").

#### 3.7 Evolved looks everywhere (home 5; the rule and its 14 sites)
Rule: every place that draws a pet the player OWNS draws its stored stage; an evolved model is always built at **Low** (`petEvoLow
380` / `petEvo2Low 520`). Helpers: `State.PetStage(key) -> 0..2` (= `PetCatalog.EvolutionStage(def, level, State.PetGrowth(key).Evo)`,
hybrids via `PetKeys.DefOf`), `State.BestStage(petId)` (max over owned keys of that base id), `CloudUI.PetViewport(.., { Evolved = n })`
forces Low and refits the camera, `CloudUI.Slot` passes `info.Evolved` (part of the keep-key), `PetBuilder.Build` sets the clone
attribute `PB_Evolved = stage` (tests), server `DataService.GetEvolution(player, key)`. Sites (owner): followers (already; pets),
garden / roaming pets evolved Low in EVERY home within `PET_NEAR` (own home first; once the posed-pet part budget `K.HOME_PET_PARTS 9000` is spent
the farthest pets fall back to plain Low) (homefx), training pets (homefx), Pets grid
`gridInfo` + detail (careui), Index tiles `BestStage` (careui), Team card + tiles (careui), Fusion tiles + result preview (careui),
Food Machine / Training / Garden rows (careui), roulette reveal + gold "Evolved" ribbon (careui), Ring fighter cards (dungeonclient:
ArenaController), battle units + helper portraits `u.evo` (battleclient), Pet Podium (tycoon: SpotService, rebuilt on
`PetCareService.Evolved`). NPCs, showcases, shop strips, enemies: unchanged.

#### 3.8 Followers (home 6; pets W3)
```
PetController.FormationFor(widths) -> { {side, back}... }   (pure, tested)   OwnerRadius 1.5, GapOwner 2.5, GapPet 1.0, Channel 1.2, Diag 0.35
1 pet  { Channel + w/2, OwnerRadius + GapOwner + w/2 - Diag x w/2 }            (behind-right)
2 pets the smaller left { -(Channel + wa/2), row }, the other { Channel + wb/2, row }, row = OwnerRadius + GapOwner + max(wa,wb)/2 - Diag x min(wa,wb)/2
3 pets the two smallest as for 2; the biggest behind the right one { Channel + wc/2, row + wb/2 + GapPet + wc/2 }
width = max(X, Z) of the built model (GetExtentsSize), cached P4.widths["key|stage"];  filter rateH = 4.2 + 0.6 x (slot-1), LEAD_H 0.10
separation after the filter every frame (n <= 3): 2 passes; overlapping pets (d < ra + rb + 0.4) pushed apart half each; inside OwnerRadius + r + 0.4 -> on that circle
```
Prototype (`proto/follow_p5.py`): smallest gap pet-pet 0.40 and pet-owner 0.40 studs in every manoeuvre, never ahead, rest 5.8 (1 small)
.. 17.2 studs (3 big). Smoke windows (size-aware): rest = |slot| +- 1.5, walking lag <= back + 9, settle <= back + 1, ahead <= 0.5 after
0.6 s, gaps >= 0, channel >= 1.0. Deleted: `FORMATION`, the `slotOffsets` fan, `P4K.EVO_BACK_MAX` / `p.backMul`.

#### 3.9 Stamina (lead W0 numbers; HUD by neonkit W2; MovementController by battleclient W3)
`Config.Physics`: `MaxStamina = 150`, `StaminaRegen = 45`, `RunStaminaDrain = 14`, `DashStaminaCost = 35` (4 dashes from full).
MovementController `EXHAUST_RESUME = 22` (15%). HudController `updateStamina`: unchanged maths + `floor(MaxStamina / DashStaminaCost)`
thin dark ticks. Inside a battle zone a dash costs no stamina (`MovementController.SetFreeDash(true)` by BattleController; 4.4) and the character walks / runs at the
fighter's battle speed (`SetBattleSpeed`, 4.4); running drains stamina as today.

### 4. The battle system (battle design; battlecore W1 Fable, battleservice W2 Fable, battleclient W3)

#### 4.1 Decisions in one screen
| # | Decision | Why |
|---|---|---|
| B1 | The player's CHARACTER is the fighter's body: the fighter pet hovers at the shoulder; the player moves it with the normal controls (WASD / joystick / camera / DASH) **at the fighter's legal battle speed** (walk `Fighter.WalkOf(MoveSpeed)` = 12..20 studs/s, run x1.3 = 15.6..26; the obby run is 27); enemies hit the pet's HP, never the Humanoid | reuses MovementController, camera and joystick; the server fighter (cap = legal run x 1.25) always keeps up: `lead-fix/leash_fix.py` 20 seeds x 60 s + a circle at r 14 with 200 ms latency: 0% of the time more than 6 studs behind and zero leash-outs for every species (the judge's model: 12-49% and a leashed Slime) |
| B2 | Server-authoritative hits, client-predicted motion: one small command per button; the server owns cooldowns, ranges, damage; the client plays the lunge at once and shows numbers only from server `Hit` events | roblox-security: never trust client damage |
| B3 | Helpers are not units on the floor: client-only models behind the player; one BUFF button each (cooldown) + SWAP (10 s); a downed fighter auto-swaps to the next alive helper = 3 lives | "fights with only 1"; ~1 unit per player (16-raids stay cheap) |
| B4 | NPC attacks wind up 0.45 s (`Winding`) so the 0.35 s dash i-frames can dodge them; bosses keep telegraphs | a dodge button needs something readable |
| B5 | `TeamPower = KitFactor 1.5 x UnitPower(fighter) + HelperWeight 0.35 x (UnitPower(h1) + UnitPower(h2))` for the Ring solver, the duel gap, the dungeon ladder | a played fighter beats a passive NPC of up to ~1.5x its power (prototype) |

#### 4.2 BattleCatalog (battlecore; data the clients read too)
```
BattleCatalog.Fighter = { AttackSlack 3.0 (studs of extra reach for latency: run 20 x 0.15 s), AttackTolerance 0.85 (an attack is accepted >= Interval x this
  after the last), AutoRepeat true, ElementCooldown 7, ElementMult 2.4, ElementRange 14, SpecialMeterMax 100, MeterPerSecond 6, MeterOnHit 4,
  MeterOnHurt 2, DashSeconds 0.35, DashCooldown 2.5, DashIFrames 0.35, SwapCooldown 10, SwapCastSeconds 0.6, BenchRegenPerSecond 0.03,
  DownAutoSwap true, HelperCooldown 15, SupportCooldown 12, Windup 0.45, KitFactor 1.5, HelperWeight 0.35, Lives 3, WalkMult 1.15, WalkMin 12, WalkMax 20,
  RunMult 1.3, MoveSlack 1.25 (the server fighter's cap OVER THE LEGAL RUN SPEED: latency + a cheat margin), Leash 10, LeashSeconds 3 }
BattleCatalog.Fighter.WalkOf(moveSpeed) = clamp(moveSpeed x WalkMult, WalkMin, WalkMax);  Fighter.RunOf(walk) = walk x RunMult
  (mochi_slime 12 / 15.6 .. stormfang 20 / 26 studs/s; speed buffs scale both: Haste x1.35, Slow x0.6; NPC units keep their MoveSpeed)
BattleCatalog.ElementAttacks[element] (one per Config.Elements.Order): Water "Tide Burst" Cone{70, 14, Push 4}; Flame "Flare" Cone{60, 14,
  Burn {3 s, 0.25}}; Frost "Frostbite" Cone{70, 14, Slow {4 s, 0.6}}; Nature "Thorn Lash" Cone{60, 14, Leech 0.3}; Earth "Quake" Circle{8,
  Stun 0.5}; Storm "Bolt" Line{24, 4}; Celestial "Radiance" Circle{8, MeterGain 15}; Shadow "Void Rend" Cone{60, 14, Weaken {5 s, 0.85}}
BattleCatalog.Buffs[kind] = { Name, Seconds, Value, Text }: Support (cooldown 12): Heal 0.30 max HP now; Shield 0.35 max HP 6 s; Rally damage
  +0.35 8 s; Haste speed +0.35 8 s. Element (cooldown 15): Water "Tide Mend" regen 4%/s 5 s; Flame "Blaze" +25% dmg 8 s; Frost "Chill" hits
  slow 40% 8 s; Nature "Bloom" regen 2%/s 10 s + meter 20; Earth "Stone Skin" taken -35% 8 s; Storm "Charge" attack speed +35% 8 s;
  Celestial "Halo" shield 25% 6 s; Shadow "Leech" 30% lifesteal 8 s.   A helper's button = its Support kind, else its FIRST element's buff.
BattleCatalog.Roles / RoleOf (3.2);  UnitStats(subject, level, tier, extras) uses GetStats(def, level, tier, extras.Evo) x Roles; `evoMult` gone
Damage: HpScale 2.6, DamageScale 0.6, Variance 0.2, Crit, MinHit, MaxHit (duels 0.6), DoubleKoByDamage {Duel} kept; Overtime DELETED;
  BossRules.GroupExponent 0.25 -> 0.2.  Training applies as today (Ability also x helper buff values by 1 + 0.04 x rank).
Ring: ChampionTeam / RingRewards / RingTarget unchanged; the solver compares the champion's UnitPower with the player's TeamPower (4.1 B5);
  `Ring.Growth` is re-tuned by sim_battle until the Phase 4 stage medians (S1 16 .. S10 51) hold within +-2 rounds.
Duel: DUEL_POWER_GAP 3 -> 2 (practice duel beyond it); the quick queue pairs within QUEUE_GAP AND x1.6 TeamPower (+x0.1 per 10 s waiting,
  cap x3); a challenge > x2 apart carries `Practice = true` in the invite.
Raid: BossHp(bossId, teams) uses ExpectedDps(team) = fighter DPS x (1 + SpecialDpsShare) x KitFactor^0.5 (bench 0).
Dungeon: section 5.1 data (`BattleCatalog.Dungeon`, `DungeonFloors`, `DungeonPower`, `DungeonWave`, `DungeonRewards`, `DungeonFirstClear`,
  `DungeonChest`), Zones.Dungeon {44, 44}, Zones.DungeonBoss {56, 56}, TimeLimits.Dungeon 120 (the FALLBACK only: DungeonService always passes `TimeLimit` from
  `Dungeon.RoomTime / Floor1RoomTime`), Modes + "Dungeon".
TrialRewardRules -> LossRules { LossShare 1/3, LossMinSeconds 20, LossMinDamage 0.2 }; RealLoss / LossXp kept (ring, dungeon).
Deleted: Trials, TrialCount, TrialCurve, TrialChapters, TRIAL_ROSTER, buildTrials, trialTeamPower, targetPower, TrialTeam, TrialRewards,
  ChapterOf, Zones.Trial, TimeLimits.Trial, "Trial" in Modes, MaxTeamSize 4, SynergyRules.SameElement[4], P4.evoMult / EVO_FALLBACK.
```

#### 4.3 BattleSim (shared, pure, rewritten core; keeps the 2D floor, seeded RNG, elements, applyDamage, bosses, specials' shapes, the delta wire form)
```
BattleSim.new(setup) -> battle | nil, reason
  setup = { Mode = "Duel"|"Raid"|"Ring"|"Dungeon", Seed, Id, Zone = {X, Z} | n, Teams = { team... }, Boss (Raid), Round (Ring),
            TimeLimit (nil = BattleCatalog.TimeLimits[Mode]), Specials = false (harness) }
  team  = { Owner, Side, Name, Npc, Auto, Pets = { entry x 1..3 } }   entry: Key, PetId, Def, Level, Tier, Slot, Evo, Train, Boost, Handicap,
            Boss, Wild, Xp, XpNext, Crowned, NoSpecial.  Side 1 teams: Pets[1] = the fighter, 2-3 the bench.  Side 2 / Npc teams: every pet is
            on the floor (a wave is a plain list; the Ring champion a one-pet team).  Mode Dungeon: side 2 may start empty.
battle:Command(owner, action, arg) -> ok, reason
  "Attack" (targetId|nil)   alive, not Casting / Stunned / Winding / Down, t >= nextAttack - Interval x (1 - AttackTolerance), reach = range +
                            target.radius + AttackSlack, target = arg | lock | nearest in reach; nextAttack = max(nextAttack, t) + Interval
  "Element" (id | {x, z} | nil)  cooldown ElementCooldown; shape ElementAttacks[fighter.elems[1]] from the SERVER fighter position
  "Special" ()              meter >= MeterMax; offensive kinds as today; Heal / Shield / Rally / Haste act on the fighter
  "Dash" ()                 cooldown DashCooldown -> state Dashing for DashSeconds, i-frames until t + DashIFrames
  "Target" (unitId|nil)     lock-on; Attack / Element default to it
  "Buff" (2|3)              that helper's buff; cooldown per helper (SupportCooldown / HelperCooldown)
  "Swap" (2|3)              fighter <-> helper; SwapCooldown; the incoming pet arrives Casting for SwapCastSeconds; refused while Casting / Stunned
  "Move" (x, z)             wanted floor point (fed by BattleService from the CHARACTER root every tick, never from a remote); a player fighter walks
                            at <= legalRun x MoveSlack, legalRun = Fighter.RunOf(WalkOf(MoveSpeed)) x speed buffs (x Config.Physics.DashSpeed /
                            RunSpeed while Dashing), clamped to the floor; NPC units walk at their MoveSpeed.  battle:SpeedOf(owner) -> { Walk, Run }
                            (the current legal speeds; the client's SetBattleSpeed values); the `Speed` event fires whenever they change
  "Forfeit" ()              as today (Raid / Dungeon: RemoveTeam)
battle:Step(dt) -> events;  Snapshot();  SnapshotDelta(last);  BattleSim.DecodeSnapshot(payload, prev)
battle:AddTeam(team) / RemoveTeam(owner);  battle:SpawnEnemies(list, opts) -> infos  (Dungeon / Raid minions: a side-2 Npc Auto team
  { Owner = "wave:"..n }, opts = { Wave = n, Anchor = {x, z} (default the far +Z edge), Name });  battle:LivingEnemies() -> n;
  battle:BossHp() -> 0..1 | nil (the side-2 unit with Boss = true);  battle:Finish(reason) (Dungeon: ends with Reason "Cleared" |
  "Abandoned" | "Shutdown");  battle:TeamOf(owner) -> { Fighter, Bench = {id, id}, Lives, Speed = { Walk, Run }, Cooldowns = { Element, Dash, Swap, Buff = {[slot] = t} } }
battle:Result() -> { Mode, Reason, WinnerSide, Winners, Losers, Draw, Forfeit, BossId, Round, Damage = {[owner] = n}, Shares, Duration,
  Survivors = {[owner] = lives}, Hp = {[side] = share}, Kills, Waves, BossHp, BossMaxHp }
BattleSim.States = { Idle 0, Moving 1, Attacking 2, Benched 3, Casting 4, Down 5, Stunned 6, Dashing 7 }   (Winding = Attacking + the windup bit)
BattleSim.Events = { Hit, Special, KO, Telegraph, Spawn, Enrage, Order, Zone, Leave, End, Element, Dash, Buff, Swap, Windup, Wave, EnemiesDown, Speed }
```
Event shapes: `Element { unit, element, name, x, z, angle | tx, tz, targets }`, `Dash { unit }`, `Buff { owner, unit, kind, name, until,
target }`, `Swap { owner, out, in, auto }`, `Speed { owner, walk, run }` (on Swap, Haste / Slow start and end), `Windup { unit, target, at }`, `Wave { index, units, left }`, `EnemiesDown { wave }` (the last
enemy of a spawned wave fell), `Order { owner, order, target, rejected }` (a refused command echoes `rejected`), `Hit` + `miss` (dodged) /
`burn` / `leech` / `element` / `buffDmg`. `unitInfo` + `role`, `buff = { Kind, Name, Seconds, Value, Cooldown }`, `elementAttack`, `bench`,
`wild`, `boss`, `evo`. End rules: Duel / Ring: a side with no lives loses; Ring timeout = loss; Duel timeout (120 s) -> `DoubleKoByDamage`
by damage dealt (no Overtime: a Heal is 30% per 12 s = 2.5%/s against >= 6%/s mirror DPS); Raid as today; Dungeon: side-1 wipe ->
"Wipe", timeout -> "Timeout", never ends on an empty side 2 (`Finish` does). NPC AI: threat target (last hitter within 3 s) else nearest;
melee orbit slots; `Windup` inside the interval (wave DPS = today's); a hit lands only if the target is still in reach and not Dashing, else
`Hit { miss = true }`; statuses Slow x0.6, Weaken x0.85, Stun (as Freeze), Burn 3 ticks. Deleted: ATTACK / RETREAT orders, `Retreating`,
`Damage.Retreat*`, `RetreatAutoResume`, `orderAttack / retreatStep / retreatSpot / resumeRetreats`, the per-slot Special command, `Trial`
setup, `Auto` casting for player teams, `Overtime`, `Result.Level`, `Describe.Level`. Determinism: `Move` points are part of the command
stream (the harness records them), so `sim_battle.lua` replays stay exact.

#### 4.4 BattleService (command layer, modes, the encounter API; the Ring, duel and raid plumbing kept)
* Validation ladder on every remote: `isPlayer` -> type (action string <= 16 chars; arg number / nil / {x, z} of two finite numbers) -> rate
  bucket (`cmd` burst 12 refill 8/s; `req` burst 4 refill 1/s) -> a running battle, a live participant, `present` -> `Sim:Command` -> replicate.
  Refusals silent except NotInZone / Charging / Cooldown / OutOfReach ("Too far!"; one throttled toast per 3 s per player); every refusal echoes an
  `Order { rejected }` for the button shake.
* Position authority: the 10 Hz `tickBattle` feeds `Command(owner, "Move", localX, localZ)` from `HumanoidRootPart.Position` for every live
  participant; the server fighter walks toward it at <= legal run x `MoveSlack 1.25` (4.3). A legit character moves at exactly the legal speed (B1),
  so it is never more than latency x run (<= 5.2 studs at 200 ms, prototype) ahead of the server fighter and the gap closes within a step. The leash
  measures the gap AFTER that legal step: gap > `Fighter.Leash 10` for `LeashSeconds 3` = a leaver in Duel / Ring, a `RemoveTeam` in Raid / Dungeon
  (that is a run-off or a teleport; an in-zone speed hack is NOT leashed and gains nothing: reach, hits and the drawn pet use the server fighter, Y2).
  `present` keeps its pocket rules for Ring and uses the encounter's zone part + `ZONE_MARGIN` for Dungeon.
* Speed: `Start.Team.Speed = { Walk, Run }` and the relayed `Speed` events; BattleController calls `MovementController.SetBattleSpeed(walk, run)` on
  Start / Speed and `SetBattleSpeed(nil)` on End. `MovementController.SetBattleSpeed(walk, run | nil)` (battleclient): while set, the controller
  writes `Humanoid.WalkSpeed = walk` as its base (the "server owns WalkSpeed" watch is suspended, except that a server write of 0 (Downed / frozen)
  still wins) and the run target is `run` instead of `P.RunSpeed`; nil restores the server base. `p5svc_position_legit` (12.1) proves no legit leash.
* Modes: Ring (`RingRun` as built; `teamOf(player, 1)` with Pets[1] the fighter; rewards unchanged), Duel (4.2 fair-play rules; `payDuel`
  once), Raid (16 fighters + boss + minions = ~25 units; `BossHp` by the new ExpectedDps), Dungeon (4.6). Every mode branch that knows
  Trial / Duel / Raid / Ring loses Trial and learns Dungeon: `present`, `forceRelease`, `finalizeBody`, `payOnce` (shutdown text), `monitorBattle`,
  `Forfeit` (refused in a dungeon: "Use LEAVE"), `dropOut`, `onPlayerRemoving`, `Shutdown`, `GetBattle` (+ `Floor`, `Room`), `startPayload`
  (`d.Dungeon = spec.Extra`, `d.Team = { Fighter, Bench, Cooldowns, Speed }`), `KeysInBattle` (ORs the run provider's `KeysInRun`).
* Run provider (C16): `BattleService.SetRunProvider({ KeysInRun = fn(player) -> {[key] = true}, GetRun = fn(player) -> run | nil })`, called last in
  `DungeonService.Init`; BattleService NEVER requires DungeonService and works with no provider. `canBattle` (:785) adds, after the InMatch check:
  "Finish your dungeon run first" when `GetRun(player)` is set OR the player's `InBattle` attribute is a string starting with "D" (so raid / duel /
  Ring starts and every `BattleRequest` are refused in the Hall, Corridor and Treasure states, judge M1).
* Rewards paid once: unchanged `b.Paid[uid]` + `payOnce`; `PAY = { Duel = payDuel, Raid = payRaid, Ring = RingRun.pay }` (`Trial` gone,
  `Dungeon` absent on purpose: C2). XP keys = the 3 team keys ("every pet that fought" = every team key, as the Ring pays today).
* Deleted: `StartTrial`, `payTrial`, `finishTrial`, `forfeitTrial`, `trialPortalPosition`, `St.trialPortal`, `TRIAL_RANGE`, `REQUEST_COOLDOWNS.Trial`,
  `b.TrialInfo` / `d.Trial`, the `"Trial"` dispatch, the header's Trial paragraphs; `TRIAL_RETURN_DELAY` -> `RETURN_DELAY`; `POCKET_LEASH` stays.
* `MovementController` (battleclient): `SetDashKeys(keys | nil)` (in battle: Shift = DASH, Q = SPECIAL; nil restores the obby keys),
  `SetFreeDash(bool)` (a battle dash costs no stamina; `Config.Physics` untouched), `SetBattleSpeed(walk, run | nil)` (above). BattleController calls
  all three on Start / End (SetBattleSpeed again on `Speed`). `onRunAction` / `onDashAction` ignore input until `UiGate.HasPlayed()` (7.2).

#### 4.5 Network (the three battle remotes stay; `BattleCommand` actions change)
* `BattleCommand(action, a)`: "Attack" (id|nil), "Element" (id | {x, z} | nil), "Special", "Dash", "Target" (id|nil), "Buff" (2|3),
  "Swap" (2|3), "Forfeit". A frantic player sends ~3/s; bucket 12 / 8 per s.
* `BattleState(kind, payload, battleId)`: "Start" (Describe + Zone + Names + Side + T + `Ring` / `Dungeon` info + `Team` = { Fighter, Bench, Lives, Speed, Cooldowns }), "Snapshot" (delta
  wire form, 10 Hz fighters / 5 Hz spectators), "Events" (batched per tick), "End", "Lobby". Wire form: `code = id x 128 + mask x 8 + state`,
  mask bits 1 hp, 2 meter, 4 shield, 8 target; NPC units carry `windup` (0|1) in the meter field; a fighter's shield field packs `shield x 4 +
  lives`. Cooldowns are not in snapshots: the client runs them from the `Element / Dash / Swap / Buff` events (`until`) and `Start.Team.Cooldowns`; speeds from `Speed` events.
* Size: 25 units x ~12 B x 10 Hz = ~3 KB/s per client worst case + ~1 KB/s events; `p5battle_net16` asserts < 6 KB/s per client.

#### 4.6 The encounter API (BattleService; the ONLY way DungeonService touches combat; C1 / C2)
```
BattleService.TeamSpec(player, keys | nil) -> spec | nil, reason        (teamOf exported; keys = the ring fallback; training keys skipped)
BattleService.OpenEncounter(spec) -> battleId | nil, reason
  spec = { Mode = "Dungeon", Zone = <NC_BattleZone part, Mode "Dungeon">, Seed, TimeLimit, Label, Teams = { { Player, Spec }... } (1..4),
           Extra = { Floor, Room, Wave, Waves, Name, Boss }, KeepInBattle = true,
           OnEnd = fn(battleId, result), OnWave = fn(battleId, waveIndex), OnBossHp = fn(battleId, frac), OnDown = fn(battleId, player, livesLeft),
           OnLeave = fn(battleId, player, why) }
  KeepInBattle: BattleService NEVER writes the InBattle attribute for such a participant, neither on add nor on ANY release path: `setInBattle` is
  skipped when `part.KeepInBattle` in addParticipant (:877), releaseParticipant (:1670), the ring release (:3274), forceRelease, dropOut,
  onPlayerRemoving, Shutdown and the Init sweep (:4365, which only clears ids that are not "D" strings). The dungeon RUN owns the attribute (its run
  id, written before the teleport, released by endRun). addParticipant still sets St.battleOf[player] (Command / present / KeysInBattle work).
  Everyone gets "Start" at once.
BattleService.SpawnWave(battleId, entries, opts) -> infos | nil, reason    entries 1..12 of { PetId | Key | Def, Level, Tier, Evo, Train, Boost,
  Handicap, Boss, Wild, Name }; opts { Wave, Anchor, Name }; -> Sim:SpawnEnemies + the Wave event
BattleService.FinishEncounter(battleId, reason) -> result | nil    reason "Cleared" | "Abandoned" | "Shutdown"; idempotent (nil the 2nd time);
  Wipe / Timeout end the sim by themselves. finalizeBody sends "End" with Rewards = { Dungeon = true, Extra } (no Cash / XP lines: the loot
  card is DungeonController's), fires BattleEnded(battleId, result) with Mode "Dungeon", then calls spec.OnEnd(battleId, result); the zone /
  pocket are left to the caller (no FreePocket, no return teleport).
BattleService.RemoveEncounterTeam(battleId, player) -> ok   (Quit / leave / leash / disconnect: the others fight on; OnLeave fires)
BattleService.EncounterStatus(battleId) -> { Enemies, Wave, BossHp, Players = { [userId] = { Lives, Hp, MaxHp, Down } } } | nil
OnWave fires when EnemiesDown says the spawned wave is gone and the encounter is not finished; OnBossHp on every 5% step of BossHp;
OnDown when a fighter's lives reach 0 (the team stays in the encounter as "Downed": no wipe while another team lives, the raid's sideAlive rule).
Every spec callback (OnEnd / OnWave / OnBossHp / OnDown / OnLeave) runs through `pcall`; an error is warned once per encounter and never stops
finalizeBody or the release of participants. Fail-safe: an encounter whose sim ended (Wipe / Timeout) and whose OnEnd did not call back within 10 s is
finalized by BattleService itself ("Error" reason, nothing paid).  Result for Mode Dungeon: { Reason = "Cleared" | "Wipe" | "Timeout" | "Abandoned" | "Shutdown" | "Error",
Duration, Fighters = { userId... } (participants not Left whose `Damage[userId]` >= `Dungeon.MinShare 0.05` x the party's total damage in this
encounter; a solo team qualifies with any damage > 0; judge M4), Damage, Hp = {[side] = share}, Survivors, Waves, BossHp, Extra }.
```

#### 4.7 BattleController (client; the HUD of 24.png on NeonKit; Fx / units / cards / Ring cards kept)
* Control map: Move = WASD / stick / joystick; ATTACK = left click / F / X / big round button (hold = auto-repeat at the interval);
  ELEMENT = E / Y / medium button (cooldown ring); SPECIAL = Q / RB / medium button (fills gold at 100); DASH = Shift / B / the DASH button;
  lock = Tab cycles, click an enemy or its row, T clears / RT, LT / tap a row; helper buff = 1, 2 / LB, D-up / tap the portrait; swap = hold
  1 / 2 for 0.5 s or the SWAP chip / D-left, D-right / hold the portrait. Keys bound through ContextActionService at High priority ONLY in battle.
* HUD (ScreenGui "NimbusBattle", 1080p px under `Theme.ScreenFactor()`, NeonKit cards, fonts via Theme roles, nothing in the centre):
  top-left fighter card: name (`Heading` 26) + "Lv 34" pill + element badge + stars, HP 320x22 green with a red loss trail draining 0.4 s
  behind (TweenService; HP writes only on change), ENERGY 320x14 blue ("ENERGY 72/100"), 3 hearts = lives; under it two 64 px round helper
  portraits (`NeonKit.Orb` + ViewportFrame Low built once, stroke in the element colour) with "Lv n", a 68 px cooldown ring (`UIGradient`
  rotation, written at 10 Hz), the buff name ("HEAL", "STONE SKIN"), the SWAP chip; KO greys the portrait. Right side: one 300x44 row per
  living enemy (max 8 + "+n more"): icon disc, name, element stripe, red HP bar; the LOCKED row first with a gold bracket + "TARGET"; the
  attacking enemy's icon flashes "!" during its wind-up; the boss bar stays top-centre under the Roblox bar. Bottom-right action cluster
  (touch 88 / 64 px, key chips on desktop). Phone (`Layout = "Compact"`, width < 900 px or touch): fighter card 70%, portraits 52 px in a
  column, enemy list 2 rows, the cluster a 2x2 grid above the jump button, menu column hidden; landscape 740x360: cards 0.8, nothing within
  the centre 40% of the width. Result card: as today + "Lives left" + the dungeon's `Extra` lines; the per-battle cleanup stays keyed by
  battle id (Ring chaining, dungeon rooms). Mode texts: "CHAMPION RING - Round 8 - Best 12", "DUNGEON - Floor 3 - Room 2" (purple), "DUEL".
* Models: the fighter = the team pet (High) at the shoulder offset (1.8, 0.5, 0.6) of the SERVER fighter position (interpolated like the enemies),
  blended toward the character root while the two are within 2 studs; beyond 2 studs the drawn pet follows the server position (lerp 0.35/frame),
  so what looks in reach IS in reach; helpers (Low) at (-2, 1.2, 2) / (2, 1.2, 2), fly to the fighter on Buff (0.6 s), trade places on Swap (0.5 s);
  enemies interpolated as today; `Winding` plays a crouch + a brief yellow Highlight; "DODGED!" (cyan) on `Hit.miss`; buff names float above
  the fighter; every camera shake x `ClientSettings.Get("Shake") and 1 or 0`.
* Prediction: press -> animation + the button's own ring + `St.pending[action] = t`; the matching event within 0.6 s clears it; a `rejected`
  Order or a timeout resets the ring to the server's `until` and shakes the button. Never predicted: HP, numbers, kills, meter.
* Deleted: the team-card row, ATTACK / RETREAT / per-pet SPECIAL buttons, the regroup countdown, `B.Trial`, "TRIAL n", the trial name / chips
  branches, LEAVE for Trials (LEAVE stays Ring-only; the dungeon has its own LEAVE in DungeonController).

#### 4.8 Teams of 3 (data W1; careui W3)
`Teams = { Presets = { [1..3] = { key, key, key } }, Active }`, `GetTeams().Slots` = 3 always; `P3.MAX_SLOTS = 3`, `P3.SLOTS = 3`, `slotsOf()`
returns 3, `P3.slotUnlock` deleted; `P3.cleanPreset` keeps the first 3 keys (the 4th key leaves the PRESET only: the pet copy, its level and
growth stay). `SetTeam(player, preset, keys)` refuses > 3 keys ("Teams have 3 pets: a fighter and two helpers"). Team window: labels
FIGHTER / HELPER / HELPER, a "Set as fighter" action that rotates the preset so the chosen key is slot 1; `MenuController` :6025 (the 4th slot
branch) deleted; `TycoonCatalog.Prestige.TeamSlotUnlock` deleted; the prestige confirmation loses its "4th team slot" line.

### 5. The Dungeon (dungeon design; battlecore W1 data, dungeon W3 Fable server, dungeonclient W4)

#### 5.1 Floors, rooms, waves (`BattleCatalog.Dungeon`, pure, next to `ChampionTeam`; the same solver)
```
BattleCatalog.Dungeon = { Floors 12, Floor1Power 1.5, FirstPower 4, Growth 2.0 (floor f >= 2 targets FirstPower x Growth^(f-1) TeamPower per
  player: floor 2 = 8 ... floor 10 = 2048 = the old Trial 30, floor 12 = 8192 = a maxed Rainbow team), RoomMult {0.8, 0.9, 1.0}, BossMult 1.3,
  EscortMult 0.5, Waves {2, 2, 3}, Floor1Waves {1, 1, 1}, EnemiesPerWave 2 (+1 per extra player), Floor1EnemiesPerWave 1, PartyExp 0.85,
  MinHandicap 0.3, EnemyMaxLevel 50, RoomTime 120, Floor1RoomTime 180, Zones { Room {44, 44}, Boss {56, 56} }, EscortAt 0.5, Intermission 2,
  DoorTime 12, HallSeconds 10, TreasureSeconds 45, MinShare 0.05, LateJoinLastRoom 2, ReadyTimeout 30, RunMaxSeconds = 4 x RoomTime + 4 x DoorTime +
  HallSeconds + TreasureSeconds + 120, Bands = { {1,2,{Common}}, {3,4,{Common,Uncommon}}, {5,6,{Uncommon,Rare}},
  {7,8,{Rare,Epic}}, {9,10,{Epic,Legendary}}, {11,12,{Legendary,Mythic,Secret}} } }
BattleCatalog.DungeonFloors = { {Name "Mossy Cellar", Element Nature, Kind Cellar}, {"Stone Halls", Earth, Hall}, {"Flooded Vaults", Water, Cave},
  {"Frozen Crypt", Frost, Cellar}, {"Ember Forge", Flame, Hall}, {"Thunder Spire", Storm, Bridge}, {"Star Chapel", Celestial, Hall},
  {"Shadow Keep", Shadow, Cave}, {"Magma Mines", Earth, Cave}, {"Howling Peak", Frost, Bridge}, {"Eclipse Sanctum", Celestial, Hall},
  {"Abyss Throne", Shadow, Throne} }     -- every boss room uses the Throne set
BattleCatalog.DungeonPower(floor, partySize) -> the party's target (x partySize^PartyExp)
BattleCatalog.DungeonWave(floor, room, wave, partySize, seed) -> { Pets = { {PetId, Level, Tier, Boss, Boost, Handicap, Wild = true}... }, Boss }
  enemies = catalog pets of the floor's element in the band (never EventOnly; < 2 candidates -> any element), solved like champions
  (Handicap / level 1..50 / mini-boss / Boost); room 4 wave 1 = the boss alone (forced mini-boss form, handicapped on floors 1-2),
  wave 2 = the escort at EscortMult; floor 1 = ONE handicapped enemy per wave. Deterministic for its arguments.
BattleCatalog.DungeonRewards(floor, room, waves, incomePerSecond, double) -> { Cash, Tokens, Xp }  (5.2)
BattleCatalog.DungeonFirstClear(floor) -> { Tokens = 300 x floor, Gems = {3,4,5,6,8,10,12,15,18,20,25,30}[floor] }  (totals 23,400 / 156)
BattleCatalog.DungeonChest(floor, seed) -> { Kind = "Cash"|"Tokens"|"Gems", Amount }   (floors 1-2: Cash 70% / Tokens 30%, never Gems: a 1.5-minute
  floor-1 farm would be ~10 Gems/h; floor >= 3: Cash 30 s of income 60%, Tokens 20 + 10f 30%, Gems 2 8%, Gems 5 2%)
Validate: 12 floors with existing elements, power never drops, rewards grow, first-clear tables complete, every band has pets.
```
Measured (`dungeon_proto.lua` on the Phase 4 engine): floor 1 cleared by every one of the 12 rollable level-1 Commons / Uncommons alone (100%,
0.2-1.6 min); the stage ladder S1 F2, S2 F3, S3-4 F4, S5 F5, S6 F6, S7 F7, S8 F8, S9 F9, S10 F11; a 4-party gains about one floor. The
Phase 5 fighter engine changes fight lengths, not the ladder's shape: `sim_battle only=dungeon` re-measures it in W1 and moves `FirstPower` /
`Growth` / `RoomMult` only.

#### 5.2 Loot (paid by DungeonService, once per room per QUALIFYING member = `result.Fighters` of 4.6: >= 5% of the party's damage in that room, any
damage solo; an AFK member or an idle alt gets nothing, the Phase 3 zero-damage-helper rule; C2)
| Reward | Formula | Why |
|---|---|---|
| Cash | `max(20 + 10 x floor, IncomePerSecond(player) x RoomSeconds)`, `RoomSeconds = {3, 4, 5, 12}` by room | the Ring's rule: seconds of your OWN garden; a floor pays 7-17% of the garden time it takes |
| Tokens | wave rooms `floor((6 + 4f) x waves / 2)`, boss room `(6 + 4f) x 2` (floor 10 run = 253); x2 under Double Rewards | roulettes keep their pace |
| XP per team pet | `(25 + 10f) x waves` (the boss room counts 4) via `PetCareService.GrantXp(player, key, xp, "Dungeon")` (floor 10 = 1,375 per run) | below the Ring on purpose: the Ring stays the free XP machine |
| Loss | the room that ends a run pays a third of its XP when `BattleCatalog.RealLoss(result)` (>= 20 s or >= 20% damage; never Quit / leave / disconnect / shutdown) | the Phase 4 rule |
| Floor cleared | `DungeonFirstClear(floor)` once per player per floor, decided INSIDE `DataService.MutateDungeon` (paid only when it returned "first"); needs the member to be a qualifying fighter of the BOSS room AND of at least one earlier room of the same run (`Member.Qualified[room]`) | once per server session; two servers can pay it twice only when the same player clears the same floor on both before either saved (no session lock, DataService:69; a narrow window, and Gems stay under the 135/h clamp), see 9.1 |
| Boss chest | one per member in the treasure alcove (E, `DungeonRequest("Chest")`), rolled server-side from seed + userId, once; an unopened chest is opened for its owner (same mark) when the 45 s exit fires | 0.26 gems expected: negligible; Gems kinds only from floor 3 |
Economy: `sim_tycoon.py --dungeon 0.1` (a run every 10 min) +~8% Cash; combined with `--ring 0.08` it must print ALL TARGETS MET (C10).

#### 5.3 Portal, party, run (player flow)
* `Portal_Dungeon` = `DungeonBuilder.BuildPortal(gatesFolder, LobbyInfo.GateSites.Dungeon)`: `WorldStyle.BuildGate` (Purple, Glyph "torch",
  title "The Dungeon", info "Rooms, waves and a boss. Solo or up to 4 friends", pill "Floors cleared here: Alex - 7" from the attribute
  `DungeonBoard`) + two torches, <= 120 parts; prompt `DungeonPrompt` with `OpenPanel = "Dungeon"` (handled in ArenaController's
  `onPromptTriggered` next to "Ring", which calls `DungeonController.Open`). Returns `DungeonInfo = { Portal, Pad, PromptPart, ReturnCFrame }`.
* Window (DungeonController, NeonKit side panel 640x860 Purple): a 12-tile floor list (element icon, name, "Cleared" / "Recommended power
  512" / "Clear floor 6 first") and the party panel: SOLO (start now) or PARTY (Create; open parties "Ava's party - Floor 3 - 2/4 - JOIN";
  members with READY ticks and team power; a leader KICK (x) per member (`DungeonRequest("Kick", userId)`, leader only; the kicked member toasts "You
  were removed from the party"); the leader's START enabled when all are ready and within 40 studs; START with unready members starts a
  `ReadyTimeout 30` s clock (side card "Starting in 30 - press READY") after which the unready are dropped and the run starts; LEAVE). Countdown side card
  "Dungeon in 5...". Entry checks (server, in order, each a toast): a pet owned ("You need a pet"); `TeamSpec` (team -> equipped -> best
  owned, training skipped); `canBattle`; within 30 studs; loaded and not provisional; the floor unlocked for the LEADER (`Dungeon.Best >=
  floor - 1`; members are carried and credited: `Best = max(Best, floor)`); no home needed.
* Inside: Entrance Hall (`HallSeconds` 10, the floor banner) -> Room 1 (the fight starts when the first member crosses the `Threshold`; the
  others are placed at the `Entrance`) -> waves (next wave 1.5 s after the last enemy falls; side card "Wave 2 / 3") -> cleared: loot card
  "+$340 +24 tokens +70 XP", bars open after `Intermission` 2 s -> corridor (`DoorTime` 12 s, then stragglers are placed at the next
  entrance) -> rooms 2, 3 -> Boss Room (escort at 50% HP) -> Treasure alcove (chests, exit portal "Back to the plaza", auto after 45 s: unopened chests are opened for their owners first).
  Pets heal fully between rooms (a fresh encounter per room, C1); a member with 3 pets down is Downed for that room (spectates from the edge,
  back at full next room); everybody down = the room is lost = the run ends (loot paid stays): "Floor 3: the Frozen Crypt got you in room 3.
  Train your team and try again!", back at the portal after `RETURN_DELAY` 4. Per-room time limit 120 s (180 on floor 1) = a wipe.
* Late join while `Run.State` is Hall or Corridor and `Run.Room <= Dungeon.LateJoinLastRoom 2` (joins close when room 3 starts; "in room 2 - JOIN"); during a fight the join is queued <= 20 s
  ("Joining when the room is cleared"); earlier rooms pay the joiner nothing. LEAVE (two presses, `DungeonRequest("Quit")`), a disconnect, a
  respawn elsewhere, an obby match or the room leash (80 studs from the room centre, 2 strikes) remove that member only (`RemoveEncounterTeam`,
  return teleport, `Runs + 1`); the last one out ends the run. A shutdown ends every run void (loot paid stays).

#### 5.4 DungeonService (`src/server/Services/DungeonService.lua`, new, Fable)
`DungeonService.Init(deps)` (deps `{ DataService, PetCareService, TycoonService, BattleService, DungeonBuilder, DungeonInfo, LobbyInfo }`: wires
`DungeonRequest`, starts the 0.5 s loop, and LAST calls `BattleService.SetRunProvider({ KeysInRun = DungeonService.KeysInRun, GetRun =
DungeonService.GetRun })` (C16)). State in one `St`: `parties[leaderUserId]`, `partyOf[Player]`, `runs[runId]`, `runOf[Player]`,
`pocketBusy[index]` (`MAX_DUNGEONS = 8` by default, 12 only after the owner's MicroProfiler check (judge M6): the 9th run gets "The dungeon is full,
try again in a minute").
```
Party = { Leader, Floor, Members = { [userId] = { Player, Ready, Keys } }, Order, Countdown, Created, Run }
Run = { Id = "D12", Floor, Seed, Pocket = { Index, Origin, Model }, State = "Hall"|"Fight"|"Corridor"|"Treasure"|"Ending", Room 1..4, Wave,
        Members = { [userId] = Member }, Order, Battle = battleId | nil, Rooms = { [room] = RoomInfo }, Paid = { [room] = { [userId] = true } },
        Loot = { [userId] = { Cash, Tokens, Xp, Gems } }, Started, Joinable, Chests = { [userId] = "Closed"|"Opened" }, Cleared }
Member = { Player, Keys (fixed at the join), JoinedRoom, Downed, Left, Spec, Qualified = { [room] = true } (a qualifying fighter of that room) }
RoomInfo = { Index, Kind, Model, Zone (NC_BattleZone), Entrance (CFrame), Threshold (part), Door = { Bars } }
API: CreateParty(player, floor), JoinParty(player, leaderUserId), LeaveParty(player), SetReady(player, bool), SetFloor(player, floor) (leader),
  KickMember(leader, userId) (leader; never during a run),
  StartRun(party) -> ok, runId | reason, StartSolo(player, floor), Quit(player), OpenChest(player), GetRun(player) -> { RunId, Floor, Room,
  State, Wave } | nil, KeysInRun(player) -> {[key] = true}, ListParties(), Shutdown() (BindToClose: every run void)
Signals: RunEnded(runId, result = { Floor, Cleared, Members, Winners, Loot }) AFTER the payments; FloorCleared(player, floor)
```
Run machinery (one `Dg` helper table): `Dg.begin(party)` reserves the pocket index BEFORE any yield, `DungeonBuilder.BuildRun(index, floor,
seed)`, `Member.Spec = BattleService.TeamSpec(player, keys)`, writes `InBattle = run.Id` for every member BEFORE the teleport (followers
parked; GoHome / portals / obby refused as for a ring run), teleports to the hall pads, `DungeonState("Run")`. `Dg.enterRoom(run, room)`:
build room `room + 1` + its corridor now, destroy room `room - 1`; place members at the Entrance; `run.Battle = BattleService.OpenEncounter({
Mode = "Dungeon", Zone = RoomInfo.Zone, Seed, TimeLimit, Teams, Extra, KeepInBattle = true, OnEnd = Dg.onRoomEnd, OnWave = Dg.onWave,
OnBossHp = Dg.onBossHp, OnDown, OnLeave })`; `SpawnWave(battleId, DungeonWave(...).Pets, { Wave = 1 })`. `Dg.onWave`: side card, next wave
after 1.5 s; after the last wave `FinishEncounter(battleId, "Cleared")`; boss room: the escort spawns at `EscortAt`, cleared when boss AND escort
are down. `Dg.onRoomEnd(run, result)`: Cleared -> `Member.Qualified[room] = true` and `Dg.payRoom` for every `result.Fighters` member (`run.Paid[room][uid] = true` written BEFORE
`DataService.AddCash / AddTokens / PetCareService.GrantXp`, all non-yielding), `DungeonState("Loot")`, bars open, `State = "Corridor"`; room
4 -> `Dg.clearFloor` (for every member with `Qualified[4]` and some `Qualified[r < 4]`: `MutateDungeon` raises `Best`, sets `Cleared[floor]`, `Clears +
1`, returns first-clear -> `DungeonFirstClear` paid via `AddTokens` / `AddGems`; the others only get `Best = max(Best, floor)`), chests, `State = "Treasure"`; Wipe / Timeout -> the loss third, `Dg.endRun(run, false, reason)`. `Dg.endRun`:
`State = "Ending"`, `DungeonState("End")`, `MutateDungeon` `Runs + 1`, return teleport to `DungeonInfo.ReturnCFrame` after 4 s, `InBattle`
released, `DungeonBuilder.FreeRun(index)`, the party record removed, `RunEnded` once. `Dg.removeMember(run, player, why)` as in 5.3.
**Watchdog** (the 0.5 s loop; judge M3): a run in "Fight" whose `run.Battle` is no longer running (`BattleService.GetBattle(id) == nil`) for more
than 15 s, or any run older than `Dungeon.RunMaxSeconds`, gets `Dg.endRun(run, false, "Error")`. `Dg.endRun` is idempotent (`run.State == "Ending"`
returns at once), runs each of its steps in its own pcall, and ALWAYS releases InBattle for every member, frees the pocket and fires `RunEnded`
once, even when an earlier step errored. Every `Dg.on*` callback is pcall-ed by BattleService (4.6) and starts with `if run.State ~= "Fight" then
return end`. Rate
limits: `DungeonRequest` burst 6 refill 2 + per-action cooldowns (Create 2, Join 1, Ready 0.3, SetFloor 0.5, Start 1.5, Quit 1, Chest 0.5,
Open 0.5, Kick 1); ladder type -> range (floor 1..12 whole, userId whole) -> permission (leader-only actions; a member of THAT party; not in a run
for Create / Join) -> plausibility (30 / 40 studs, `canBattle`, floor unlocked, pocket free). Refusals: side toasts, throttled.

#### 5.5 DungeonBuilder (`src/server/Services/DungeonBuilder.lua`, new; art per image 22, rules of 6.4)
Mood: Slate / Cobblestone brick walls, Sandstone floors, wall torches (bracket + Neon flame + one `Fire` + `PointLight` range 18 amber),
puddles, moss, barrels, crates, chains, pillars, arches, a portcullis, stairs to a dais, a throne under a purple carpet; caves with rock,
stalagmites, a turquoise pool + waterfall wall; bridges over a dark chasm (an invisible floor below); a dark stone ceiling 16 studs up.
* `DungeonBuilder.Build(lobbyInfo) -> DungeonInfo` (W3; the portal + the template folder); templates built ONCE by Voxel into
  `ServerStorage.DungeonTemplates` (`Hall_1..3`, `Cellar_1..3`, `Cave_1..3`, `Bridge_1..2`, `Throne_1`, `Entrance_1`, `Corridor_Straight / Left /
  Right`, `Treasure_1`) in a `task.spawn` after boot with `task.wait()` between sets (a run needing a missing set builds it synchronously,
  ~0.1 s). Budgets per template: wave room <= **320**, boss room <= **420**, hall <= 140, corridor <= 70, treasure <= 90 (~4,000 total).
  Each template carries `Accent` attributes on <= 40 recolourable parts and attachments `Entrance`, `Exit`, `Threshold`, `Spawn1..4`, `Dais`.
* `BuildRun(index, floor, seed) -> Pocket` (origin `Vector3.new(9000 + col x 600, 160, 9000 + row x 600)`, holder `workspace.Dungeons.
  Dungeon_<index>`; rooms chained along a seeded corridor path, never overlapping), `PlaceRoom(pocket, room)` (clone, recolour Accent parts
  to `PetCatalog.Elements[el].Color`, add the `NC_BattleZone` part (`Mode "Dungeon"`, `ZoneId "Room"`, `Index`, `Room`), the Threshold, the
  bars as two toggled states (CanCollide + Transparency; the client plays the slide on the `DoorOpen` attribute); floor 1 brightest, no abyss),
  `FreeRun(index)` (holder destroyed, zones gone, the `Dungeons` folder removed with the last run). Live budget per run: hall + room k +
  corridor + room k+1 <= **950** parts; 8 runs <= 7.6K (12 = 11.4K only after the owner's check). A room is assembled under `ServerStorage` and
  parented into the pocket in ONE step (one replication burst, never part by part). StreamingEnabled is OFF in this game (`default.project.json`;
  LightingService:140 leaves it alone), so there is NO `RequestStreamAroundAsync` step: every client replicates every live run, which is why the
  client-total row of 10.3 exists (judge M6).
  Renderer: `render_model.py dungeon[:<kind>[:<variant>]]`, `dungeon:run[:<floor>]`, `gates`.

#### 5.6 Client (DungeonController new, W4; BattleController lines in W3)
`DungeonState` payloads (5.7) drive the window, the run side cards ("Floor 3 - Room 2 / 4", wave pips, loot ticker, member chips, LEAVE,
"Door opens in 7", the chest prompt), the result card; optimistic READY reverted by the next Lobby state; `FIRE_GAP 0.3` between requests.
Lighting: `LightingStack.Push("Dungeon", preset, 1)` on Run / `Pop("Dungeon", 1)` on End or leaving the pocket (preset: ColorCorrection
Brightness -0.12 Contrast 0.1 warm-grey tint, darker Ambient / OutdoorAmbient, Atmosphere density +0.15). BattleController: `Start.Dungeon`
read like `Start.Ring`, mode text "DUNGEON - Floor 3 - Room 2", `wild` chips with the floor's element stripe, the boss chip crowned, no result
card for a room (the dungeon's loot card instead). Wild look: `PetBuilder.Build(def, { Wild = { Tint, Eyes } })` (pets W3: body x0.75
brightness -20% saturation, Neon eyes in the element colour); enemies Low, <= 5 on screen.

#### 5.7 Remotes (Config, lead W0)
* `DungeonRequest(action, a, b)` c->s: "Open", "Create" (floor), "Join" (leaderUserId), "Leave", "Ready" (bool), "SetFloor" (floor), "Start",
  "Solo" (floor), "Quit", "Chest", "Kick" (userId; leader only, party state only).
* `DungeonState(kind, payload)` s->c: "Lobby" `{ Parties = { {Leader, LeaderName, Floor, Count, Max = 4, Open, InRun, Room} }, Mine = { Leader,
  Floor, Members = { {UserId, Name, Ready, Power} }, Countdown } | nil, Record = { Best, Cleared, Runs, Clears } }` (<= 1/s per client);
  "Run" `{ RunId, Floor, Name, Element, Room, RoomCount = 4, Wave, Waves, State, Members = { {UserId, Name, Downed, Left} }, Joinable }` (<= 1 KB);
  "Loot" `{ Room, Cash, Tokens, Xp, LevelUps }`; "Chest" `{ Kind, Amount }`; "End" `{ Floor, Cleared, Reason, Totals = { Cash, Tokens, Xp, Gems },
  FirstClear | nil, Unlocked | nil, NewBest }`. `OpenPanel("Dungeon", { Floor })` from the server (tutorial, prompt).

### 6. World, gates, obby, art, sky, GUI (world design; worldstyle W1, worldlobby W2, neonkit W2, ui owners W3-W4)

#### 6.1 `Config.Lobby` (lead W0) and the Gate Court (LobbyBuilder, W2)
```
Config.Lobby = { Origin = Vector3.new(0, 300, 0), PlazaRadius = 150 (was 110), GateArcRadius = 118 (replaces PortalRingRadius 88),
  GateStep = 14.5 (degrees: 29.8 studs), GateFacing = 90 (+Z; the spawn looks this way), SpotRingRadius = 340 (was 300: spoke bridges stay
  130 studs), SpotCount = 16, PlotSize = 72 (unchanged, read by TycoonCatalog), ShopOffset = Vector3.new(0, 0, -196) (was -150), KillY = 100 }
```
Plaza (plaza-local, 0 = +X, 90 = +Z): spawn court r 0..34 (Slate tiles, Marble ring, a medallion with 6 arrows in the gate colours); the
grand avenue to the court along 90 degrees (20 wide, Cobblestone, Brick kerbs, lamp posts every 16 studs, `Shadows = false`); the **Gate
Court** sector 48..132 degrees, r 96..146, with a terrace (r 126..146), hedges, banners, two obelisks; gates left -> right **Home 53.75, Obby
68.25, Dungeon 82.75, Ring 97.25, Arena 111.75, Altar 126.25** degrees, gate centre r 118, pad centre r 104, every gate faces the spawn; the
shop boardwalk at 270 degrees; lawns at 0 / 180 with the 6 NPC spots on r 62..80 (>= 12 studs from any path centre); spokes unchanged
(Cobblestone). Derived: `G.GardenR = 221`, the altar site, the arena distance (`SpotRingRadius + 40`). The six gates live in a Folder
`workspace.NimbusLobby.Gates` (`LobbyInfo.GatesFolder`), built by their owners in `Build` order (C4). Removed: the portal promenade, the 5
difficulty portals, the Trial / Ring patches, the rainbow arch (the welcome sign moves onto a stone arch over the avenue at r 40), the
difficulty bunting; `L.PortalAngles / PortalStep / MidAngle / PromFrom / PromTo / TrialAngle / RingAngle`, `G.TrialHalf / PromIn / PromOut`,
`buildPortal / fallbackPortal / portalTag / gateBoxes / gatePalette / buildArch / RAINBOW / MAX_STARS`.
```
LobbyInfo.GateSites = { Home, Obby, Dungeon, Ring, Arena, Altar }  -- ground CFrame of each gate centre, LookVector toward the plaza centre
LobbyInfo.RingSite = GateSites.Ring;  LobbyInfo.DungeonSite = GateSites.Dungeon;  LobbyInfo.GatesFolder = workspace.NimbusLobby.Gates
LobbyInfo.Portals = { Obby = PortalInfo }   (PortalInfo + PromptPart);  LobbyInfo.Gates = { Home = { Model, Pad, PromptPart }, Altar = {...}, Obby = {...} }
LobbyInfo.ArenaAngle / ArenaDock / ArenaBridgeWidth kept;  LobbyInfo.TrialSite DELETED;  NimbusLobby.PartCount is written by Main.server AFTER DungeonBuilder.Build (the last gate builder; # of BasePart descendants), NOT by LobbyBuilder (m3)
```

#### 6.2 `shared/WorldStyle.lua` (new, worldstyle W1) and `GateService` (new, worldlobby W2)
```
WorldStyle.BuildGate(parent, siteCFrame, spec) -> model, pad, promptPart
  spec = { Id, Title, Info, Color (Theme.Neon.*), Glyph = "house"|"cloud"|"torch"|"crown"|"swords"|"bolt", Pad = bool, Name = "Portal_<Id>" }
  22 wide x 8 deep x 26 tall: two Marble columns on Slate plinths, a Slate lintel with a Marble keystone, a 0.4-stud Neon inlay ring, a Neon disc
  (Transparency 0.35) + a ForceField disc, a 6x6 voxel emblem (<= 30 parts, one per Glyph, built once and cloned); Pad = a 14 x 0.6 x 14 Slate
  slab with a Marble border and a Neon glyph (the PortalService zone part sits on it) else a 10 x 0.3 x 6 step; the pixel BillboardGui tag
  (title 28 px, info 20 px, pill 18 px, stroke, MaxDistance 120, LightInfluence 0) 27 studs up; one PointLight (Range 14, Brightness 1.2,
  Shadows = false) + sparkles (Rate 6); <= 90 parts, owners add <= 30 (crown, torches): every gate <= 120.
WorldStyle.Palette, WorldStyle.Materials, WorldStyle.Plinth(parent, cf, size, mat), WorldStyle.Kerb(...), WorldStyle.Chamfer(...)   (on Voxel.Box)
```
Gates: Home (LobbyBuilder, Yellow, "house", no pad; `HomeGatePrompt` "Go home" / "My Home"), Obby (LobbyBuilder, Blue, "cloud", pad +
`ObbyPrompt`), Dungeon (DungeonBuilder, 5.3), Ring (ArenaBuilder, Gold, "crown", `RingPrompt`, `ArenaInfo.RingPortal` = its pad), Arena
(ArenaBuilder, Red, "swords", `ArenaPortalPrompt` -> `ArenaInfo.Spawn`; the bridge stays; the forum `Return` gate is always built and lands
in front of `Portal_Arena`, `ArenaInfo.LobbyCFrame`), Altar (LobbyBuilder, Cyan, "bolt", `AltarGatePrompt` "Travel" / "Storm Altar").
`GateService.Init(lobbyInfo, { SpotService, PortalService, StormAltar })`: prompts on `Gates.Home.PromptPart` / `Gates.Altar.PromptPart`
(MaxActivationDistance 12, HoldDuration 0); on trigger: the prompt is one of the two; alive; `InMatch` false; `InBattle` nil; `PortalService.
IsLocked(player)` false; within MaxActivationDistance + 4; 1.5 s cooldown; Home -> `SpotService.Teleport(player)` (no plot -> a free gate +
"Press E at the gate to claim this home!"), Altar -> `StormAltar.GetLanding()` (new: a CFrame on the island deck at the bridge end, 3 studs up,
facing the altar); `GateService.Teleported:Fire(player, "Home"|"Altar")`. Main.server: after `SpotService.Init` and `PortalService.Init`.

#### 6.3 One obby portal (lead W0 `shared/ObbyLevels.lua`; worldlobby W2 PortalService; dungeonclient W4 `ObbyController`)
```
ObbyLevels.List() -> { "Easy", "Medium", "Hard", "Extreme", "Saint" }   (Config.Difficulties order)
ObbyLevels.HighestUnlocked(bestTimes) -> 1..5   = min(5, 1 + max index i with bestTimes[Difficulties[i].Id] a positive number); 1 when none
ObbyLevels.IsUnlocked(bestTimes, levelId) -> bool;  ObbyLevels.NextAfter(levelId) -> levelId | nil
```
No migration: `Stats.BestTimes` has every win since v2; a player who beat Medium has Hard on the first Phase 5 join; the highest beaten level
decides; no win = Easy only (the approved rule). PortalService: ONE party slot keyed `"Obby"` (`lobbyInfo.Portals.Obby`; the per-difficulty
loop deleted); `party.Diff` mutable, `party.Leader = party.Players[1]`; remote **`ObbyPick(levelId)`** -> `PortalService.PickLevel(player,
levelId)`: string <= 16 chars, `Config.GetDifficulty`, 4/s burst 4, profile loaded, `IsUnlocked(profile.Stats.BestTimes, levelId)` (server
copy) -> `player:SetAttribute(Config.Attr.ObbyLevel, levelId)`; a LEADER's pick before launch sets `party.Diff`, `party.Deadline = max(Deadline,
now + 8)`, toast "Level: Hard" to the members; refusal "Beat Medium to unlock Hard"; junk dropped silently. Party creation: level = the
`ObbyLevel` attribute if still unlocked, else the player's highest; anyone may JOIN whatever the level; launch `MatchService.StartMatch(party.
Diff.Id, players)` unchanged. `ObbyPrompt` on `PortalInfo.PromptPart` ("Pick level" / "Sky Obby", attribute `OpenPanel = "Obby"`) created by
PortalService. `PartyState` + `Level`, `Stars`, `LeaderUserId`, `PortalId = "Obby"`; model attribute `PartyLevel`. `ObbyController` (side
panel 560x640 Blue): 5 level cards (stars, name, blurb, "Best 3:42", "+N tokens on a win", LOCKED "Beat Medium to unlock" / UNLOCKED /
PICKED), footer "Step on the pad to start" or "Party on the pad: Hard 2/4 - step on to join"; opens on the prompt, `OpenPanel("Obby")`, the
party panel's CHANGE chip (leader); closes > 40 studs away or on the pad; unlock toast "Extreme unlocked! Pick it at the Obby portal."
after a `MatchResult` that raised `HighestUnlocked`. HudController party panel: a "Hard ★★★" row + CHANGE chip (leader).

#### 6.4 Art rules (every builder; `p5world_style` checks them), lighting, `LightingStack`
1. Materials from `WorldStyle.Materials` only (Slate, Cobblestone, Brick, Marble, WoodPlanks, Wood, Grass, LeafyGrass, Sand, ClayRoofTiles /
   RoofShingles, Metal, Glass, Neon inlays, Fabric, the voxel cloud palette); no SmoothPlastic on a world part with a side > 2 studs (pets,
   tokens, voxel clouds exempt by tag). 2. Large faces (> 16 studs^2): saturation <= 0.45, value 0.35..0.9; saturated colours only on pieces
   <= 8 studs^3 or Neon inlays <= 0.5 thick; one accent hue per structure; +-6 RGB jitter per tile. 3. Plinth + body + cap on every structure;
   kerbs 0.4 + a 0.3 lip on platform edges. 4. Chamfers on exposed corners >= 4 studs tall. 5. Ground tiles 4..6 studs, +-0.05 height
   alternation. 6. A detail every ~12 studs of walkway, +-20% scale / 15-degree yaw variants, cloned. 7. Warm lanterns (255, 214, 170),
   Brightness <= 1.5, Range <= 16; <= 12 shadow-casting lights in the lobby. 8. Budgets after the greedy merge: lobby <= **8000** (incl. the
   six gates), each gate <= 120, arena <= **2800**, a max-tier plot <= 950 (3.6); parts < 4 studs `CastShadow = false`. 9. Clouds stay voxel,
   shaded for the sky (tops 250,244,252; sides 226,214,240; undersides 186,172,222). 10. World text rule unchanged. Pure decor models are
   tagged `NC_Detail` (the Low graphics setting hides them). Rebuild order: LightingService (W1) -> LobbyBuilder (W2) -> HomeBuilder (W2, every station incl.
   House / Vault / Fusion / Arena Gate) -> ArenaBuilder art pass (**arenaart, W4**, not optional: island, colosseum, stands, Ring pocket in these
   rules, budget 2800, renders `arena`, `arena:ring`, `pocket:ring` >= 3 rounds at the W4 gate). CourseBuilder and the StormAltar island keep their
   voxel-cloud look ON PURPOSE (the sky world is the game's identity; the player summary says so).
* `default.project.json` (lead W0): `Lighting.$properties.Technology = "Future"` (one-line revert) and `"ReplicatedFirst": { "$className":
  "ReplicatedFirst", "First": { "$path": "src/first" } }`.
* `LightingService.Look = { Custom = {...}, Fallback = {...} }` (replaces the Phase 4 `LOOK`); `Init()` picks Custom when all six
  `Config.Sky.Faces` are set, else Fallback: ClockTime 14.5 / 16.6, Brightness 2.2 / 2.6, Exposure 0 / +0.1, Ambient (112,104,140) /
  (118,104,140), OutdoorAmbient (150,138,176) / (160,140,180), ColorShift_Top (70,46,40) / (80,50,40), _Bottom (30,20,60) / (34,22,64),
  EnvironmentDiffuse 0.7 / 0.6, Specular 0.45 / 0.35, Atmosphere Density 0.32 / 0.36, Offset 0.2, Color (226,188,232) / (220,176,232), Decay
  (150,120,210) / (126,104,214), Glare 0.15 / 0.4, Haze 1.2 / 2.0, Sky StarCount 0 / 3000, SunSize 11 / 14, Clouds Cover 0.45 / 0.62, Density
  0.55 / 0.7, Color (255,222,242) / (255,206,236); shared Bloom 0.25 / 24 / 1.35, ColorCorrection Contrast 0.12 Saturation 0.06 Tint
  (255,246,252), SunRays 0.04 / 0.06. `Config.Sky = { Faces = { Bk = "", Dn = "", Ft = "", Lf = "", Rt = "", Up = "" } }`.
* `src/client/LightingStack.lua` (new, worldstyle W1): `Push(id, preset, seconds)` (preset = `{ Lighting, Atmosphere, ColorCorrection, Bloom,
  SunRays, Clouds }`, tweened), `Pop(id, seconds)` (restores what is under it; unknown id = no-op), `Top()`. The first Push snapshots the
  replicated values as the base; the effective value = the topmost preset that sets it. Users: DungeonController ("Dungeon"),
  GraphicsQuality ("GfxLow"). Nothing else on the client writes Lighting.

#### 6.5 The sky (`blender/sky/render_sky.py` + `branding/sky/*.png`, worldstyle W1)
A Cycles WORLD shader only (no geometry): a colour ramp by elevation (pink haze -> light blue horizon -> lavender -> violet -> deep blue
zenith, the 23.png palette), clouds = fBm noise on the view direction squashed x1.8 in a band of -32..+32 degrees, lit from above, pinker toward
+X; stars = Voronoi cells, 14% lit, above 10 degrees. Every face samples ONE continuous function of direction (side seams measured 0.42..0.68 vs
0.53 between inner columns: invisible); Up / Dn carry no clouds, so their rotation cannot show a seam. Convention: Ft = -Z, Bk = +Z, Rt = +X,
Lf = -X. Output 6 x 1024 px PNG + a preview cross, committed so the owner never runs Blender. README owner checklist (10.6, step 2): Asset
Manager -> Bulk Import the 6 PNGs -> Copy ID -> paste into `Config.Sky.Faces` (`Ft = "rbxassetid://..."`); Lf / Rt swapped = swap two ids.
The builder may add one larger noise octave for rounder clouds (one node), nothing else.

#### 6.6 The Neon kit and the window rule (neonkit W2: Theme, NeonKit, CloudUI, Hud, Hotbar, Notify; every window owner adopts it after)
```
Theme.Neon = { Orange (255,150,48), Blue (64,170,255), Purple (176,104,255), Red (255,76,100), Green (72,224,120), Yellow (255,210,64),
  Cyan (64,226,236), Pink (255,112,200), Gold (255,196,64), Grey (150,166,204) }
Theme.Category = { Pets Orange, Items Blue, Team Red, Index Purple, Shop Green, Home Yellow, Stats Cyan, Settings Grey, Obby Blue, Dungeon Purple,
  Ring Gold, Arena Red, Altar Cyan, Care Green, Fusion Pink, Battle Red };  Theme.NeonColor(categoryOrColorName) -> Color3
Theme.Colors.PanelTop (26,32,72), PanelBottom (12,15,38), PanelInk (8,10,28)  (old keys kept)
Fonts: Title / Button / Toast -> GothamBlack; Display stays FredokaOne, Accent LuckiestGuy, Body / Label BuilderSansBold; sizes unchanged
NeonKit.Card(props) -> { Root, Body, SetColor, SetGlow }   -- Size, Position, Color, Corner 14, Glow (outer frame +5 px, 5 px stroke at 0.62),
  Floor (the colour fading up from the bottom 55%), Fill {PanelTop, PanelBottom}, a 3 px neon UIStroke, a 2 px white sheen line
NeonKit.Tile(props) -> { Root, Icon, Label, SetBadge }   -- the 21.png tile: Card + Icon on an Orb (0.46 x size) + GothamBlack label (0.2 x size, 2.5 px stroke)
NeonKit.Orb(parent, color, size);  NeonKit.Icon(parent, id, size)  -- emoji glyph; Config.Icons[id] = "rbxassetid://n" switches to an ImageLabel
NeonKit.Pill(props) -> { Root, SetText };  NeonKit.Button(props) -> TextButton (Primary | Outline; hover 1.04 / press 0.95; disabled desaturated)
NeonKit.SideRect(prefW, prefH, minW, minH) -> { x, y, w, h, scale, mode = "Side" | "Sheet" };  NeonKit.Dock(holder, uiScale, prefW, prefH, minW, minH)
```
Window rule (`SideRect`, f = `Theme.ScreenFactor()`, margin 12 f, inset 58): landscape = docked RIGHT, `maxW = 0.44 W`, scale f (or
`max(0.85 desktop / 0.8 touch, maxW / prefW)`), vertically centred, left edge >= 0.56 W - m; portrait = a bottom SHEET, scale 0.8, w = W - 2m,
h <= 0.56 H (the top 44% clear); small confirms (Evolve, prestige, odds, purchase) centred <= 30% of the area; HUD popups (results, NPC
dialog, party panel, tutorial) <= 25% of a phone screen and never in the centre third; NO full-screen dimming (the five `Backdrop` buttons,
`setBackdrop` / `H.setBackdrop` / `hideBackdropNow`, `MenuController.fitBox`, `K.BUMPS`, the four `fitWindow`s and CloudUI's cloud bumps are
deleted); one side panel at a time; close = X / Esc / B / another window / walking away. While a panel is open the hotbar re-centres
(`HotbarController.SetAvoidRight(x)`). Preferred sizes (design px): Inventory / Pets / Shop / Home / Team 820x900, Stats 640x760, Index 860x900,
Care 600x820, Arena / Ring / Dungeon 640x860, Fusion 760x860, Obby 560x640, Settings 520x640 (content uses the existing narrow / tall
layouts). Measured (`coverage.py`): Pets panel + HUD 40 / 45 / 56 / 48% at 1920x1080 / 1280x720 / 390x844 / 844x390 (today 48 / - / 83 / 79).
Per file: `CloudUI.Panel` = a Neon card (accent = `props.Accent` or the category), GothamBlack 34 title + neon underline + red X; `Button /
IconButton / Slot / Tabs / Bar / Pill` reskinned, API unchanged; `MenuController` left column -> a 2x3 tile grid (Pets, Items, Team, Index, Shop,
Home: 84 / 66 / 54 px) + a small row (Stats, Settings gear), names `MenuButton_<Id>` kept, `fitBox` -> `NeonKit.Dock` (careui W3);
`HudController`: currency pills bottom-left (landscape phone: top band right of Roblox's buttons, x >= 150), vitals card reskinned, party row +
CHANGE chip, stamina ticks (3.9); `HotbarController` neon slots 64 / 54 / 46 + `SetAvoidRight`; `NotifyController` toasts as neon pills at the
right edge; NPC dialog moves to the side on phones; the results card = one compact card top-right (<= 25%). `IndexController`, `CareController`,
`ArenaController`, `FusionController`, `DungeonController`, `ObbyController`, `BattleController` use `NeonKit.Dock` / NeonKit cards (their owners).

### 7. Loading screen, main menu, settings (world design 7-8; menu W3)

#### 7.1 `src/first/LoadingScreen.client.lua` (ReplicatedFirst)
Line 1: `ReplicatedFirst:RemoveDefaultLoadingScreen()`; ScreenGui `NimbusLoading` (DisplayOrder 100, IgnoreGuiInset, ResetOnSpawn false): a
violet gradient (60,50,150) -> (190,110,200), no text until `Shared.Theme` arrives (fonts via Theme roles), then "NIMBUS CLIMB" (GothamBlack;
two lines when W < 700), a Cyan neon bar `min(0.6 W, 640 f) x 26 f`, "Loading the sky... 64%", a tip rotating every 5 s from `UpdateNotes.Tips`,
SKIP after `Config.Loading.SkipAfter = 6` s. Progress = weighted stages, forward only (tween 0.25 s): game loaded 0.30 (`game:IsLoaded()`),
shared modules 0.10 (Config, Theme, Util, Voxel present), lobby replicated 0.30 (`BasePart` descendants of `NimbusLobby` vs its `PartCount`, polled 0.25 s),
assets 0.15 (`ContentProvider:PreloadAsync` of the Sky + the gui), profile 0.15 (the player attribute `ProfileLoaded = true`, written by DataService when the profile is loaded or provisional; never a
PlayerScripts module from ReplicatedFirst (boot order, m13), never the `CloudTokens` attribute).
Finish at 100% or `Config.Loading.MaxSeconds = 25`: attribute `Done = true`; MainMenuController fades it (0.4 s) and destroys it; with the
menu disabled the script fades itself after 2 s. One 0.25 s poll loop, no per-frame work.

#### 7.2 Main menu (BEFORE spawning: the server holds the character until PLAY; the approved decision, judge M7)
* `src/client/UiGate.lua` (new): `UiGate.Played` (signal), `HasPlayed()`, `WaitForPlay(timeout)`, `MarkPlayed()`, `UiGate.ALLOW = { "NimbusLoading",
  "NimbusMainMenu", "NimbusNotify" }`: a DENY-list rule, every OTHER ScreenGui in PlayerGui (now and via `ChildAdded`) is `Enabled = false` until
  played: NimbusHud, NimbusMenu, NimbusHotbar, NimbusTutorial, NimbusTutorialPointer, NimbusArena, NimbusArenaSide, NimbusCare, NimbusDungeon,
  NimbusIndex, NimbusFusion, NimbusNpcDialog, NimbusBattle, NimbusDash, NimbusRun, NimbusDev and any future one.
* `MainMenuController` (new; FIRST in `CONTROLLER_NAMES` after MovementController): until played every ScreenGui not in `UiGate.ALLOW` (now and via
  `PlayerGui.ChildAdded`) is `Enabled = false`; there is NO character yet (below), so nothing to disable; MovementController's binds are inert until
  `UiGate.HasPlayed()` (4.4); camera `Scriptable` orbiting the
  Gate Court (centre = Origin + GateArcRadius at GateFacing; `Config.MainMenu = { Enabled = true, OrbitRadius = 90, OrbitHeight = 38,
  OrbitPeriod = 60 }`; RenderStepped, no allocation). PLAY (Enter / A / tap): fires `MenuPlay` (c->s, no args, rate 1/s), waits for `LocalPlayer.CharacterAdded` (<= 5 s, then proceeds anyway),
  0.35 s fade, camera Custom, guis on, `MarkPlayed()`. Shown once per session. Layout (NeonKit): logo NIMBUS / CLIMB, tag line, PLAY (Primary Green 76 f), SETTINGS (Blue outline),
  UPDATES (Purple outline, "NEW" badge when `UpdateNotes.Latest > Settings.SeenNotes`), a left-to-right dark gradient, version chip.
  TutorialController waits `UiGate.WaitForPlay(600)` before its first panel (TutorialService is event-driven, nothing advances). DevController
  `/menu` reopens it (client-side only: the character stays).
* Server half (**PlayerService.lua**, owner menu W3): Main.server's boot spawn gate (`holdSpawns` / `releaseSpawns`, :138-165) keeps
  `Players.CharacterAutoLoads = false` for the server's life (`releaseSpawns` no longer re-enables it nor loads characters; LightingService:147 drops
  its `CharacterAutoLoads = true` line). `PlayerService.setupPlayer` records `St.waiting[player] = true`; the remote **`MenuPlay`** (first per
  session only, rate 1/s) or a `Config.MainMenu.FallbackSeconds = 90` timer calls `PlayerService.SpawnPlayer(player)` (= one `player:LoadCharacter()`,
  idempotent, skipped when the player left or already has a character); after that first spawn `Humanoid.Died` -> `task.delay(Players.RespawnTime,
  SpawnPlayer)` replaces Roblox's automatic respawn; `PlayerService.HasSpawned(player)`. With `Config.MainMenu.Enabled = false` the character spawns
  at once on PlayerAdded (today's behaviour, and what every existing smoke scenario and the mock get unless a test sets Enabled). DataService still
  loads on PlayerAdded, the tutorial is event-driven, and the plaza never shows an avatar before PLAY (Y13).
* Settings: profile field `Settings = { Music 0..10, Sfx 0..10, Gfx "Auto"|"Low"|"High", Shake bool, SeenNotes int }`, defaults `{ 6, 8,
  "Auto", true, 0 }`, left out of the save while default, always in ProfileSync; per-key defaults on load; the live session's values win on
  merge; the dev reset leaves it alone. Remote **`SettingsSet(key, value)`** (DataService's remote section): 6/s burst 6, key in the 5 names,
  Music / Sfx whole 0..10, Gfx one of 3, Shake boolean, SeenNotes whole 0..1000 and >= stored. API `DataService.GetSettings(player)`,
  `SetSetting(player, key, value) -> ok`; `State.Settings()`, `State.SettingsChanged`. `SettingsPanel` (in MainMenuController, also from the
  Settings gear): Music / Sound sliders (11 steps, -/+), Graphics chips, Camera shake chip; applied locally at once, sent with a 0.4 s debounce.
* `src/client/ClientSettings.lua` (`Get(key)`, `Changed`), `src/client/SoundFx.lua` (`Play(name)` Click / Confirm / Error / Reward / Whoosh at
  Sfx/10; `Music(context)` Lobby / Battle / Dungeon at Music/10, 1 s crossfade; `Config.Audio = { Music = { Lobby = "", Battle = "", Dungeon = "" },
  Sfx = { Click = "", Confirm = "", Error = "", Reward = "", Whoosh = "" } }`: empty = silent, the README tells the owner to paste free Creator
  Store ids; **superseded 2026-10-27 by the original audio**: `Config.Audio.Keys` names the `src/shared/AudioIds.lua` key of every sound
  (written by `tools/upload_assets.py --audio` from `audio/audio.json`), Music / Sfx / Ambient hold the AudioIds numbers, `Volume` the slot
  volumes; SoundFx adds Inhale / Shatter / CrowdCheer / DrumLoop, `SetLayer` (Battle over Dungeon over Lobby) and `Positional`; the ring's
  crowd + drums: `src/client/Controllers/RingAmbience.lua`), `src/client/GraphicsQuality.lua` (Auto: `SavedQualityLevel <= 3` = Low; Low pushes "GfxLow" (Bloom / SunRays / DoF off, Clouds
  Density 0.4), reparents `NC_Detail` models to a local holder, disables their emitters, pauses SkyDragonController; High restores).
* `src/shared/UpdateNotes.lua` (lead W0): `{ Latest = 5, Notes = { { Version = 5, Title = "The Big Sky Update", Lines = {...} }, ... }, Credits =
  { "Game by <owner>", "Built with Claude" }, Tips = { 12 tips } }`; opening UPDATES sends `SettingsSet("SeenNotes", Latest)`.

### 8. Tutorial and NPC tips (ONE owner: tutorial W4; C9). Indices never move: chapter 1 = 1-9, 2 = 10-14, 3 = 15-18, 4 = 19-21.

| # | Id | Change (texts 97-125 bytes, checked by `p5ui_content`) | Target -> CompleteOn |
|---|---|---|---|
| ch.1 `equip` | kept | unchanged | |
| ch.1 `portal` | kept | "Now the fun part! Step on the Obby portal pad - Easy is picked for you. Friends can hop in too." Hint "Stand on the Obby pad" | `{Kind = "Portal", Id = "Obby", Label = "Obby portal"}` (`lobbyPosition` reads `lobby.Portals.Obby`) -> MatchStarted |
| 11 `garden` | text | "Your pets make the money! Build your free Pet Garden, then press E on a pet bed to put a pet in it." | the first empty open bed -> GardenPlaced |
| 12 `coins` | text + target | "Garden pets roam your yard, eat at the Food Bowl and poop Cloud Cash. Only you can scoop it: walk over it!" | the biggest drop (`TycoonService.Drops`) -> CoinsScooped |
| 13 `machine` | text + target | "Build the Berry Farm, then the Food Machine: the farm grows berries and the machine turns them into XP!" | the Farm pad until built, then the Kitchen pad -> Built Kitchen |
| 14 `feed` | text | "Press E at the Food Machine and press Feed: your berries become XP. At level 20 your pet can EVOLVE!" | the machine -> Fed (ChapterEnd +$1,000 once) |
| 15 `team` | text | adds "(a fighter + 2 helpers)" | unchanged |
| 16 `trial` -> **`dungeon`** | id, text, target, event | Title "Into the Dungeon!", "Press E at the Dungeon portal and start Floor 1: the Mossy Cellar. Beat every room, then the boss. Your fighter attacks, your helpers buff!", Hint "Clear Dungeon floor 1" | `{Kind = "Arena", Place = "Dungeon", Label = "Dungeon portal"}` -> `positionOfInfo(deps.DungeonInfo.Pad)` -> **DungeonWon** (`DungeonService.FloorCleared(player, 1)`, or saved `Dungeon.Best >= 1`, or legacy `Battle.TrialCleared[1]`: veterans skip it) |
| 17-18 `arena`, `raid` | kept | unchanged | |
| 20 `ring` | kept | Place "Ring" -> `ArenaInfo.RingPortal` (its pad now in the Gate Court) | unchanged |
TutorialService: `KNOWN_COMPLETE_ON` - `TrialWon` + `DungeonWon`; `trialOneCleared` -> `dungeonOneCleared`; the `BattleEnded` listener loses
`Mode == "Trial"`; `impossible()`: DungeonWon needs `DungeonService.StartSolo`; deps + `DungeonInfo`, `DungeonService`; `homeTarget` learns
the Farm pad and `Drops`; `payChapter` unchanged. TutorialController: `Portal_Obby` by name; waits `UiGate.WaitForPlay(600)` before the first
panel. NpcDialog (<= 125 bytes, no `< > &`, numbers from the catalogs): Mayor Panda 2 "Your garden pets roam your yard, eat at the Food Bowl
and poop Cloud Cash. Only you can scoop it: walk over it!", 3 "Level up your Berry Farm: bigger berries make bigger Cloud Cash, and more
berries for the Food Machine!" (keywords Berry Farm, Food Bowl, Cloud Cash, Berry Basket replace Berry Bush, Carrot Patch, rainbow coins);
Granny Owl 4 "Your farm fills the Berry Basket. Press E at the Food Machine, pick a pet and press Feed: berries become XP!", 5 reads
`EvolutionBonus` ("evolved pets grow 50% faster per level"); Coach Corgi 2 "The Dungeon portal on the plaza has 12 floors of rooms, waves and
bosses. Clear a floor for the first time: big token bonus and Gems!" (keyword "Trial Portal" -> "Dungeon"; `trialCount` -> `floorCount` from
`BattleCatalog.Dungeon.Floors`), 5 "Your team is a fighter and two helpers: ATTACK, ELEMENT, SPECIAL and DASH; tap a helper for its buff!";
Sparky Fox's battle line = the same controls; the p3ui needles (Coach Corgi "Team", "+20 trophies"; Granny Owl "Gems"; Professor Axolotl
"Fusion Machine", "Storm Altar") stay.

### 9. Data: schema, the migration of Phase 4 saves (nobody loses pets, levels, Cash, Gems, Tokens or progress), rollout (data W1 Fable)

`PROFILE_VERSION` stays 2; every change is additive; new data lives in NEW TOP-LEVEL fields or new Home keys (the rollout rule of the Phase 4
contract section 4: a Phase 4 server rebuilds `Battle`, `Teams`, `Tutorial`, `PetLevels` entries and slot values from the keys it knows and
`keepForeign` restores unknown top-level / Home / Stats keys). One helper table `P5` (one new local; DataService is at 158).

#### 9.1 Fields
| Field | Shape | Default | Cross-server merge | Provisional | Dev reset |
|---|---|---|---|---|---|
| `Dungeon` (NEW top) | `{ Best 0..100, Cleared = dense booleans by floor, Runs, Clears }` | `{0, {}, 0, 0}` (left out while default) | Best max, Cleared union, Runs +/- delta, Clears +/- delta EXCEPT the migration's own `Clears = Best` which merges as max (two servers migrating the same save do not double it, m15); `P5.cleanDungeon` (whole numbers, Best >= highest cleared) | `Runs` only (`MutateDungeon` refuses a first clear: "Your save is still loading") | wiped |
| `Berries` (NEW top) | whole number >= 0 | 0 (left out while 0) | +/- delta clamped at 0 (like Food) | `AddBerries` allowed, `SpendBerries` refused | 0 |
| `Settings` (NEW top) | `{ Music, Sfx, Gfx, Shake, SeenNotes }` | the defaults of 7.2 (left out while default); per-key defaults on load | the live session wins (not progress) | allowed | kept |
| `Migrations.P5Dungeon`, `Migrations.P5Home` | true | - | union | set in the same step as the migration | kept |
| `Home.DecorCredit` (NEW Home key) | 0..18 | nil | with Home (per-key replace; a higher Prestige wins the whole Home, which CARRIES it) | - | with Home |
| `Home.LegacyMagnet`, `Home.LegacyMagnetStar` (NEW Home keys) | 1..5, the Prestige it was folded at | nil | with Home; MutateHome's prestige path clears them with LegacySlots / LegacyPrices and NEVER clears DecorCredit | - | with Home |
| `Home.Stations` | the 11 ids; `Press2-4`, `Collector`, `DecorLamps / Flowers / Banners` removed by the fold (removal travels as `false`) | | per-key replace | | |
| `Teams` | 3 keys per preset (4.8); `Slots` 3 | | unchanged | | |
| `Battle.TrialBest / TrialCleared` | kept in saves, sanitised by `P3.cleanBattle`, never written again; read by the migration and the tutorial | | unchanged | | zeroed as today |
| `Food` | converted into berries ONCE by the P5Home step (Snack 200 / Meal 1200 / Feast 6400 each, `Berries.LegacyFood`) and zeroed; never written again (m16) | | delta | | |
| `Stats.BestTimes` | unchanged; read by `ObbyLevels` | | | | |
API: `GetDungeon(player)`, `MutateDungeon(player, fn) -> ok, first` (non-yielding; Best never down; Cleared only grows; `first` = this call set a
new `Cleared[f]`), `GetBerries`, `AddBerries(player, n) -> ok`, `SpendBerries(player, n) -> ok` (check-then-subtract in one step), `GetSettings`,
`SetSetting`, `IsMigrated / MarkMigrated` (exist). State: `State.Dungeon()`, `State.Berries()`, `State.Settings()` + `SettingsChanged`,
`State.PetStage(key)`, `State.BestStage(petId)`, `State.Teams().Slots == 3`. DevService: reset wipes `Dungeon`, `Berries`; `/berries <n>`.
ProfileSync: + `Dungeon` (<= 60 B), `Berries`, `Settings` (~60 B); Teams shrink; a Berries-only change never triggers a sync (C14).

#### 9.2 The one-time Phase 5 migrations (`P5.migrateEntry`, inside the place `P4.migrateEntry` runs: ProfileLoaded / ProfileRebased of a loaded, non-provisional profile; idempotent; one non-yielding step each; a profile another server migrated is left alone)
1. **Teams -> 3** (`P3.cleanPreset`, on every load, no marker needed): a 4-key preset keeps its first 3 keys; the 4th pet stays owned with its
   level and growth; `TeamsChanged` fires once (`p5data_team3`: Cash / Gems / PetLevels / PetGrowth byte-equal before and after).
2. **P5Dungeon**: `Dungeon.Best = min(10, floor(TrialBest / 3))`, `Cleared[f] = true for f <= Best`, `Clears = Best`, `Runs = 0`;
   `Migrations.P5Dungeon = true`. Reason: `TrialCurve` (BattleCatalog:693) grows x1.186 per level, so a floor (x2) is about 4 Trials; `/ 3` rounds DOWN against the player by about one
   floor in the middle (Trial 18 = 257 power maps to floor 6 while floor 7 = 256), so nobody skips a floor they could not win and the under-credited
   first clears are simply earned again (never paid twice); Trial 30 (2000) = floor 10 (2048); Trials 1-2 map to nothing because floor 1 is the
   one-minute tutorial floor (m1).
3. **P5Home** (`TycoonCatalog.FoldLegacy(home, firstTime) -> changed`, pure, called in ONE `MutateHome`; `MarkMigrated("P5Home")` is written in that same
   step and ONLY when the fold actually ran: without `TycoonCatalog.FoldLegacy` the whole step is skipped and retried on the next load, m14):
   (a) Farm: `sum = Press1..Press4` (each clamped 0..10); if any of Press2-4 is present or `firstTime`: `Press1 = min(40, max(sum, the smallest L
   with FARM_FOOD[L] >= the old plant food of Press1-4))` (the food floor runs on `firstTime` only), Press2-4 removed; (b) Magnet: `Collector > 0`
   -> `LegacyMagnet = max(LegacyMagnet or 0, Collector)`, `LegacyMagnetStar = Prestige`, Collector removed (`LegacyMagnetLevel(home)` counts
   while `LegacyMagnetStar == Prestige`, else 0); (c) Decor: `Fence = max(Fence, Flowers, Banners)`, `Fountain = max(Fountain, Lamps)`,
   `DecorCredit += the levels that did not fit`, the three keys removed; (d) Food: `Berries += Snack x 200 + Meal x 1200 + Feast x 6400`
   (`Berries.LegacyFood`) and `Food` zeroed, ignoring the basket cap (m16). No Cash or Gems are paid by any migration; the only berries a migration
   adds are the player's own snacks converted. Toast on the first
   claim: "Your home got simpler! Your 4 plants grew into one Berry Farm and your garden pets now roam your yard. Old snacks count as berries!"
   Proof (`fold_check.py`, 300 Phase 4 homes): Home Level dropped in 0 (rose in 126, median +1, none newly at 40), food per meal never lower,
   income x1.00-1.20, no dead end, pad time <= 1.00 in every tier / star bucket.
4. **Obby** and **Settings**: no migration (derived from `Stats.BestTimes`; per-key defaults). **Evolution**: `PetGrowth[key].Evo` untouched.

#### 9.3 Rollout (Phase 4 and Phase 5 servers alive together; "Publish, then Migrate to Latest Update")
| Situation | What happens | Why it is safe |
|---|---|---|
| A Phase 5 save opened by a Phase 4 server | `Dungeon`, `Berries`, `Settings`, `Migrations.P5*`, `Home.DecorCredit / LegacyMagnet*` come back untouched | `keepForeign` |
| ... its `Press1 = 13` | read as Berry Bush L10 (TycoonCatalog clamps to its MaxLevel, no write) | no crash; Phase 5 folds again on the next load |
| A Phase 4 server sells a Carrot Patch / Magnet / old decor level meanwhile | the next Phase 5 load folds that key too (the level is kept) | `FoldLegacy` is idempotent on the keys present |
| A Phase 4 Prestige on a folded home | `LegacyMagnet` goes stale; `LegacyMagnetStar` makes it inert | no Cash involved |
| A Phase 4 server writes a 4-key preset | the next Phase 5 load keeps 3 | the pet stays owned |
| A Phase 4 Trial clear after the migration | `TrialBest` grows; `Dungeon` is already migrated and not re-derived | a few minutes of a rollout; floors are earned in the dungeon |
| A Phase 4 server pays a Cash feed | Cash spent there, XP written: consistent | Phase 5 never refunds Cash for food |
Fixture tests: the lead freezes `tools/fixtures/DataService_phase4.lua` and `tools/fixtures/sim_tycoon_phase4.py` (byte copies) in W0;
`p5home_rollout` / `p5dgn_migrate` load the frozen module as a second copy against the same mock store (the `p4data_rollout` pattern);
`p4data_rollout` (Phase 3 fixture) keeps running unchanged.

### 10. Config, remotes, attributes, Main wiring, budgets, exploits, deletions (lead W0 unless an owner is named)

#### 10.1 Lead edits in wave 0 (the shared files only the lead touches)
* `Config.Remotes` + `"DungeonRequest"`, `"DungeonState"`, `"ObbyPick"`, `"SettingsSet"`, `"MenuPlay"` (5.7, 6.3, 7.2); comments: `BattleCommand` "Attack /
  Element / Special / Dash / Target / Buff / Swap / Forfeit", `BattleRequest` loses "Trial", `PetCare` "Feed (key)". `Config.Attr` + `InBattle =
  "InBattle"` (C11), `Berries = "Berries"`, `ObbyLevel = "ObbyLevel"`. `Config.Physics` (3.9). `Config.Lobby` (6.1). `Config.Sky`, `Config.Audio`,
  `Config.Icons = {}`, `Config.Loading = { SkipAfter = 6, MaxSeconds = 25 }`, `Config.MainMenu = { Enabled, OrbitRadius, OrbitHeight, OrbitPeriod, FallbackSeconds = 90 }` (7). A `Config.Movement` note: a battle dash costs no
  stamina (`MovementController.SetFreeDash`).
* `PetCatalog` (3.1, 3.2): `EvolutionBonus`, `LevelFactor(level, stage)`, `StatsOf / GetStats(.., stage)`, `EvolutionBonusOf`, `SpecialKinds` +
  Rally / Haste, the 15 Support specials, `Validate`; `EvolutionBoost` / `EvolutionMultiplier` kept as deprecated aliases (old values) and
  deleted by the lead in the W3 gate once no caller remains (`check.mjs` lists callers).
* `default.project.json`: `Technology = "Future"`, the `ReplicatedFirst` mapping (6.4). New `src/shared/ObbyLevels.lua`, `src/shared/UpdateNotes.lua`.
* `Main.server.lua` order: Remotes -> LightingService.Init -> LobbyBuilder.Build -> StormAltar.Build -> ArenaBuilder.Build(lobbyInfo) ->
  **DungeonBuilder.Build(lobbyInfo) -> dungeonInfo -> `NimbusLobby.PartCount` written (m3)** -> Damage / Token / Data -> PetService / ItemService / SpotService -> PlayerService ->
  MatchService -> PortalService -> **GateService.Init(lobbyInfo, { SpotService, PortalService, StormAltar })** -> Index / Npc -> TutorialService.Init
  (deps + `DungeonInfo`, `DungeonService`) -> Tycoon / PetCare / Fusion / Gem -> BattleService.Init -> **DungeonService.Init({ DataService,
  PetCareService, TycoonService, BattleService, DungeonBuilder, DungeonInfo, LobbyInfo })** -> EventService -> DevService. Optional services
  (`loadOptionalService`) like the Phase 3 ones; the boot spawn gate stays closed for good (7.2: `releaseSpawns` keeps `CharacterAutoLoads = false`). `Main.client.lua` `CONTROLLER_NAMES`: `MovementController`, **`MainMenuController`**, HudController,
  ..., + `DungeonController`, `ObbyController` (all three OPTIONAL).
* `tools/contract.json`: groups `shared/HomeRoam`, `shared/TokenLook`, `shared/WorldStyle`, `shared/ObbyLevels`, `shared/UpdateNotes`,
  `server/Services/DungeonService`, `server/Services/DungeonBuilder`, `server/Services/GateService`, `client/LightingStack`, `client/UiGate`,
  `client/UI/NeonKit`, the new controllers, the new public functions of sections 3-7 (`TycoonCatalog.SignedPads / FoldLegacy / BasketCap /
  FeedBerries / RoamLayout / LegacyMagnetLevel`, `DataService` Dungeon / Berries / Settings API, `BattleService` encounter API + `TeamSpec`,
  `PetCatalog.LevelFactor / EvolutionBonusOf`, `PetController.FormationFor`, `TycoonService.Drops`, `StormAltar.GetLanding`, `PortalService.
  PickLevel`, `MovementController.SetDashKeys / SetFreeDash / SetBattleSpeed`, `BattleService.SetRunProvider`, `PlayerService.SpawnPlayer / HasSpawned`,
  `BattleCatalog.Fighter.WalkOf / RunOf`, `DungeonService.KickMember`, `HotbarController.SetAvoidRight`); removed: `BattleService.StartTrial`,
  `ArenaBuilder.BuildPocket` Trial kind, `BattleCatalog.Trials*`; `partBudget`: `farm 150`, `garden 95`, `fence 90`, `fountain 80`, `gate 120`,
  `lobby 8000`, `arena 2800`, `dungeonRoom 320`, `dungeonBoss 420`, `dungeonRun 950`, `petEvoLow / petEvo2Low` kept.
* `tools/smoke.py`: registration lines for every new file of section 12 (placeholders that the owners fill); `tools/run_checks.sh` unchanged.
  `tools/count_locals.py` (new, from the Phase 4 design prototype: column-0 `local` statements per file; m4) and the 10.3 locals row re-baselined
  with it. The empty per-owner blocks of 11 in `dump_gui.lua`, `dump_model.lua`, `smoke_p5_gui.lua`, `smoke_p3_ui.lua` (C18). The `src/first`
  LocalScripts added to the smoke client boot and to check.mjs's client side (m13).
* Fixtures frozen: `tools/fixtures/DataService_phase4.lua`, `tools/fixtures/sim_tycoon_phase4.py` (byte copies, excluded from the game-code scans
  like the Phase 3 ones; `tools/fixtures/README.md` lists them).

#### 10.2 Attributes (written only on change)
| On | Name | Format | Writer | Readers |
|---|---|---|---|---|
| Player | `InBattle` (now in Config.Attr) | battle id, or a dungeon RUN id "D12" for the whole run | BattleService / DungeonService | many |
| Player | `Berries` | whole berries | DataService only, inside `AddBerries` / `SpendBerries` (<= 2/s, trailing write; m6) | HomeFx sign, CareController, MenuController |
| Player | `ProfileLoaded` | true once the profile is loaded or provisional | DataService | LoadingScreen (ReplicatedFirst) |
| Player | `ObbyLevel` | difficulty id | PortalService | HudController party row, ObbyController |
| Plot | `RoamSeed`, `RoamVersion`, `Roam`, `CoinDrops`, `BerryCap` (3.5) | | TycoonService | HomeFx, tests |
| Plot | `GardenPets`, `GardenInfo`, `GardenSlots`, `TrainingPets`, `IncomePerSecond`, `HomeLevel`, `Prestige`, `CollectorCash` | kept | | |
| Portal_Dungeon | `DungeonBoard` | `"Alex|7;Sam|4"` | DungeonService | the gate's pill |
| Portal_Ring | `RingBoard` | kept | | |
| Portal_Obby | `PartyLevel` (+ the existing party attrs) | difficulty id | PortalService | billboard, ObbyController |
| NimbusLobby | `PartCount` | number (BasePart descendants after the last gate) | Main.server, after `DungeonBuilder.Build` | LoadingScreen |
| Room models | `DoorOpen` | bool | DungeonService | DungeonController (the bars' slide) |
| NC_BattleZone | `Mode` + "Dungeon", `ZoneId "Room"`, `Index`, `Room` | | DungeonBuilder | BattleService.present |
| Tag | `NC_Detail` | pure decor models | LobbyBuilder / HomeBuilder / ArenaBuilder / DungeonBuilder | GraphicsQuality |
| Removed | plot `CoinPiles`; the per-difficulty portal attributes; `ArenaInfo.TrialPortal` | | | |

#### 10.3 Budgets (held by)
| Budget | Phase 5 | Held by |
|---|---|---|
| Lobby parts | <= 8000 incl. the six gates (<= 120 each), `PartCount` written | LobbyBuilder (`p5world_lobby`, `p5world_style`) |
| Arena island | <= 2800 (its portals moved to the court) | ArenaBuilder (`smoke_p3_arenaworld`) |
| Home plot | <= 950 fully built; Farm 150, Garden 95, Fence 90, Fountain 80 (3.6) | HomeBuilder (`smoke_p2_homeworld`) |
| Dungeon | templates <= 4,000 in ServerStorage; <= 950 live parts per run; `MAX_DUNGEONS 8` (12 only after the owner's MicroProfiler check; wave rooms 320 -> 260 via `Voxel` `MaxParts` is the next knob); a room parented in ONE step | DungeonBuilder (`p5dgn_world`) |
| Client total (streaming is OFF: every client holds everything) | <= **45,000** BaseParts in Workspace worst case: lobby 8,000 + NPCs 2,600 + arena 2,800 + 16 plots x 950 + 8 runs x 950 + 2 ring pockets x 600 + the live obby course + tokens / coins; `p5world_client_total` boots the server world, builds 16 Sky Castle plots, 2 ring pockets and 8 dungeon runs (8 x 950 stand-in parts until W3, real runs after) and asserts the count, printing the breakdown | lead (`smoke_p5_world.lua`, worldlobby adds it in W2) |
| Client home | <= 12 roaming pets (own home evolved Low <= 380 / 520), <= 36 coins x 6 parts, puffs / berries <= 16 | HomeFx (`client_p5home_roam`) |
| Battle units | own fighter High, helpers Low, enemies Low; raids ~25 units | BattleController |
| Network | battle snapshots < 6 KB/s per client in a 16-raid (`p5battle_net16`); a 4-player dungeon room <= a 4-raid; `DungeonState` < 1 KB, <= 1/s; `CoinDrops` <= 0.5/s <= 400 B; `Berries` <= 2/s; ProfileSync <= 4/s | BattleService, DungeonService, TycoonService |
| Server CPU | 1 s income tick (poops: <= 2 catch-ups per slot), 0.25 s scoop loop, 10 Hz `tickBattle` Move feed, 0.5 s dungeon loop, 2 Hz monitor; no per-frame server loops, no server tweens | |
| Lights | <= 12 shadow-casting in the lobby; torches `Shadows = false`; parts < 4 studs `CastShadow = false` | world builders |
| Lua locals (200) | baselines by `tools/count_locals.py` (column-0 `local` statements; the earlier numbers came from another count, m4): MenuController 181 (+2 max; new code in helper tables), ArenaBuilder 182 (+0: gate and art code in `Gates` / `Art` helper tables), BattleService 136 (`Enc`, `Cmd`, `Run` tables), HomeFx 141 (+2, `R`), DataService 158 + 1 (`P5`), TycoonService 128 + 2 (`Coins` grows), HudController 153 + 2, LobbyBuilder 142 (`Court`, `Gates`), PetController 105 + 1 (`F5`), PlayerService + 2, new files <= 120 | every engineer re-runs `python3 tools/count_locals.py <file>` before handing in; the W0 gate prints the table |
| DataStore | + <= ~0.3 KB per profile (Dungeon, Berries, Settings, Home keys) | additive |

#### 10.4 Exploits closed (new ones; X1-X24 of Phase 4 hold)
| # | Attempt | Closed by |
|---|---|---|
| Y1 | Forge damage / hit from the client | the client sends only actions; reach, cooldowns, meter, lives and damage are decided by `BattleSim` on the server fighter position |
| Y2 | Teleport / speed-hack the character in a battle | the server fighter walks toward the character at <= legal run x 1.25 (4.3); reach, hits and the drawn pet use the SERVER fighter, so running faster gains nothing; a gap > `Leash 10` for 3 s (a run-off / teleport) = out |
| Y3 | Spam commands | bucket 12 / 8 per s; `DungeonRequest` 6 / 2 + per-action cooldowns; `ObbyPick` 4/s; `SettingsSet` 6/s; junk types dropped |
| Y4 | Farm dungeon loot (replayed OnEnd, late join, two servers) | `run.Paid[room][uid]` marked BEFORE paying; rooms before a join pay nothing; first clear decided inside `MutateDungeon` (Cleared union); chest once per userId per run; only qualifying fighters (>= 5% of the room's party damage) are paid; the first clear needs the boss room + one earlier room; late join closes at room 3; an AFK alt earns nothing |
| Y5 | Enter a locked floor | the LEADER's `Dungeon.Best` is checked server-side; members are carried on purpose |
| Y6 | Quit-farm the loss XP | `RealLoss` gate; Quit / leave / disconnect / shutdown pay nothing |
| Y7 | Move a Cloud Cash coin or hurry a pet | poop times / points come from the server plan on server time; no pickup remote; the owner's root is checked |
| Y8 | Place / remove churn | `SettleSeconds 20`, first poop >= 24 s, the same key keeps its epoch within a cycle |
| Y9 | Forge berries / double-spend | never from the client; `SpendBerries` check-then-subtract; delta merge clamped at 0 (a two-server race costs at most one feed) |
| Y10 | Pick a locked obby level / spoof a party level | `IsUnlocked` on the server copy of `BestTimes`; only the leader's pick moves `party.Diff` |
| Y11 | Junk settings | key whitelist, ranges, types; `SeenNotes` only up |
| Y12 | Use a gate prompt from afar / in a match / in a battle | distance, `InMatch`, `InBattle`, `IsLocked` checks + 1.5 s cooldown in GateService |
| Y13 | Never send `MenuPlay` / disable the menu to hide in the plaza | the server spawns the character on `MenuPlay` or after `FallbackSeconds 90` whatever the client does; the tutorial is event-driven; a client without the menu only sees the plaza from a camera until its character exists |

#### 10.5 What is deleted (index; the areas' lists are the detail): BattleCatalog / BattleSim / BattleService / BattleController Trial + RETREAT
machinery (4.2-4.4, 4.7); `ArenaBuilder` `Portal_Trials`, `buildTrialPortal` (-> `buildGatePortal` using `WorldStyle.BuildGate`), `TrialPrompt`,
`ArenaInfo.TrialPortal`, the trial pocket template, `BuildPocket`'s Trial kind, `DEFAULT_ZONES / MAX_ZONE.Trial`, the zero-part fallback prompt,
the `link == "Portal"` condition; `LobbyBuilder` (6.1); `PortalService` per-difficulty parties; `ArenaController` Trial window (`buildTrials`,
`trials`, `trialCount`, `isCleared`, `highestCleared`, `trialPortal`, `TRIAL_RANGE`, `OpenTrials`, `SelectLevel`, `StartSelected`, `S.Level`,
`S.AtPortal`, `Win.Trials`, `C.Trial`, the "Trials" cases); `MenuController` "Trial best: %d / 30" (-> "Dungeon: floor %d cleared, %d runs"),
the 4th team slot branch; `TycoonCatalog` / `TycoonService` / `HomeBuilder` / `HomeFx` / `CareController` / `PetCareService` / `PetController`
items of 3.3-3.8; `PetCatalog.EvolutionBoost / EvolutionMultiplier` (W3 gate); `DataService` `P3.MAX_SLOTS 4`, `P3.slotUnlock`; `LightingService`
`LOOK`; CloudUI cloud bumps, the five Backdrops, `fitBox` / `fitWindow`s; `Config.Lobby.PortalRingRadius`; tests: `p3bs_trial`, `p3flow_trials`,
`p3fixsrv_trial1`, `p3fixsrv_retreat`, `p4ring_trialxp` (-> `p4ring_lossxp`), the Trial checks of `smoke_p3_arenaworld / p3_ui / p3_battlecore /
p3_battleclient / p3_visual`, `dump_gui` `arena:trials`, `render_*` `pocket` (trial), `sim_battle` `only=trials`.

#### 10.6 Owner checklist (by hand, once; docs W4 writes it into README.md as "Phase 5: owner checklist", numbered like this; `smoke_p2_final.lua`
`checkPhase5` asserts one needle per step, given in [brackets]; judge M9)
0. Where things live: the game's numbers are in `src/shared/Config.lua` in the project folder on your PC. While `rojo serve` runs and Studio is
   connected (the Rojo plugin's CONNECT button), a saved change in that file reaches Studio within a second; the committed `play/NimbusClimb.rbxlx`
   is rebuilt by us (`rojo build`) and only matters when you open the place WITHOUT Rojo. [`rojo serve`]
1. Publish and migrate: Studio -> File -> Publish to Roblox (Alt+P) -> your experience -> Publish. Then create.roblox.com -> Creations -> your
   experience -> the three dots -> **Migrate to Latest Update** (also under Configure Experience -> Places -> Start Place -> Version History):
   running servers move to the new version within a few minutes; until then Phase 4 and Phase 5 servers run together, which 9.3 makes safe.
   [`Migrate to Latest Update`]
2. The sky (6 images, ~5 min): Studio -> View -> Asset Manager -> Bulk Import -> the six PNGs in `branding/sky/` -> Upload. They are IMAGES (the
   ids are Image ids, which is what `Sky` needs; a Decal id would NOT work). New images wait for moderation (minutes to an hour; a grey square in
   Studio until approved). Right-click each -> Copy ID -> paste into `Config.Sky.Faces` as `Bk = "rbxassetid://123..."` (Bk Dn Ft Lf Rt Up by file
   name). Until all six are set the game shows the built-in fallback: a pink-lavender haze, a Roblox cloud layer tinted pink and 3000 stars (no
   seams, a little flatter than the painted sky). Left and right swapped -> swap the Lf and Rt ids. [`Bulk Import`]
3. Music and sounds: the game's own original audio (`audio/`, 12 files) goes up with the owner's keyed upload session:
   `python3 tools/upload_assets.py --audio` (dry run) then `--upload --audio`; it writes `src/shared/AudioIds.lua`, which `Config.Audio` reads
   (docs/phase6/OWNER_UPLOAD.md 6b: moderation, the monthly audio quota). A sound without an id is silent, nothing breaks. (Until 2026-10-27
   this step pasted free Toolbox ids into Config.Audio.) [`Config.Audio`]
4. Icons (optional): the menu tiles use emoji glyphs; a PNG you Bulk Import (step 2) pasted into `Config.Icons[id]` replaces one. [`Config.Icons`]
5. Lighting on a slow PC or phone: `default.project.json`, the line `"Technology": "Future"` -> `"ShadowMap"` (one word), save, publish. Players
   can also pick Graphics: Low in SETTINGS. [`ShadowMap`]
6. Gems for Robux (open since Phase 4): create.roblox.com -> your experience -> Monetization -> Developer Products -> Create (one per pack: name,
   Robux price) -> copy each Product ID into `Config.Gems.Products` (`{ Id = ..., Gems = 100, Name = "Pouch of Gems" }`); until then the Gems tab
   shows "Coming soon". [`Developer Products`]
7. After any change: Studio -> Play (F5) once, View -> Output: no red line starting with `[Config]` or `[LightingService]` = good. [`Output`]

### 11. Ownership and the waves (one owner per file per wave; Fable for the riskiest builders, Opus elsewhere; effort high)

Rules: engineers never edit `ARCHITECTURE_V3.md`, `Config.lua`, `PetCatalog.lua`, `Main.*.lua`, `default.project.json`, `tools/contract.json`,
`tools/run_checks.sh` (deviations go to the lead in the report). In `tools/smoke.py` each engineer edits only their own registration lines
(re-read right before each edit). The same rule ("your own block only, re-read right before each edit") applies to the shared tool files, each with
NAMED per-owner blocks the lead creates empty in W0 (`-- [owner: <key>] begin` .. `-- [owner: <key>] end`; C18): `tools/dump_gui.lua` and
`tools/dump_model.lua` (scene / target builders registered in a `SCENES` / the `BUILDERS` table from inside the block, so no block touches the
dispatch), `tools/smoke_p5_gui.lua` (the `client_p5gui_cover` scene lists, one block per window owner), `tools/smoke_p3_ui.lua` (the arena / ring
windows block -> dungeonclient, the chapter-3 block -> tutorial). `tools/render_gui.py` / `render_model.py` are lead-owned: owners name their new
scenes / targets in the report and the lead adds any python-side entries (`--list`, view presets) at the gate. New helpers go into the file's helper table; a window gets its own controller. Every builder tests with
`--only` while working and runs ONE full `--quick` at the end; the lead gates each wave with one full `--quick` in a worktree.

#### 11.1 Ownership table
| Role | Model | Wave | Source files (exclusive) | Test / tool files |
|---|---|---|---|---|
| lead | Fable | 0, gates, 6 | section 10.1 files | `smoke.py`, `contract.json`, `check.mjs` names, the two fixtures, `run_checks.sh` |
| data | Fable | 1 | `DataService.lua` (Teams 3, `Dungeon`, `Berries`, `Settings` + `SettingsSet`, `P5` migrations incl. the `FoldLegacy` call guarded by `if TycoonCatalog.FoldLegacy`), `client/State.lua` (Dungeon / Berries / Settings / PetStage / BestStage / Slots 3), `DevService.lua` (reset, `/berries`) | `smoke_p5_data.lua` (new), `smoke_p4_data.lua`, `smoke_p3_data.lua`, `smoke_p2_data.lua`, `smoke_polish_data.lua`, `smoke_dev.lua` |
| battlecore | Fable | 1 | `BattleCatalog.lua` (rewrite: 4.2 + 5.1 + Trial deletions), `BattleSim.lua` (rewrite 4.3) | `smoke_p5_battlecore.lua` (replaces `smoke_p3_battlecore.lua`), `tools/sim_battle.lua` (sections `fighter`, `support`, `duels`, `raids`, `ring`, `dungeon`, `training`; `trials` deleted) |
| economy+roam | Opus | 1 | `TycoonCatalog.lua` (3.3-3.5 data, `FoldLegacy`, `SignedPads`, `RoamLayout`, `BasketCap`, `FeedBerries`, PetPower via LevelFactor, deletions), `shared/HomeRoam.lua` (new, from `proto/HomeRoam.lua`), `shared/TokenLook.lua` (new), `TokenService.lua` (`MakeTokenPart` uses TokenLook) | `smoke_p4_economy.lua`, `smoke_p5_home.lua` (catalog + roam-shared scenarios), `tools/sim_tycoon.py` (`sim_p5.py` port, `--migrate5`, `--dungeon`, `--check`) |
| worldstyle | Opus | 1 | `shared/WorldStyle.lua` (new), `LightingService.lua`, `client/LightingStack.lua` (new), `blender/sky/render_sky.py` + `branding/sky/*.png` | `smoke_p5_world.lua` (`p5world_lighting`, `client_p5lightingstack`, `p5world_style` helpers), README sky steps (draft for docs) |
| battleservice | Fable | 2 | `BattleService.lua` (4.4-4.6) | `smoke_p5_battleservice.lua` (new), `smoke_p4_ring.lua`, `smoke_p3_battleservice.lua`, `smoke_p3_fix_server.lua`, `smoke_p3_fixcheck.lua`, `smoke_p3_events.lua`, `smoke_fix_leave.lua`, `smoke_p4_fix_battle.lua`, `smoke_p3_flow.lua` (W2) |
| tycoon+care | Fable | 2 | `TycoonService.lua` (3.5 ledger, Drops, old-id toasts, welcome toast, `BerryCap` / `Berries` attrs), `SpotService.lua` (podium stage), `PetCareService.lua` (3.4 Feed, prompts, evolve toast), `PetService.lua` (nothing new expected), `FusionService.lua` (stage carry kept) | `smoke_p4_garden.lua` (drops), `smoke_p4_portal.lua`, `smoke_p4_care.lua`, `smoke_p2_tycoon.lua`, `smoke_economy.lua`, `smoke_p2_fusion.lua`, `smoke_fix_server.lua`, `smoke_p5_home.lua` server scenarios |
| worldlobby | Opus | 2 | `LobbyBuilder.lua` (6.1 rebuild), `GateService.lua` (new), `PortalService.lua` (6.3), `StormAltar.lua` (`GetLanding`), `ArenaBuilder.lua` (Trial deletions, `Portal_Ring` + `Portal_Arena` via BuildGate into `GatesFolder`, zones; the art pass is arenaart's in W4) | `smoke_p5_world.lua` (`p5world_lobby`, `p5world_gates`, `p5obby_levels`, `p5obby_migration`), `smoke_p3_arenaworld.lua`, `smoke_polish_portals.lua`, `smoke_server.lua` portal scenarios, `tools/dump_model.lua` / `render_model.py` (`lobby`, `gates`) |
| homeworld | Opus | 2 | `HomeBuilder.lua` (3.6) | `smoke_p2_homeworld.lua`, `smoke_p2_visual.lua` (server halves), `dump_model.lua` / `render_model.py` home targets (`home:Press1:<1..40>`, `homegarden`) |
| neonkit | Opus | 2 | `shared/Theme.lua`, `client/UI/NeonKit.lua` (new), `client/UI/CloudUI.lua`, `HudController.lua` (pills, vitals, party row + CHANGE, stamina ticks), `HotbarController.lua`, `NotifyController.lua` | `smoke_p5_gui.lua` (`client_p5neon`, `client_p5stamina`, the `coverage.py` port), `smoke_client_v2.lua` ui-kit / hud / hotbar / notify scenarios, `smoke_polish_vitals.lua`, `tools/dump_gui.lua` widget gallery |
| dungeon | Fable | 3 | `DungeonService.lua` (new), `DungeonBuilder.lua` (new) | `smoke_p5_dungeon.lua` (server scenarios of 12), `dump_model.lua` / `render_model.py` `dungeon:*` |
| battleclient | Opus | 3 | `BattleController.lua` (4.7 incl. the Dungeon mode lines), `MovementController.lua` (`SetDashKeys`, `SetFreeDash`, `EXHAUST_RESUME`), `client/UI/PetCard.lua` (lives pips) | `smoke_p5_battleclient.lua` (new), `smoke_p3_battleclient.lua`, `smoke_p3_fix_client.lua`, `smoke_p3_visual.lua` (client half), `dump_gui.lua` battle scenarios |
| homefx+pets | Opus | 3 | `HomeFx.lua` (3.4 signs + flights + basket line, 3.5 roaming + coins, 3.7 evolved home pets), `PetController.lua` (3.8), `shared/PetBuilder.lua` (`PB_Evolved` attribute, `Wild` option), `HomePortalFx.lua` (if touched) | `smoke_p5_home.lua` client scenarios, `smoke_p5_follow.lua` (new), `smoke_p4_pets_client.lua`, `smoke_client_v2.lua` follow windows, `smoke_p2_fix_client.lua`, `smoke_p2_homeworld.lua` / `smoke_p2_visual.lua` client halves, `smoke_release_client.lua`, `smoke_polish_worldtext.lua` |
| careui | Opus | 3 | `CareController.lua` (Feed window, stage viewports, Dock), `MenuController.lua` (tile grid + Dock, Home strip, Pets "Food Machine" + stage, Team 3 slots + FIGHTER / "Set as fighter", Stats dungeon line, reveal ribbon, prestige texts), `IndexController.lua` (BestStage tiles, Dock), `FusionController.lua` (stage tiles, Dock) | `smoke_p4_careui.lua`, `smoke_p5_looks.lua` (new), `smoke_p2_ui.lua` (Home / Pets rows), `smoke_p3_evolved.lua`, `dump_gui.lua` / `render_gui.py` menu / feed / garden / train / looks scenarios |
| menu | Opus | 3 | `src/first/LoadingScreen.client.lua`, `client/UiGate.lua`, `Controllers/MainMenuController.lua`, `client/ClientSettings.lua`, `client/SoundFx.lua`, `client/GraphicsQuality.lua`, `DevController.lua` (`/menu`), `server/Services/PlayerService.lua` (the 7.2 spawn gate: `SpawnPlayer`, `HasSpawned`, `MenuPlay`, the fallback, the respawn) | `smoke_p5_menu.lua` (`p5menu_spawn`, `client_p5loading`, `client_p5menu`, `client_p5settings`), `dump_gui.lua` `mainmenu` / `loading` / `settings` |
| dungeonclient | Opus | 4 | `Controllers/DungeonController.lua` (new), `ArenaController.lua` (Trial deletions, Dungeon prompt hand-off, Practice invite flag, Ring card stage, Dock), `Controllers/ObbyController.lua` (new) | `smoke_p5_dungeon.lua` client scenarios, `smoke_p5_world.lua` `client_p5obby`, `smoke_p3_ui.lua` (arena / ring windows), `dump_gui.lua` `arena:dungeon`, `obby`, `ring` |
| tutorial | Opus | 4 | `TutorialService.lua`, `shared/TutorialSteps.lua`, `TutorialController.lua` (+ the UiGate wait), `shared/NpcDialog.lua` | `smoke_p4_ui.lua` (chapters 2 / 4), `smoke_p3_ui.lua` (chapter 3, needles), `smoke_p2_ui.lua` (chapter 2 ids / texts), `smoke_p5_tutorial.lua` (`p5ui_content`, `p5dgn_tutorial`, `p5ui_tutorial_ch2`) |
| docs | Opus | 4 | `README.md`, `tools/README.md`, `tools/fixtures/README.md` | `smoke_p2_final.lua` (`checkPhase5`) |
| flow | Opus | 4 | (none: reports bugs to the lead, who reopens the owner) | `smoke_p5_flow.lua` (new), `smoke_p4_flow.lua`, `smoke_p3_flow.lua` (W4), `smoke_p2_flow.lua` |
| arenaart | Opus | 4 | `ArenaBuilder.lua` art pass (6.4 rules: island, colosseum, stands, Ring pocket; budget 2800; `Portal_Ring` / `Portal_Arena` untouched) | `smoke_p3_arenaworld.lua`, `smoke_p3_visual.lua` (arena half), its `dump_model.lua` block; renders `arena`, `arena:ring`, `pocket:ring` (>= 3 rounds) |
Untouched on purpose: `Voxel.lua`, `BossBuilder.lua`, `EventService.lua` (verify it keeps ignoring non-Raid results),
`DamageService.lua`, `MatchService.lua`, `GemService.lua`, `IndexService.lua`, `ItemService.lua`, `NpcService.lua`, `HazardService.lua`,
`CourseBuilder.lua`, `CourseLayout.lua`, `DamageFx.lua`, `EvolutionFx.lua`, `TokenFx.lua`, `SkyDragonController.lua`, `ShowcaseController.lua`,
`NpcController.lua`, `DevPetShow.lua`, `ItemCatalog.lua`, `PetKeys.lua`, `Util.lua`, `Remotes.lua`.

Interfaces each pair codes against (fixed here): battlecore <-> battleservice / battleclient / dungeon (4.2-4.6, 5.1); battleservice <->
dungeon (4.6, both Fable: the dungeon lands one wave AFTER the real BattleService); economy+roam <-> tycoon / homefx (3.3-3.5 names, the
attribute formats); data <-> tycoon / care / dungeon / menu (9.1 API); worldstyle <-> worldlobby / homeworld / dungeon / arenaart
(`WorldStyle.BuildGate`, pieces, `Materials`) and <-> dungeonclient / menu (`LightingStack`); worldlobby <-> dungeon (`GateSites.Dungeon`,
`GatesFolder`) and <-> tutorial (`Portals.Obby`); neonkit <-> every window owner (`NeonKit`, `CloudUI.Panel`, `Dock`); menu <-> tutorial
(`UiGate`); tycoon+care <-> homefx / careui (attributes, `PetCare("Feed", key)` answer, `OpenPanel` args).

#### 11.2 The ordered build plan (each wave gated by `python3 tools/syntax.py`, `node tools/check.mjs`, one full `bash tools/run_checks.sh --quick`; the lead's "known red until wave N" list only shrinks)
**Wave 0 - lead (Fable), contract freeze.** Baseline `--quick` on `v3-phase5` (green, keep the log); freeze the two fixtures; this contract;
the shared edits of 10.1 (incl. `tools/count_locals.py`, the empty per-owner blocks, `PartCount` in Main, the spawn gate left closed with
`Config.MainMenu.Enabled = false` until W3); smoke.py placeholders; gate green (the aliases keep Phase 4 code booting).
**Wave 1 - foundations (4): data (Fable), battlecore (Fable), economy+roam (Opus), worldstyle (Opus).** Pure modules + the save layer. Gate:
their scenarios; `sim_tycoon.py` ALL TARGETS MET with `--ring 0.08 --dungeon 0.1`, `--check`, `--migrate5`; `sim_battle` quick (`support` 0.65-
0.75, `duels` 40-60% no timeouts, `raids` 100-240 s for 1 / 4 / 8 / 16, `ring` medians within +-2 of Phase 4 after re-tune, `dungeon` ladder
floor 1 = 100% for the 12 single L1 pets and S10 >= F10); `render_sky` committed. Known red until W2: every booted scenario that reads the old
catalog / BattleSim shapes (p2tycoon_*, p2home_*, p4garden_*, p4care_*, p3bs_*, p4ring_*, p3flow_*, the client battle / home scenarios).
**Wave 2 - servers, worlds, the kit (5): battleservice (Fable), tycoon+care (Fable), worldlobby (Opus), homeworld (Opus), neonkit (Opus).**
Gate: every server scenario green except the dungeon's, the flows and the client windows; renders (>= 3 rounds): the Berry Farm L1 / L10 /
L22 / L40, the Garden with 12 beds + bowl, the Fence / Fountain levels, the House tiers / Vault / Fusion / Arena Gate, the plot at Sky Castle, the five gates + the reserved Dungeon site
(the sixth gate and the lobby <= 8000 check run at the W3 gate, m3), the plaza top view; the Neon
widget gallery at 4 sizes. Known red until W3 / W4: client battle and home scenarios, dungeon, the windows' Dock checks, flows, docs.
**Wave 3 - the dungeon server and the clients (5): dungeon (Fable), battleclient (Opus), homefx+pets (Opus), careui (Opus), menu (Opus).**
Gate: dungeon server scenarios, battle / home / care / menu client + phone scenarios green; renders: the battle HUD (`battle:fighter`,
`battle:raid`, `battle:dungeon`) at 1920x1080 / 1366x768 / 1170x540 / 740x360, the Food Machine window, the Home strip, the Pets grid with
evolved slots, the main menu, the loading screen, settings, the dungeon rooms (`dungeon:run:3`). The lead deletes `EvolutionBoost` /
`EvolutionMultiplier` in this gate. Known red until W4: dungeon client, obby picker, arena / ring windows, tutorial, flows, docs.
**Wave 4 - dungeon client, tutorial, docs, flows, arena art (5): dungeonclient (Opus), tutorial (Opus), docs (Opus), flow (Opus), arenaart (Opus).**
Gate: everything green; renders of the Dungeon / Obby / Ring / Arena side panels at 4 sizes and of the arena island (`arena`, `arena:ring`,
`pocket:ring`, >= 3 rounds); the README owner checklist (10.6) present with every needle; `client_p5gui_cover` <= 60% everywhere. Bugs found by flow go back to the
owner (a short fix wave).
**Wave 5 - review and fix (3 reviewers).** Lenses: save data and merges (incl. both rollout fixtures), money paid
exactly once (dungeon rooms / first clears / chests, berries, coins, ring), battle lifecycle (encounters, every end path, InBattle gaps, leash,
the loss gate), economy numbers (sim vs catalog vs README), client budgets and readability (coverage, centre, phone sizes, parts), tutorial /
NPC / README accuracy. Release gate: full `bash tools/run_checks.sh`, `--smoke --strict`, the Rojo 7.7.1 rebuild of `play/NimbusClimb.rbxlx`,
`tools/verify_place.py`, merge to main. Critical path: W0 -> data / battlecore (W1) -> battleservice / tycoon+care (W2) -> dungeon / careui (W3)
-> dungeonclient / tutorial / flow (W4) -> W5. worldstyle, worldlobby, homeworld, neonkit, homefx+pets, menu have slack.

### 12. Tests (every owner registers their own file in `tools/smoke.py`; smoke.py fails on an unwired `tools/smoke_*.lua`)

#### 12.1 New smoke files
| File | Worlds | Owner (wave) | Scenarios and what they assert |
|---|---|---|---|
| `smoke_p5_data.lua` | server | data (W1) | `p5data_team3` (a 4-key preset loads with 3, `TeamsChanged` once, Cash / Gems / PetLevels / PetGrowth byte-equal, `SetTeam` > 3 refused, merge of two sessions, ProfileSync shape), `p5data_evo_untouched`, `p5dgn_data` (Dungeon defaults / clean / merges Best max, Cleared union, Runs + Clears delta / provisional / sync / reset), `p5dgn_migrate` (frozen Phase 4 fixture `TrialBest 15` -> `Best 5`, `Cleared 1-5`, `Clears 5`, marker; every other field byte-identical; idempotent; `TrialBest 0 / 1 / 2 / 30` -> `0 / 0 / 0 / 10`; runs on `ProfileRebased`), `p5data_berries` (delta clamped at 0, provisional rules, no sync on a Berries-only change), `p5data_settings` (defaults per key, malformed keys, `SettingsSet` validation, session wins), `p5home_fold_data` (the P5Home step: `FoldLegacy` called once with `firstTime`, marker in the same step and ONLY when the fold ran (a missing `FoldLegacy` leaves the marker unset and the step retries on the next load), Food converted to berries once (one Feast = 6400) and zeroed; keys removed travel as `false`), `p5home_rollout` + `p5dgn_rollout` (the frozen Phase 4 DataService saves a Phase 5 profile: `Dungeon`, `Berries`, `Settings`, `DecorCredit`, `LegacyMagnet*` come back; `Press1 13` not clamped on return) |
| `smoke_p5_battlecore.lua` (replaces `smoke_p3_battlecore.lua`) | pure | battlecore (W1) | `p5stats_formula` (LevelFactor table to 1e-9, stage vs none, hybrids, stage above MaxEvolution clamped), `p5roles` (Support x2.6 / x1.5, the 15 kinds, Validate, Combat bit-identical at stage 0), `p5sim_fighter` (attack timing / reach / lock; Element cooldown + every shape; Specials incl. Rally / Haste; Dash i-frames dodge a Winding hit and a telegraph; Swap cooldown / cast lock / bench regen / auto-swap / lives; Buff cooldowns; Move clamp at legal run x MoveSlack incl. Haste / Slow / Dashing, `SpeedOf`, the `Speed` event on Swap / Haste), `p5sim_ai` (threat, wind-up inside the interval, miss on i-frames, slow / weaken / burn / stun), `p5sim_modes` (Duel ends by lives or damage, no overtime; Ring timeout loss; Raid 1-16 fighters; Dungeon: empty side 2 runs, SpawnEnemies / EnemiesDown / BossHp / Wipe / Finish), `p5sim_wire` (round trip with the new codes, windup bit, lives packing, junk payloads, 25 units < 600 B), `p5sim_determinism`, `p5dgn_catalog` (12 floors, elements exist, power monotonic, floor 10 = 2048 +-1%, DungeonWave deterministic / never EventOnly / floor 1 one handicapped enemy / boss entry, rewards grow, first-clear totals 23,400 / 156, Validate), `p5battle_balance` (sim_battle subset: support 0.65-0.75, mirror duels 40-60%, kit factor 1.3-1.7, raids 100-240 s, the 2.4 wave rule >= 90% with helpers, ring medians +-2, floor 1 by one L1 pet, S10 >= F10) |
| `smoke_p5_home.lua` | server + client | economy+roam (W1), tycoon+care (W2), homefx+pets (W3) | `p5home_catalog` (11 stations == the sim block, Kinds, decor 0.4x, caps 24/45/72/80, Validate, build-outs, `HomeLevelOf` with credits), `p5home_fold` (fixtures: fresh / Press1 6 + Press2 4 / all plants 10 / Collector 3 at Prestige 2 / all decor 3 / a Phase 4 Press2 after the marker: HL and food never drop, expected farm level, credits, idempotent), `p5home_signs`, `p5home_roam_shared` (two requires give identical plans for 3 seeds x 12 slots x 50 cycles; speeds 4-9; points inside the yard and off Blocked rects; continuity; cache <= 3), `p5home_berries` (poop adds 0.25 clamped at BasketCap, a cap that drops below the berries removes none, offline berries ignore the cap, cap + BasketMin, offline once, Feed spends FeedBerries and grants FeedXp, no Food path (converted by P5Home), the `Berries` attribute written only by DataService, every refusal, `{Count = 5}` = one feed, XP 0 refunds, provisional, `Berries` <= 2/s, no sync), `p5home_roam_server` (epoch + 20, first poop >= 24 s, points == Plan, 3 drops then merge, owner scoop radius 8 / visitor never, nap + wake, churn, invariant every step, `CoinDrops` format / rate, rebase -> Welcome once), `client_p5home_roam` (poses within 0.5 stud of `HomeRoam.At`, eat at the bowl, pending coin confirmed / faded, zip + "+$", others dimmed, budgets, parked beyond 110, RoamVersion mismatch), `client_p5home_flow_ui` (Home strip texts, one Feed button with the berry price, no "Level up", basket header, three signs, basket line follows attributes, Pets "Food Machine") |
| `smoke_p5_world.lua` | server + client | worldstyle (W1), worldlobby (W2), dungeonclient (W4) | `p5world_lighting` (Fallback vs Custom by `Config.Sky.Faces`, one id missing -> fallback, `Init()` twice = same), `client_p5lightingstack` (Push A, B, Pop A -> B applied; Pop B -> base exact; unknown no-op; GfxLow + Dungeon), `p5world_lobby` (6 `GateSites` on r 118 +-1 within 50..130 deg, >= 26 apart, facing the centre; `Portals` = exactly Obby; no `Portal_Easy..Saint` / `Portal_Trials`; 16 spots on r 340 +-30; spawn looks at the court; gardens / altar between plaza and street; shop beyond; NPC spots >= 10 from pads / paths; lobby <= 8000 (from the W3 gate), `PartCount` written by Main after the last gate; arena clear of plots), `p5world_client_total` (10.3: the booted world + 16 Sky Castle plots + 2 ring pockets + 8 dungeon runs (stand-in 8 x 950 parts until W3) <= 45,000 BaseParts, breakdown printed), `p5world_style` (materials, no big SmoothPlastic, saturation, each gate <= 120 with a pixel billboard, <= 12 shadow lights, small parts CastShadow false), `p5world_gates` (Home prompt with / without a plot, refusals InMatch / InBattle / locked / far / cooldown; Altar -> within 6 of `GetLanding()` on ground; `Portal_Arena` -> `ArenaInfo.Spawn` and the Return gate; `Teleported` once), `p5obby_levels` (`HighestUnlocked` table, `ObbyPick` refusals leave the attribute, accepted sets it, first on the pad -> party level, joiner without the unlock joins, leader re-pick vs member pick, launch `StartMatch("Hard")`, unlock after a win, `PartyState` fields), `p5obby_migration` (Phase 4 fixture profiles: {Easy, Medium} -> Hard; {Extreme} -> all; {} -> Easy; record round-trips), `client_p5obby` |
| `smoke_p5_gui.lua` | client + phone | neonkit (W2), then every window owner adds its scenes | `client_p5neon` (Card stroke + Glow, Tile fonts + stroke, `SideRect` == the prototype at 4 sizes), `client_p5stamina` (150, runs ~10.7 s, refills <= 3.5 s, 4 dashes, 4 ticks), `client_p5hud_pills`, `client_p5gui_cover` (for `menu:*`, `feed`, `garden`, `train`, `ring`, `arena:*`, `dungeon`, `obby`, `settings` at 4 sizes: union <= 60%, landscape left edge >= 0.5 W, portrait top >= 0.44 H, no `Backdrop`, smallest text >= the floor) |
| `smoke_p5_battleservice.lua` | server | battleservice (W2) | `p5svc_commands` (ladder: junk types, NaN / huge aims, bucket, NotInZone, every refusal, toasts throttled), `p5svc_position` (character teleport -> the server fighter lags at legal run x 1.25; a gap > 10 for 3 s = leaver / RemoveTeam; `Start.Team.Speed` and `Speed` events on Swap / Haste), `p5svc_position_legit` (mochi_slime L1 and stormfang L50: the character replays `lead-fix/leash_fix.py`'s random-target run and the r 14 circle at exactly `RunOf(WalkOf(MoveSpeed))` with a 200 ms feed delay, 20 s each: zero leashes, every ATTACK on a target within the drawn reach accepted; a straight run-off past the zone edge IS leashed after 3 s), `p5svc_duel_fair` (gap 2 practice, queue band, Practice flag, MaxHit, no overtime, rewards once, leaver loses), `p5svc_raid` (16 fighters, boss HP by ExpectedDps, `p5battle_net16` < 6 KB/s, leavers, tiers once), `p5svc_ring` (rounds 1-3 won by one L1 pet pressing ATTACK once per second; XP once per round; every end path; `p4ring_lossxp`), `p5svc_encounter` (boots with NO run provider and `KeysInBattle` / `canBattle` work; OpenEncounter 1 and 4 teams with KeepInBattle: the attribute untouched after add, FinishEncounter, RemoveEncounterTeam, a KO wipe, forceRelease and Shutdown; `SetRunProvider` with a GetRun that returns a run -> raid join / duel accept / Ring start refused "Finish your dungeon run first"; an erroring OnEnd / OnWave is pcall-ed and finalizeBody still completes; `Result.Fighters` drops a 0-damage team of two and keeps a solo 1-damage team; SpawnWave; OnWave / OnBossHp / OnDown / OnLeave; FinishEncounter idempotent, "End" with `Rewards.Dungeon`, `BattleEnded` Mode Dungeon then OnEnd; RemoveEncounterTeam mid-fight; Wipe / Timeout end the sim; the 10 s fail-safe; nothing paid by BattleService), `p5svc_shutdown` (voids Duel / Ring, pays Raid shares, encounters end Shutdown, nothing twice) |
| `smoke_p5_dungeon.lua` | server + client | dungeon (W3), dungeonclient (W4) | `p5dgn_party` (create / join / ready / SetFloor / leave; the leader's Kick removes a member with a toast, a non-leader Kick is refused; START with an unready member drops them after 30 s and starts; a join once room 3 started is refused), `p5dgn_exclusive` (in the Hall, a Corridor and the Treasure: a raid join, a duel accept, a Ring start, GoHome, the Home / Altar gates, the obby pad and the dev `/reset` are each refused and `InBattle` stays the run id), `p5dgn_run` (`BattleService.SetRunProvider` was called by Init; solo floor 1 with ONE L1 pet end to end through the remotes: hall -> room 1 Start with `Mode "Dungeon"` + `Start.Dungeon` -> waves -> loot once -> bars -> room 2 built while 1 fights, room 1 destroyed on entering 3 -> boss + escort at 50% -> chest -> exit; `InBattle` = run id from the teleport to the return; pocket freed; `workspace.Dungeons` gone; a 4-party: stragglers placed, enemies 2 + 3, leash), `p5dgn_loot` (once per room per fighter, replayed OnEnd pays nothing, Cash = income x seconds with the floor, Tokens x2 under Double Rewards (Cash / XP not), XP via GrantXp source "Dungeon", first clear once, an AFK member (0 damage) paid nothing and no first clear, a boss-only joiner paid the boss room when qualifying but never the first clear, a solo run with 1 damage paid, a late joiner unpaid for earlier rooms, chest once and auto-opened on the 45 s exit, no Gems chest on floors 1-2, loss third on a wipe >= 20 s, nothing on Quit), `p5dgn_ends` (wipe by timeout and KO, Quit mid-fight / in a corridor, leave the game, respawn elsewhere, obby match refused, leash, last member frees the pocket, Shutdown mid-fight and in a corridor, `RunEnded` once, fail-safe; watchdog: an injected error in `Dg.onRoomEnd` ends the run "Error" within 20 s with every member InBattle nil, the pocket free, `RunEnded` once and nothing paid twice; a run older than RunMaxSeconds ends), `p5dgn_world` (templates within budgets, `BuildRun` <= 950, no overlap over 20 seeds, attachments present, zones Mode Dungeon 44 / 56 inside the floor, Accent recoloured, `FreeRun` clean, the portal <= 120 with `OpenPanel "Dungeon"`, portal outside every zone), `p5dgn_net` (a 4-player room <= a 4-raid's bytes; `DungeonState` < 1 KB; junk `DungeonRequest` 60/s refused without errors), `client_p5dungeon` / `_mobile` (window from a Lobby payload at 4 sizes <= 60%, READY optimistic + revert, run cards from Run / Loot / End, result card, chest prompt, lighting pushed and popped, "DUNGEON - Floor 3 - Room 2" with wild chips) |
| `smoke_p5_battleclient.lua` | client + phone | battleclient (W3) | `client_p5hud_fighter` (writes only on change, loss trail, energy, lives, portraits + rings from events, late-join cooldowns from Start), `client_p5hud_enemies` (rows, lock first, +n, windup flash, boss bar not centred), `client_p5input` (map bound only in battle, hold-to-attack cadence, swap hold, Tab cycle, predictions + rejected shake + timeout reset, `SetDashKeys` / `SetFreeDash` / `SetBattleSpeed(walk, run)` on Start / Speed / End (WalkSpeed written = walk, run target = run, nil restores the server base, a server 0 still wins), binds inert before `UiGate.HasPlayed()`), `client_p5models` (fighter at the shoulder of the server position, blended with the root within 2 studs, following the server beyond, helpers fly on Buff / Swap, Winding pose, DODGED, shake x Shake setting), `client_p5battle_mobile` / `_landscape` (nothing in the centre 40%, buttons >= 60 px, menu column hidden), `client_p5result`; renders `battle:fighter`, `battle:raid`, `battle:dungeon` |
| `smoke_p5_follow.lua` | client | homefx+pets (W3) | `client_p5follow_formation` (`FormationFor` on 7 width mixes == 3.8 +-0.05), `client_p5follow_motion` (walk 16 / 24 / 27 straight, 90-degree turn, reverse: gaps >= 0, lag <= back + 9, settle <= back + 1, ahead <= 0.5 after 0.6 s, channel >= 1.0), `client_p5wild` (`PB_Evolved`, `Wild` tint + eyes) |
| `smoke_p5_looks.lua` | client + server | careui (W3) | `client_p5looks` (keys at stage 1 and 2: Pets grid slot, detail, Index tile (BestStage), Team card + tiles, Fusion tile, Care rows, own garden pets all evolved (12), reveal of an evolved key + ribbon, Ring card, followers: each builds `PB_Evolved == stage` at Low), `p5looks_podium`, `client_p5support_power` (the Pets panel detail of an Economy pet shows "Battle power" from `BattleCatalog.UnitStats` with the Support role, never the raw Power 2-4; m17), `client_p5team3` (3 slots, FIGHTER / HELPER labels, "Set as fighter" rotates, no 4th slot), `client_p5menu_tiles` (2x3 grid, names kept, Dock, no backdrop) |
| `smoke_p5_menu.lua` | server + client + phone | menu (W3) | `p5menu_spawn` (with `Config.MainMenu.Enabled`: a joining player has no Character until `MenuPlay`; a second `MenuPlay` does nothing; no remote -> the character appears after the 90 s fallback on the mock clock; death -> respawn after RespawnTime; a player leaving before PLAY leaves nothing behind; Enabled false -> the character spawns at once as every other scenario expects), `client_p5loading` (RemoveDefaultLoadingScreen, bar never backwards, SKIP after 6 s, Done at 100%, tips rotate, no text before Theme, gone after the fade), `client_p5menu` (every ScreenGui except NimbusLoading / NimbusMainMenu / NimbusNotify disabled until PLAY incl. one created later and NimbusDash / NimbusRun / NimbusIndex / NimbusNpcDialog / NimbusTutorialPointer by name; Shift / Q do nothing before PLAY; no character before PLAY; `MenuPlay` fired once; camera Scriptable then Custom, `Played` once, tutorial panel absent before / shown after, UPDATES badge), `client_p5settings` (slider -> one `SettingsSet` after the debounce with clamped ints; Gfx Low hides `NC_Detail` and pushes GfxLow, High restores; Shake OFF -> amplitude 0; SeenNotes sent on UPDATES) |
| `smoke_p5_tutorial.lua` | server + client | tutorial (W4) | `p5ui_content` (every step id / text 97-125 bytes / target; NPC lines <= 125 bytes, needles from the catalogs: Berry Farm, Food Bowl, Cloud Cash, Berry Basket, Dungeon, fighter / helpers), `p5dgn_tutorial` (chapter 3 `team` -> `dungeon` with the arrow at the Dungeon pad -> floor 1 cleared marks DungeonWon -> `raid`; a veteran with `TrialCleared[1]` skips; `OpenPanel("Dungeon", { Floor = 1 })` once), `p5ui_tutorial_ch2` (steps 10-14 against a Phase 5 home: Farm pad then Kitchen pad, the biggest drop, Fed), `p5ui_portal_obby` (the chapter-1 portal step targets `Portals.Obby`), resume from every index 1-21 |
| `smoke_p5_flow.lua` | server + client | flow (W4) | `p5flow_new` (a new player: menu PLAY -> tutorial -> Easy obby -> claim -> Garden -> a roaming pet poops -> scoop -> Farm -> Food Machine -> Feed with berries -> `/petlevel 20` + EVOLVE (looks evolved in the grid) -> team of 3 -> dungeon floor 1 solo -> ring rounds 1-3 -> prestige keeps berries and the Garden), `p5flow_migrate` (a Phase 4 save: 4 plants + Collector + 6 decor + a 4-key team + TrialBest 15 + leftover Feasts + BestTimes {Easy, Medium}: Home Level unchanged or up, Farm level, DecorCredit / LegacyMagnet, 3-key team with the 4th pet owned, floors 1-5 cleared, Hard unlocked, Feasts spent as berries, Ready to evolve), `p5flow_dungeon` (3 players: a party clears floors 1-2, one wipes solo on floor 4, a late join, Double Rewards, rejoin keeps `Dungeon`, the dev reset), `p5flow_rejoin` / `p5flow_merge` (two servers: berries, Dungeon (Cleared union, Clears not doubled by two migrations, a first clear paid on both servers before either saved lands once in Cleared), Settings, Teams) |

#### 12.2 Existing tests that change (owner in brackets)
`smoke_p4_economy` (economy: 11 stations, FoldLegacy / SignedPads / BasketCap / FeedBerries, PetPower with LevelFactor, the sim parity block);
`smoke_p4_garden` (tycoon: piles -> drops, `CoinDrops`, roam epochs; homefx: client half); `smoke_p4_care` (tycoon+care: berries, no Count /
Food modes, evolve toast text); `smoke_p2_tycoon`, `smoke_economy` (tycoon: old ids answer the toast, Kitchen / Gym slots swapped);
`smoke_p2_homeworld`, `smoke_p2_visual`, `smoke_p2_fix_client` (homeworld / homefx: budgets, the swap, signs "Unsigned", 12 beds, bowl, no
walks); `smoke_p4_careui`, `smoke_p2_ui`, `smoke_p3_evolved` (careui: Feed window, Home strip, Pets, Team 3, Dock); `smoke_p4_pets_client`,
`smoke_client_v2`, `smoke_release_client`, `smoke_polish_worldtext` (homefx+pets: size-aware follow windows, cards, gate tags); `smoke_p4_ring`,
`smoke_p3_battleservice`, `smoke_p3_fix_server`, `smoke_p3_fixcheck`, `smoke_p3_events`, `smoke_fix_leave`, `smoke_p4_fix_battle` (battleservice:
Trial scenarios deleted, `TrialPortal` teleports -> `RingPortal`, the new command set, `Mode` names); `smoke_p3_battleclient`, `smoke_p3_fix_client`,
`smoke_p3_visual` (battleclient: the new HUD, no RETREAT, Ring cards kept); `smoke_p3_arenaworld`, `smoke_polish_portals`, `smoke_server`
portal scenarios (worldlobby: no Trial portal, Portal_Ring / Portal_Arena in the Gates folder, arena <= 2800, one obby portal, `Portals.Obby`);
`smoke_p3_ui`, `smoke_p4_ui`, `smoke_p2_ui` chapter blocks (tutorial: section 8); `smoke_p3_data`, `smoke_p4_data`, `smoke_p2_data`,
`smoke_polish_data`, `smoke_dev` (data: Slots 3, new fields, reset); `smoke_p3_flow`, `smoke_p4_flow`, `smoke_p2_flow` (flow: Trials ->
dungeon, berries, 3-key teams); `smoke_p2_final` (docs: README tables incl. `checkPhase5`); `tools/dump_gui.lua`, `render_gui.py` (scenes
`mainmenu`, `loading`, `settings`, `obby`, `arena:dungeon`, `battle:*`, `looks`, `home:strip`; `arena:trials` gone), `tools/dump_model.lua`,
`render_model.py` (`lobby --views top`, `gates`, `dungeon:*`, `home:Press1:<n>`, `homegarden`; `pocket` trial gone). `smoke.py` (lead):
the new registration lines; `p3battle_*` scenario names -> `p5battle_*`.

#### 12.3 Sims
`tools/sim_tycoon.py` (economy W1): the `sim_p5.py` model (12-station constants block, `PRICE_Press1` = FARM_PRICE, `PLANT_FOOD_Press1` =
FARM_FOOD, `GARDEN_RADIUS`, `GARDEN_PILE_SECONDS`, `EVOLUTION_BONUS`, `BERRY = [0.25, 30]`), `power()` on LevelFactor, feeding spends berries,
`--ring 0.08`, `--dungeon 0.1` (a run per 10 min: the 5.2 Cash), `--check` (tables, `FoldLegacy`, `SignedPads`, `BasketCap`, `FeedBerries`,
`AvailablePads` with stars), `--migrate5` (= `fold_check.py` against the frozen `sim_tycoon_phase4.py`: 300 homes, HL never down, no dead end,
pad time <= 1.0 per bucket). TARGETS: the 13 Phase 4 targets, unchanged; the run with both flags must print ALL TARGETS MET.
`tools/sim_battle.lua` (battlecore W1): sections `fighter` (kit factor 1.3-1.7; mirror fights 8-45 s; no fight reaches the Ring's 90 s),
`support` (DPS ratio 0.65-0.75; a Support fighter beats 2 x puddle_frog L8 in 10-60% of seeds), `duels` (mirror 40-60%, no draws, none at
120 s), `raids` (100-240 s for 1 / 4 / 8 / 16 fighters at 70% dodges; no one-shots), `ring` (rounds 1-3 >= 95% for every single L1 rollable
pet; stage medians S1 13-19 ... S10 48-54 after re-tuning `Growth`), `dungeon` (floor 1 100% for the 12 single L1 pets; the stage ladder
monotonic; S10 >= F10; a 4-party +1 floor), `training` (kept), `move` (replays the B1 patterns, random targets + the r 14 circle, at the legal run speed with a 200 ms feed delay for
mochi_slime L1 / sunbeam_bear L20 / stormfang L50: gap vs the reported position <= 0.5 stud after the catch-up, zero leashes; a straight run-off is
leashed after 3 s); `trials` deleted. `SIM.Stages`, `SIM.team`, `SIM.Player` kept as the library
`p5battle_balance` and `p5dgn_balance` call.

### 13. Open risks (and the knob that absorbs each)
| # | Risk | Mitigation |
|---|---|---|
| R1 | The real-time fighter changes fight lengths; the Ring and Dungeon ladders were measured on the Phase 4 engine | floors and rounds are data keyed on TeamPower; W1 re-measures with `sim_battle` and moves `Ring.Growth`, `Dungeon.FirstPower / Growth / RoomMult` only; the gates are the stage medians |
| R2 | Character-as-body: playtests may want the pet to lead, or the camera to lock on | the `Move` command accepts any point (one client remote later); the camera stays default on purpose |
| R3 | Latency > 250 ms rejects some attacks | `Fighter.AttackSlack` / `AttackTolerance` are catalog knobs |
| R4 | BattleService surgery (encounter API + every mode branch) and the dungeon landing one wave later | the dungeon builds against the REAL BattleService (W3 after W2); one test per end path; the fail-safe; both Fable |
| R5 | Economy: late coins +15-20%, dungeon +8%, prices x1.25, free feeding | the sim with both flags is the W1 gate; `Dungeon.RoomSeconds` shrinks first; veterans read "Feeding is free: berries!" in the welcome toast |
| R6 | Berries as a second currency (a full basket wastes berries for an idle kid) | the 30-minute basket, "Basket full!" toast, berries from every poop by themselves |
| R7 | HomeRoam determinism across server and clients | the same shared module and Luau doubles; `RoamVersion` parks pets and hides coins on a mismatch; the static graph never depends on what is built |
| R8 | Up to 12 evolved pets in the owner's own home (~6.2K parts worst case) and 3 big followers 17 studs back | own home only; `GapPet` is one number |
| R9 | `Future` lighting on cheap phones | the light budget, the Low setting, a one-line revert |
| R10 | Skybox face order | Up / Dn are rotation-proof; Lf / Rt swapped = swap two ids |
| R11 | LobbyBuilder (3655 lines) and ArenaBuilder near the local limit | new code in `Court` / `Gates` helper tables; `count_locals.py` before hand-in |
| R12 | Windows shrink to 820 px on desktop: every window needs its narrow layout and new renders | the kit lands in W2; `client_p5gui_cover` at 4 sizes is the gate |
| R13 | Players with no saved obby win start on Easy only | the approved rule; every past win is kept |
| R14 | No music / sound / custom icons until the owner pastes ids | empty ids are silent / emoji; README steps |
| R15 | Dungeon part budget on phones (streaming OFF: every client holds every run) | `MAX_DUNGEONS` 8 by default (12 after the owner's MicroProfiler check), wave rooms 320 -> 260 via `Voxel` `MaxParts`, the client-total row of 10.3 |
| R16 | Test churn: 20 smoke files pin Trials, piles, 4-slot teams, the five portals | every file and owner is listed in 12.2; ids, remotes and chapter indices are kept |
| R17 | Rollout minutes with Phase 4 servers alive | section 9.3; "Publish, then Migrate to Latest Update" in the README |
| R18 | The server-held spawn: a client whose menu never fires `MenuPlay` (old client, script error) | the 90 s fallback spawn; `Config.MainMenu.Enabled = false` restores today's behaviour in one line |
| R19 | Slow pets make the character slow in battle (a Slime walks at 12, runs at 15.6) | `WalkMin 12` keeps every fighter close to the obby walk; Haste and the speed stat make fast pets feel fast; `WalkMult / WalkMin / WalkMax` are catalog knobs |

### Judge notes (second pass: what was rejected or changed on purpose)
* B1: option 1 (the character at the fighter's legal speed) was chosen over "every player fighter at max(MoveSpeed, RunSpeed) x 1.15" so the speed
  stat still matters; the leash is NOT meant to catch in-zone speed hacks (`leash_fix.py`: even x3 hackers reach their targets and stop before 3 s
  of excess accumulate): it catches leaving; speed hacks gain nothing because reach, hits and the drawn pet use the server fighter.
* M6: StreamingEnabled stays OFF. Turning it on is a game-wide change (every `workspace.X` client access needs WaitForChild / streaming signals)
  that does not fit Phase 5; the client-total budget and `MAX_DUNGEONS 8` bound the cost instead.
* M7: the server-held spawn was taken (the approved decision) instead of asking the player again; `PlayerService.lua` is owned by menu (W3).
* m8: no session lock (a DataService redesign, out of scope); the claim is corrected and the window stated; the Gems clamp absorbs it.
* m11: every pet within PET_NEAR is drawn evolved under a part budget rather than telling the player "a distance detail".
* m16 was adopted (Food converted into berries once), which also removes m7's change path and the leftover branch of Feed.
* M5: named per-owner blocks, not split files (the render_*.py loaders and the smoke boot stay unchanged).

### Phase 5 gate amendments (lead; these win over the sections above)
- W1: 5.1 `PartyExp` 0.85 -> 0.5, `RoomMult` {1.0, 1.1, 1.25}; 4.2 `BenchRegenCap` 0.6, `MeleeUptime` 0.75, `Specials` Solo 3; Ring `FirstPower` 4.0 /
  `Growth` 1.172 / `BossBump` 1.12 (all measured by `sim_battle`, 36 of 36 targets).
- W1: 3.3 Kitchen pad `padAt(-19, 21.5, -24, 29)` (22.5 overlapped the 16x10x10 Food Machine).
- W1: C10 first Prestige floor is 115 min for the player who also runs the Ring and the Dungeon (`--ring 0.08 --dungeon 0.1`: 118 min), 120 otherwise.
- W1: `TycoonCatalog.CoinPoint` / `HeapStage` stay as deprecated stubs until the W3 gate (HomeFx), then leave contract.json with the aliases.
- W2: 4.5 wire: `Start.Team.Cooldowns.Buff` is keyed by slot STRINGS ('2', '3'); a rejected `Order` echo goes only to its owner. 10.5: `Config.Lobby.PortalRingRadius` deleted.
- W4: 9.1 `Berries` merge: a session that converted Food -> berries in P5Home carries `BerriesMigrated`; applyDelta subtracts it when the STORED record was already P5Home-marked (two servers folding the same Phase 4 save never double-credit; the m15 Clears twin).
- W5: `Buff` / `Swap` take any benched slot 1..3 (the active fighter is refused); the boss room zone is 56x72 (`BattleCatalog.Dungeon.Zones.Boss`) with a `SpawnAnchor` at the foot of the stairs; the dungeon watchdog uses `DungeonService.MaxRunSeconds(floor)` (floor 1 room time 180 s counted); the boss room ends only at 0 living enemies; a member who quit cannot re-join that run; the Treasure chest goes only to members who qualified in a room; a leader who quits hands the party to the next live member; a join during a room-1/2 fight queues <= 20 s ("Joining when the room is cleared").

## Phase 6: Blender models only, back to the cute voxel look (contract; lead, 2026-10-20)

### 6.0 Player rulings (these win over everything, including the docs below)
1. **Blender models only.** No Roblox Part-built models and no Toolbox models: every model the player sees (pets,
   evolved forms, accessories, wings, hybrids, Stormfang, bosses, wild/enemy pets, sky dragon, NPCs, tokens, gates,
   Storm Altar, lobby props, clouds, floors, home stations, decor, arena, dungeon) becomes a Blender mesh (FBX ->
   Open Cloud Model asset -> MeshParts). Effects are not models: particles, lights, beams, trails, billboard/surface
   text and invisible gameplay volumes (colliders, zones, prompt anchors) stay Roblox instances.
2. **Style = the pre-Phase-5 look (Phase 4 release 7aa0df2) with finer voxels, more detail, more aesthetic.** Bright,
   cute, colourful, SmoothPlastic, no realistic textures, no Future lighting, no muted greys. Reference sheets:
   `docs/phase6/img/compare_*.png`, rules and numbers: `docs/phase6/style.md` section 4 (P4 palette, lighting LOOK).
   Approved previews: `docs/phase6/img/pebble_pup_preview.png`, `twilight_dragon_preview.png`, `cmp_portal.png`.
3. **Portals = the P4 round hoop gates, more detailed, but for the Phase 5 Gate Court modes** (the player changed the
   lobby from difficulty portals to mode portals). Mapping (recipe 4.10): Obby = hoop + 5-star crest; Ring = crowned
   arch (P4 Ring portal); Arena = hoop + crossed-swords crest (P4 Trials); Dungeon = hoop, purple, skull/key crest;
   Home = hoop, yellow, house crest; Altar = hoop, cyan, storm-bolt crest. Each gate keeps its Phase 5 position,
   prompts, pads, zones, signs and names. Same family for the arena gates, the dungeon portal, the home portal.
4. **Evolved pets look the best: auras and effects.** Evolution 1 and 2 get Blender aura meshes (rings, orbiting
   element bits, crowns of light, wing glows) plus effects (PetFx, 6.4): element particles, a soft PointLight, a
   pulse on Neon parts; second evolutions stronger than first. Must stay readable and cheap (budgets 6.5).
5. Uploads happen only in a NEW session that sees `ROBLOX_API_KEY` / `ROBLOX_CREATOR_ID`; the first real upload is
   the calibration asset and needs the player's OK in chat. Never fake an upload or an id.

### 6.1 The technical contract
`docs/phase6/recipe.md` section 4 IS the technical contract (pipeline layout 4.1, grain and budgets 4.2, part split
and names 4.3, colour 4.4, export + verify 4.5, manifest + keys 4.6, upload 4.7, runtime MeshLibrary 4.8, tests 4.9,
look 4.10, waves 4.11) with the amendments below. Background: `docs/phase6/research.md` (Open Cloud + loading facts,
cited), `docs/phase6/style.md`, `docs/phase6/kit-design.md` (the prototype kit, now in `blender/kit/`),
`docs/phase6/inv-*.md` (every model today with file:line, consumers and name contracts),
`docs/phase6/proto/` (prototype MeshLibrary.lua, upload_assets.py and their tests).

Amendments (lead; these win over the recipe):
* A1 **Fallback look (wave 1) is a revert, not a redesign**: palette, materials (SmoothPlastic), lighting values and
  blocky shapes back to 7aa0df2 per style.md 4; round primitives (Cylinder / Ball) go; the gate Part build becomes the
  P4 hoop family with the 6.0.3 mapping. The detail comes from the Blender meshes, so do not spend effort on new Part
  detail. Keep every name, prompt, zone, collider, attribute and position the code and tests use.
* A2 `default.project.json` Technology is already `ShadowMap` (lead, W0). LightingService goes back to the P4 LOOK
  values (style.md 4; Fallback = P4 sky-blue / peach, Custom = light pink when the sky ids are set). LightingStack stays.
* A3 Ids: `src/shared/MeshIds.lua` (generated, numbers only) and `Config.MeshAssets = require(script.Parent.MeshIds)`
  exist (lead, W0). Manifests: `src/shared/MeshManifests/<key>.lua` (generated by the kit, one ModuleScript per key in
  a plain Rojo folder; MeshLibrary requires a key's manifest by name, lazily).
* A4 Build outputs: `blender/out/` is NOT committed (`.gitignore`): FBX, previews and `.tris.json.gz` are rebuilt by
  `blender/build_all.py` (deterministic: same input = same `contentHash`). Committed: kit code, catalogs, generated
  `src/shared/MeshManifests/*.lua`, `blender/meshes.json` (index with hashes) and a few review PNGs under
  `docs/phase6/review/<class>/` (<= 400 KB each, <= 12 per class).
* A5 Catalog split (so builders never edit the same file): `blender/catalog/<class>.json` per art class (pets,
  evolved, creatures, gates, lobby, home, arenadungeon); `build_all.py --class <c>` / `--key <k>` / `--all`.
* A6 Effects for evolved pets: `src/shared/PetFx.lua` (stub + call already in `PetBuilder.Build`, lead W0). PetFx works
  on any pet model (Part or mesh): it creates `Body.PetFx` (a Folder of Attachments under the invisible `Body` root)
  with ParticleEmitters / PointLight / optional Beams; aura MESHES are pet parts (group `Aura`, kind `orbit`, from the
  evolved art keys) and PetFx never creates Parts. Respect `GraphicsQuality` (Low = no particles, light only) and the
  Detail option (Low = half rates). No per-frame Lua: emitters + the existing Animate orbit/pulse only.
* A7 Client mesh dressing of world builders (recipe 4.8 "World path"): the builder tags a static decoration subtree
  with `MeshLibrary.Tag(target, key, look, keep)`; the client `Dress`es it. Builders own their Tag calls.
* A8 Ownership is by files (6.3). Shared tool files (`tools/smoke.py`, `tools/dump_model.lua`, `tools/render_model.py`
  callers): only your own registration line / `-- [owner: <key>]` block.

### 6.2 Keys (mesh asset names; recipe 4.6, extended)
`cal_axes`; `pet_<species>[_low]` (15); `wing_<style>_<L|R>[_low]` (7 styles); `acc_<name>[_low]` (8 incl. halo);
`hyb_<feature>`; `lid` (procedural, part of the body key); `evo1_<petId>[_low]` (33), `evo2_<petId>[_low]` (16);
`evowing_<style>_<L|R>[_low]`; `aura_<kind>[_low]` (element aura meshes); `star_gold`; `boss_<id>_<joint>`;
`dragon_<piece>`; `npc_pedestal`; `token_<kind>`; `fx_<shield|ice|arrow>`; `gate_<obby|ring|arena|dungeon|home|altar>`;
`gate_arena_<n>`, `portal_dungeon`, `portal_home`; `prop_<name>`; `cloud_<size>_<v>`; `floor_<area>_<i>`;
`home_<station>_<level>`; `arena_<piece>`; `dungeon_<room|piece>`. Exact lists live in the catalogs.

> Player ruling (2026-10-20, Phase 6 W2b): NO Home gate in the lobby Gate Court (5 gates: Obby, Dungeon, Ring, Arena, Altar). Going home = the Home window hero button "Go home" / "Claim a home" (MenuController). Every BuildGate gate is animated client-side by src/client/Controllers/PortalFxController.lua (Neon Glow/Swirl/Gem + GlowCore light only; Low graphics = static). art-gates may skip gate_home.

### 6.3 Waves and ownership
| Wave | Key | Files (owns) | Task |
|---|---|---|---|
| W0 | lead | ARCHITECTURE_V3, BUILD_STATE, default.project.json, Config, MeshIds stub, PetFx stub + PetBuilder.Build call, README step 5, docs/phase6 | DONE |
| W1 | look-lobby | WorldStyle.lua, LobbyBuilder.lua, LightingService.lua, StormAltar.lua (look only), tools/smoke_p5_world.lua, smoke_p2_final pinned asserts (not the checklist) | A1/A2 revert for the lobby, gates (P4 hoop family, 6.0.3), altar, lighting; tests updated |
| W1 | look-places | HomeBuilder.lua, ArenaBuilder.lua, DungeonBuilder.lua, their smoke files | A1 revert for home plots, arena, dungeon (incl. arena gates / dungeon portal / home portal use of the gate kit) |
| W1 | kit | blender/** (kit, catalog/, build_all.py), tools/mesh_names.py, tools/mesh_budget.py, tools/render_model.py + tools/dump_model.lua mesh path, read-only hooks in PetBuilder.lua (`_Blueprint`, Anchors) and BossBuilder.lua, .gitignore line for blender/out | recipe 4.1/4.2/4.5/4.6 + bridge + cal_axes + pets.json skeleton; build Dog/Cat/Dragon through the bridge as the golden path |
| W1 | runtime | src/shared/MeshLibrary.lua, tools/upload_assets.py (+ tests), tools/check.mjs rules, tools/smoke_p6_mesh.lua, tools/fixtures/mesh/, smoke.py line | recipe 4.7/4.8/4.9 core: load/fit/validate, templates, Tag/Dress, Assemble skeleton, fixtures from the kit's Dog manifest |
| W1 | evofx | src/shared/PetFx.lua, tools/smoke_p6_evofx.lua, render scenes | A6 effects on today's Part pets (visible now) |
| W2 | art-pets | blender/catalog/pets.json, blender/kit/detail/pets*, review PNGs | 15 species + wings + accessories + hybrid features + lids, High/Low, previews >= 3 rounds |
| W2 | art-evolved | blender/catalog/evolved.json, kit/detail/evolved*, aura meshes | evo1 x33, evo2 x16, evo wings, auras (6.0.4), budgets |
| W2 | art-creatures | blender/catalog/creatures.json, BossBuilder.lua + SkyDragonController.lua + NpcService.lua + TokenLook.lua mesh paths | bosses, sky dragon, NPC pedestals, tokens, battle fx cubes |
| W2 | art-gates | blender/catalog/gates.json, kit/props/gates*, WorldStyle.lua Tag calls | 6 Gate Court gates + arena gates + dungeon/home portals + altar gate |
| W2 | art-lobby | blender/catalog/lobby.json, kit/props/lobby*, LobbyBuilder.lua + StormAltar.lua Tag calls | lobby props, clouds, floors, shop, plots, garden, altar island, course pieces |
| W2 | art-home | blender/catalog/home.json, kit/props/home*, HomeBuilder.lua Tag calls | stations per level, house tiers, fence, fountain, decor, pads |
| W2 | art-arenadungeon | blender/catalog/arenadungeon.json, kit/props/arena*/dungeon*, ArenaBuilder.lua + DungeonBuilder.lua Tag calls | arena island, colosseum, ring, stands, bridge, dungeon rooms + props |
| W2 | runtime-pets | PetBuilder.lua (mesh path), MeshLibrary.lua (Assemble, effects hookup), PetController / HomeFx / CloudUI / BattleController / EvolutionFx rebuild-on-Changed lines | recipe 4.8 pet path, both-modes test runs |
| W3 | review + docs + ship | as assigned | review/verify/fix, README Phase 6 + owner checklist, full suite both modes, rbxlx, merge |
| W4 | upload (new session) | MeshIds.lua via the tool | calibration, one pet live, batches (recipe 6) |

### 6.4 PetFx (A6) details
* Per element (Config.Elements order): particle texture-free shapes only (default ParticleEmitter sprite, Squash,
  LightEmission), colours from the pet's Look Glow/GlowB or element palette; stage 1: 1 emitter + light 0.6
  brightness range 6; stage 2: 2 emitters + light 1.0 range 8 + Neon pulse (PB_Pulse) on aura parts.
* Total emitter Rate per pet <= 12 (stage 2, High), <= 4 on Low detail; none when GraphicsQuality is Low.
* Never in viewports (CloudUI / Index / Fusion) unless the caller passes `opts.Fx = true` (viewports ignore particles
  anyway: skip creating them). Battle units keep them.

### 6.5 Budgets
recipe 4.2 table; plus the evolved auras count inside the evolved budget; busiest phone view <= 300k tris.
W3 amendment (lead, from perf-plots): the busiest contract view (4 plots seen from the plaza, 340-stud ring) applies
the client plot LOD (HomeFx: High < 120 studs, `_low` keys 120-200, Far >= 200 keeps only the house + plot base on
`_low`; 20-stud hysteresis, checked every 0.5 s) and must be <= 300k tris; the sampled cross-plaza phone view
(113 degrees, any yaw) <= 320k. The old "400 parts" is replaced by <= 3000 MeshParts in view and <= 700 distinct
(mesh, material) batches (Roblox instances identical meshes; the 4.3 name contract alone makes pet sets 1395 parts).
`tools/mesh_budget.py --lod-check` enforces it; confirm in Studio with the MicroProfiler after W4.

### 6.6 Tests
recipe 4.9. Every wave keeps `tools/smoke.py --quick` green in the default (no ids) mode; W2 adds the mesh-fixture
mode runs. `tools/run_checks.sh` full at W3.

## Dungeon fixes (player request after Phase 6; branch `v3-dungeon-fixes`; plan `docs/dungeon-fixes/plan.md`)

These rulings amend sections 4 and 5 of Phase 5 (they win over the older text there).
* **Enemies drawn (bug):** the client adds the units of `Wave` events (`Units.AddList`), not only `Spawn` / `Start`; the dungeon
  encounter centre is the room FLOOR (`RoomInfo.ZoneFloor`, `FloorY` = floor top); enemies use the Wild look.
* **Doors (5.3):** no timer moves a group any more (HallSeconds / Intermission + DoorTime / boss -> treasure are gone). After a clear
  the route leads to the next room's closed `Door_Entrance`; its `EnterPrompt` (E, `DungeonAction "Enter"`) records
  `run.Confirm[userId]`; when every member still in the run (Downed included) confirmed, `DungeonState("Fade", { Out 0.45, Hold
  0.35, In 0.45, Room })` then the room is entered ONCE (`Dg.transit` / `Dg.finishTransit`, `run.Transit` + `TransitSeq` lock).
  Run payload: `Confirmed`, `NeedConfirm`, `EnterOpen`, `Next`. `MaxRunSeconds` no longer counts DoorTime / HallSeconds.
* **Arrival (4.x):** every enemy added after the start (waves, escorts, raid adds) arrives for `BattleCatalog.Fighter.ArriveSeconds`
  1.2 s: it does not act, cannot be hit or targeted; unit info carries `Arrive`; a dungeon wave adds 1.2 s to the time limit.
  Client: `EvolutionFx.Arrive(pivot, opts)` (effects only), the model appears at the flash.
* **Attack (4.4):** a player's fighter AUTO-ATTACKS every step in every mode (lock if in reach, else nearest in reach; never moves);
  the `Attack` command only directs (`Attack(id)` locks, `Attack()` locks / cycles the nearest; echo `Order{order="Attack",
  target}`); `Fighter.AutoRepeat = false`; the ATTACK button reads "PICK TARGET".
* **Dash (4.4):** in battle Shift / RightShift / ButtonB = the PET's dash (`MovementController.SetPetDash`): no character
  impulse, no stamina; sim Dash unchanged; event `Dash { unit, dir = {dx, dz}, target }`; run stays on Ctrl.
* **E (4.4):** ELEMENT's E passes to a visible ProximityPrompt (exit, chest); gamepad Y keeps ELEMENT.
* **Mouse lock:** setting `MouseLock` (bool, default false, L key) + `src/client/MouseLock.lua` (LockCenter after the camera; any
  Dock window, main menu, loading, result cards, tutorial card, a focused TextBox = cursor free).
* **Healing (4.x):** no passive heal in combat (`BenchRegenPerSecond` / `BenchRegenCap` 0, code removed; wave gaps count). A player's
  Heal special heals the fighter AND both benched pets; the Heal helper buff heals the fighter and the other benched pet.
  Raid retune: `BossRules.DamageGroup.Min` 0.55 -> 0.35, lava_golem `LingerDamage` 0.03 -> 0.015.
