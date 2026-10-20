# tools

Checks and helpers for Nimbus Climb. The test pipeline (`run_checks.sh`, `syntax.py`, `check.mjs`, `smoke.py`) is
described in the "Tests" section of the main `README.md`.

## Place verifier: is the place file up to date?

`verify_place.py` checks a Rojo-built place against `src/` (Python 3 only, no other packages): every
`src/**/*.lua` must be in the place at its path with the class Rojo 7 gives it (`*.server.lua` Script,
`*.client.lua` LocalScript, any other `.lua` ModuleScript) and a Source identical to the file on disk; sub-folders
must be Folders, no two siblings may share a name, the place may hold no script that `src/` does not have, and the
`$properties` of `default.project.json` (the lighting technology) must be there. It names every mismatch (with the
first differing line) and exits 1, so run it after every rebuild:

```sh
rojo build default.project.json -o play/NimbusClimb.rbxlx
python3 tools/verify_place.py                     # or: python3 tools/verify_place.py other.rbxlx
```

## Tycoon economy simulation

`sim_tycoon.py` replays the Phase 5 tycoon homes (11 stations, TycoonCatalog Version 5: roaming garden pets that poop
Cloud Cash, the 40-level Berry Farm, berries and the Berry Basket, feeding that spends berries, EVOLVE at 20 / 50 with
the level bonus x1.5 / x1.875, pets growing to level 100, prestige with x1.5 prices per star, the Vault's offline
coins) for an active player and 120 typical ones (3 prestige runs each), prints when each milestone is reached (first
paid pad, Villa, first prestige, first EVOLVE, later runs, prestige Gems per hour) and checks the 13 pacing targets of
ARCHITECTURE_V3.md "Phase 4 build contract" 3.12 / 8.3 (kept by "Phase 5 build contract" 12.3): it must print
`ALL TARGETS MET`. Its constants block mirrors `src/shared/TycoonCatalog.lua` (and the pet data of `PetCatalog` /
`Config`): change both together (the smoke test `p2_economy`, `tools/smoke_p4_economy.lua`, fails while they
disagree).

```sh
python3 tools/sim_tycoon.py                          # timeline of one player + Monte Carlo + targets (~20 s)
python3 tools/sim_tycoon.py --quiet                  # summary only
python3 tools/sim_tycoon.py --ring 0.08              # a kid who climbs the Champion Ring regularly (+8% Cash)
python3 tools/sim_tycoon.py --dungeon 0.1            # a Dungeon run every 10 minutes (the room Cash + the chest)
python3 tools/sim_tycoon.py --ring 0.08 --dungeon 0.1   # the Phase 5 gate run: must print ALL TARGETS MET (C10)
python3 tools/sim_tycoon.py --mode combat            # the timeline player only gets Combat pets
python3 tools/sim_tycoon.py --check                  # catalog == sim: tables, pads, income, berries, the fold (lupa)
python3 tools/sim_tycoon.py --migrate5               # 300 Phase 4 homes on their first Phase 5 load (the fold)
python3 tools/sim_tycoon.py --plan yard.png          # the yard from above: stations, pads, the garden (lupa + Pillow)
```

* `--ring R`: Champion Ring Cash as a share of garden income (0 by default). `--dungeon N`: Dungeon runs per minute
  of play (0.1 = one every 10 minutes; a run takes 3 minutes + 15 s per floor away from the yard and pays the room
  Cash of 5.2 plus the expected chest). Both start at minute 30, after the tutorial's home chapter. The C10 floor of
  the first Prestige is 115 minutes for the player who runs both (120 otherwise). `--feed` is kept for old command
  lines but unused since Phase 5 (feeding spends berries, not Cash).
* `--check` loads the real catalog (and PetCatalog) with lupa and compares every constant, `AvailablePads` (incl.
  `PriceAt` with stars and `LegacyPrices`), `SignedPads`, `FoodOf`, `GardenSlots`, `IncomePerSecond`, `PileSeconds`,
  `ScoopRadius`, `BasketCap`, `FeedBerries`, `OfflineEarnings`, `FoldLegacy` and `StationsAfterPrestige` on random
  homes, `FeedXp` / `TrainCost` / `TrainSeconds` at every level and rank, and runs `Validate()`.
* `--migrate5` imports the frozen Phase 4 sim (`tools/fixtures/sim_tycoon_phase4.py`) by path, stops 300 Phase 4 homes
  (18 stations) at random moments, folds them with the Phase 5 rules (plants -> Berry Farm with the food floor, the
  Coin Magnet -> LegacyMagnet, old decor -> DecorCredit) and gates on: Home Level never down, no dead end, and a median
  time-to-the-next-pad ratio <= 1.0 in every house tier / star bucket. (The Phase 3 `--migrate` is gone.)
* Exit status 1 when a target is missed (or `--check` / `--migrate5` finds a problem).

## Battle balance simulation (Phase 5)

`sim_battle.lua` runs the **real** battle engine (`src/shared/BattleSim.lua` on the numbers of
`src/shared/BattleCatalog.lua`, with PetCatalog / PetKeys / TycoonCatalog) inside the Roblox mock under lupa, like
`smoke.py`, and prints a balance report with `TARGET ok / MISS` lines for the Phase 5 battle system (one fighter you
steer, two helpers with buffs, three lives; ARCHITECTURE_V3.md "Phase 5 build contract" 12.3). It boots the mock by
itself (run it from the repo root), so no Python wrapper is needed beyond lupa:

```sh
python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
SIM_BATTLE="quick only=duels,raids" python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
```

* `SIM_BATTLE` options: `quick` (fewer seeds, ~20 s per section) or `full` (the default), `seeds=N`, `only=a,b`,
  `verbose` (section timings). The sections:

  | Section | What it measures (targets) |
  |---|---|
  | `roster` | every pet's battle numbers (UnitStats, role, walk / run speed, buff, element attack) |
  | `fighter` | the played kit against a passive NPC of k x its power (kit factor 1.25-1.7); mirror fights 6-45 s, none at the Ring's 90 s |
  | `support` | Support (Economy) pets: DPS ratio 0.65-0.75 of Combat pets; a Support fighter beats 2 x puddle_frog L8 in 10-60 % of seeds |
  | `duels` | mirror duels per stage with scripted players on both sides: fair (40-60 % overall, 30-70 % per stage), no draws |
  | `raids` | 1 / 4 / 8 / 16 dodging fighters finish every boss in 100-240 s; no one-shots; joins / leaves; idle alts |
  | `ring` | rounds 1-3 >= 95 % for every single level-1 rollable pet; the stage medians S1 16 .. S10 51 (+-2) |
  | `dungeon` | floor 1 for the 12 single level-1 pets (100 %); the stage ladder (monotonic, S10 >= floor 10); a 4-party gains a floor |
  | `training` | trained / evolved TeamPower ratios; trained mirror duels fair; trained raids 100-240 s |
  | `move` | the character patterns (random targets + an r 14 circle) at the legal run speed with a 200 ms feed delay for mochi_slime L1 / sunbeam_bear L20 / stormfang L50: the server fighter keeps up (gap <= 0.5 stud, zero leashes); a straight run-off is leashed after 3 s |
  | `perf` | a 16-fighter raid with minion waves steps in well under 1 ms |
  | `progression` | the XP and Cash behind each stage, `Validate()` |

* Change a number in `BattleCatalog` -> re-run the sim. The smoke scenario `p5battle_balance`
  (`tools/smoke_p5_battlecore.lua`) loads this file as a library (`SIM_BATTLE_LIBRARY = true`) and runs a short
  subset; `p5dgn_balance` (`tools/smoke_p5_dungeon.lua`) uses `SIM.Stages`, `SIM.team`, `SIM.Player` and
  `SIM.dungeonFloor`.
* The scripted player (`SIM.Player`) moves a simulated character at the fighter's legal run speed (`SpeedOf`), feeds
  `Move`, presses ATTACK / ELEMENT / SPECIAL / the buffs, swaps and dashes out of wind-ups and telegraphs after a
  human-ish delay (options: dodge share, delay steps, buffs, swap, element). `Auto = true` teams are driven by the
  engine's own AI (tests only; BattleService never sets it). The Phase 3 / 4 sections (`trials`, `dodge`, `specials`,
  `extremes`, `elements`, `level100`) are gone with the Trials and RETREAT.

## Model renderer: see the voxel art without Studio

`render_model.py` builds a model with the **real** game modules (inside the same lupa + `robloxmock.lua` world that
`smoke.py` boots, via `dump_model.lua`) and draws it with a small numpy + Pillow rasteriser: orthographic views,
flat Lambert shading with a key light from the upper front-left, Neon glowing, Glass/transparent parts blended,
thin outlines on silhouettes. Needs `lupa`, `numpy` and `Pillow`. A pet takes about a second, the whole lobby a few.

```sh
python3 tools/render_model.py pet:stormfang -o stormfang.png          # 2x2 sheet: front, 3/4, side, back
python3 tools/render_model.py pet:cloudy_dragon:Low -o low.png        # Low detail (followers of other players)
python3 tools/render_model.py species:Fox -o fox.png                  # a species with a neutral sample look
python3 tools/render_model.py --grid -o pets.png                      # every catalog pet, labelled (pets:Low, species)
python3 tools/render_model.py token:golden --views front,side -o coin.png
python3 tools/render_model.py skydragon --views side,top -o dragon.png
python3 tools/render_model.py lobby --views threequarter,top --size 1400 -o lobby.png
python3 tools/render_model.py lobby --box -125,270,-125,125,360,125 --views top -o plaza.png   # crop (world studs)
python3 tools/render_model.py lobby+npcs+storm-altar --views top -o village.png
python3 tools/render_model.py module:server/Services/LobbyBuilder:Build -o any.png   # generic; add :lobby to pass LobbyInfo
```

* Evolved forms (`PetBuilder.Build(def, { Evolved = true })`): `pet:<id>:Evolved`, `pet:<id>:EvolvedLow`, and the sheet
  `python3 tools/render_model.py --grid pets:Evolved --views hero --margin 0.95 -o evolved.png` (the `hero` view is
  lower and more from the side, `--margin` lets the model fill more of each cell).
* Second evolutions (`PetBuilder.Build(def, { Evolved = 2 })`, Epic pets and up): `pet:<id>:Evolved2`,
  `pet:<id>:Evolved2Low`, and the sheet of the 13 pets that have one:
  `python3 tools/render_model.py --grid pets:Evolved2 --views hero --margin 0.95 -o evolved2.png`.
* Targets: `pet:<id>[:High|Low]`, `species:<Species>[:High|Low]`, `lobby`, `npcs`, `storm-altar`, `skydragon`,
  `token[:golden]`, `module:<path>:<func>[:lobby]`, several joined with `+`, or a `.json` dump from `--json`
  (`storm-altar` needs `server/Services/StormAltar.lua`; `npcs` and `storm-altar` build the lobby first).
* Phase 3 targets: `arena` (workspace.BattleArena from `ArenaBuilder.Build(lobbyInfo)`: island, colosseum, duel rings,
  boards and the bridge (since Phase 5 the Ring and Arena gates stand in the Gate Court); `lobby+arena` with `--box`
  shows the plaza link) and `pocket[:<index>]` (one private battle pocket from `ArenaBuilder.BuildPocket`).
* Phase 3 bosses (`shared/BossBuilder.lua`): `boss:<bossId>[:<pose>[:High|Low]]` (pose Idle | Windup | Attack |
  Basic | Enrage | Hurt | Down at its strongest moment; `Windup/chain` picks the attack id, a trailing `!` shows it
  enraged, e.g. `boss:storm_titan:Attack/slam`, `boss:lava_golem:Enrage!`) and `bosses[:<pose>[:Low]]` (the roster).
* Phase 3 battles (`client/Controllers/BattleController.lua`, client world): `battle[:<duel|raid>[:<seconds>[:specials]]]`
  steps a real BattleSim at 10 Hz and feeds it to the real BattleController the way BattleService sends it, then dumps
  what the client drew (`workspace.ClientBattle`: unit models, boss, telegraphs, effects). `battle:raid:9` catches the
  boss's first telegraph filling; `:specials` fills the local team's meters and casts every special just before the
  dump, e.g. `python3 tools/render_model.py battle:raid:9:specials --views threequarter,top --size 1400 -o raid.png`.
* Phase 4 targets (homes where pets make the money): `home:<StationId>[:<level>|all[:<open>]]` draws one home station
  with HomeBuilder (`Press1`..`Press4` are the food plants Berry Bush / Carrot Patch / Cloud Melons / Starfruit Tree,
  `Collector` the Coin Magnet, `Kitchen` the Food Machine, `Gym` the Training Place, `Garden` with `<open>` places),
  `homerow:<StationId>[:<levels>]` puts several levels side by side, `homegardens[:<level>[:<opens>]]` several open
  counts; `homegarden[:<open>[:<level>]]` and `hometrain[:<level>]` (client world) are the Pet Garden with a pet on
  every open place and its coin piles, and the Training Place with a pet on every mat, drawn by the real `HomeFx`;
  `pocket:ring` is the Champion Ring pocket (`ArenaBuilder.BuildPocket(1, "Ring")`) and `portal:home` the home portal
  `HomePortalFx` draws, e.g. `python3 tools/render_model.py homegarden:12:8 --views threequarter,top -o garden.png`.
* Phase 5 targets: `lobby` is the whole lobby with the **Gate Court** (render it `--views top`), `gates` the five gates
  and the court alone (Phase 6: no Home gate), `gate:<Obby|Dungeon|Ring|Arena|Altar>` one gate with its pad (`WorldStyle.BuildGate`);
  `home:Press1:<1..40>` the Berry Farm at a level (and `home:<Id>:<level>` every other station), `homerow:House:1,2,3,4` /
  `homerow:DecorFountain:1,2,3` / `homerow:DecorFence:1,2,3` the tiers side by side, `homeplot:SkyCastle:pads` the whole
  plot, `homegarden[:<open>[:<level>]]` the Pet Garden with its 12 beds and the Food Bowl; `homeroam[:<t>]` (client world)
  a Sky Castle plot with 12 roaming pets and their Cloud Cash at time `t`, `followers[:walk]` another player's three
  followers (small, evolved, second evolution); the Dungeon (`DungeonBuilder`): `dungeon[:<kind>[:<variant>]]` one room
  template (Hall / Cellar / Cave / Bridge / Throne / Entrance / Corridor / Treasure), `dungeon:room:<kind>`,
  `dungeon:boss`, `dungeon:run[:<floor>[:<seed>]]` a built run as DungeonService places it (hall + corridors + rooms 1-2),
  `dungeon:floor[:<floor>]` every piece of a run at once and `dungeon:portal` the Dungeon gate; the renders cut away the
  ceiling and the two camera-side walls, e.g. `python3 tools/render_model.py dungeon:run:3 --views threequarter,top`.
  `pocket:ring` stays; the Trial pocket is gone. The sky itself is painted in Blender:
  `/tmp/claude-0/bpyenv/bin/python blender/sky/render_sky.py` (bpy 5.2, about 2 minutes) writes `branding/sky/*.png` and
  `blender/sky/preview_cross.png`.
* Views: `front` looks the model in the face (a pet's LookVector), `side` at its right flank (face to the right),
  `back`, `left`, `threequarter`, `top` (front at the bottom). All views of a sheet share one scale.
* Output: the PNG (part count in the bottom-right corner) plus the part count and bounding box on stdout.
  `--json dump.json` keeps the part dump (position, rotation matrix, size, colour, material, transparency, shape);
  `--dump-only` skips the drawing. Other flags: `--size`, `--cell` (grid), `--ss` (supersampling), `--outline`,
  `--echo` (show the game's print/warn output).
* Balls and cylinders are drawn as polyhedra and textured materials (Grass, Cobblestone...) as flat colour, so the
  render shows shapes, colours and proportions, not Roblox's exact lighting.

## GUI renderer: see the 2D UI without Studio

`render_gui.py` boots the **real** client (`Main.client.lua` and every controller) in the same lupa + `robloxmock.lua`
world `smoke.py` uses, at the screen size you ask for, drives it into a scenario with the fake server events the smoke
tests send (`dump_gui.lua`), dumps every visible GuiObject of PlayerGui and draws the dump with Pillow. The mock lays
out UDim2 / AnchorPoint / AutomaticSize / UIListLayout / UIGridLayout / UIPadding / UIScale / UIAspectRatio /
UISizeConstraint; the renderer measures text with real fonts (the mock's layout engine is handed the same metrics, so
auto-sized pills fit their text) and draws ScreenGuis by DisplayOrder, siblings by ZIndex, rounded corners,
UIStrokes (box and text), UIGradients, legacy borders, TextScaled + UITextSizeConstraint, wrapping, truncation,
rich-text colours, the typewriter limit, colour emoji, Rotation, CanvasGroups, clipping and scroll bars. A dump takes
well under a second, a 1080p render one to three seconds.

```sh
python3 tools/render_gui.py lobby -o lobby.png                       # idle lobby HUD at 1920x1080
python3 tools/render_gui.py match --size 1280x720 -o match.png       # match panel, damaged HP bar, drained stamina
python3 tools/render_gui.py menu:Index:Mythic -o index.png           # a window (Inventory, Pets, Index, Shop, Stats)
python3 tools/render_gui.py tutorial:3 --grid -o tutorial.png        # 1920x1080, 1280x720, 390x844, 844x390 in one sheet
python3 tools/render_gui.py match --crop 0,920,420,160 --scale 3 -o hp.png   # zoom into the HP / stamina bars
python3 tools/render_gui.py npc --mark-small --boxes -o npc.png      # red frames on small text, every box outlined
python3 tools/render_gui.py gallery -o gallery.png                   # renderer check: one cell per feature, known values
python3 tools/render_gui.py portal:Hard:2 -o portal.png              # a portal's world GUIs (billboard + countdown face)
```

* Scenarios: `lobby`, `title` (title card up), `match` / `match:hit` (a quarter second after a hit), `countdown`,
  `party` (portal party panel), `results`, `menu:<Window>[:<Tab or Index group>]`, `tutorial[:<step>]`, `npc[:<n>]`,
  `dev` (owner panel), `toasts`, `gallery`, `portal[:<Id>[:<players>[:<studs>]]]`, or a `.json` dump written earlier
  with `--json`. `--list` prints them.
* `battle[:<mode>[:<phase>]]` (BattleController): the battle HUD fed by a real BattleSim stepped at 10 Hz through
  BattleState. Since Phase 5 this is the fighter / helpers HUD (see the Phase 5 scenarios below); the Phase 3 team rows,
  ATTACK / RETREAT and the regroup countdown are gone. e.g. `python3 tools/render_gui.py battle:raid:ready --grid -o raid.png`.
* `arena[:<view>[:<arg>]]` (Phase 3 UI: MenuController's Team window, ArenaController): a profile with a battle team,
  trophies and a few Dungeon floors cleared, then `team` (default), `newteam` (empty presets),
  `duels` / `raid` / `leaders` (the Arena panel's tabs, with two
  more players to challenge, a running raid, Double Rewards) or `side` (no window: the duel invite, the queue, the raid
  join card and the event countdown at the right edge); e.g. `python3 tools/render_gui.py arena:duels --grid`.
* Phase 4 scenarios (a shared care profile: Prestige 1, a Garden with 4 places, plants, the Food Machine and the
  Training Place): `home[:coins]` (the Home window with its Pet Garden card; `:coins` = a home from before Phase 4
  with kept places, old prices and a big pile of coins), `feed` (CareController's Food Machine list: garden pets first,
  the Berry Basket, a pet ready to EVOLVE, a level-100 pet), `garden[:<slot>]` (the garden picker), `train[:<key>]` (the
  Training Place window with a running timer and Stop), `evolve` (the EVOLVE confirm), `ring[:new|record]` (the
  Champion Ring window), `petcards` (the floating pet cards of every mode mirrored flat) and the ring HUD
  `battle:ring:<fight|next|result|record><round>` (e.g. `battle:ring:next8` is the "Round 8 won! ... Round 9 in 3"
  card). `menu:<Window>[:<Tab>[:<Action>[:<Key>]]]` passes an Action / Key along (e.g. `menu:Pets:Pets:Evolve:<key>`).
* Phase 5 scenarios (`dump_gui.lua`, one named block per owner): `neon[:window|hud|party]` (the Neon kit gallery; a
  docked side panel; the HUD with the stamina ticks; the obby party panel with the level row and CHANGE), the battle HUD
  `battle[:fighter|raid|dungeon|duel|spectate|ring[:<phase>]]` with the phases `fight` / `ready` / `result` / `lost` /
  `cleared` (fighter card, helper portraits, enemy rows, the action cluster), `home` / `feed` / `garden` / `train` /
  `team` / `looks[:epic]` / `stats` / `fusion[:mix]` (the care windows on NeonKit: the Home strip, the one-button Food
  Machine with the Berry Basket, the Team of 3 with FIGHTER / HELPER, evolved looks), `mainmenu[:updates|credits]`,
  `loading` and `settings[:hud]` (the loading screen, the main menu before PLAY and the settings window),
  `dungeon[:lobby|party|leader|countdown|run|loot|treasure|end|wipe]` (DungeonController's window, run card and end
  card), `obby[:picker|party|toast]` (ObbyController's level picker) and `arena[:team|duels|raid|leaders|side|practice|dungeon]`
  (the docked Arena windows; `arena:trials` is gone), e.g. `python3 tools/render_gui.py dungeon:leader --grid`. Render
  every window at 1920x1080, 1280x720, 390x844 and 844x390 (`--grid`): `client_p5gui_cover` fails any window that
  covers more than 60 % of the screen. Scenarios the lead has not added to `render_gui.py --list` yet still render
  by name.
* `arenaboards[:<countdown|raid|idle>]` (Phase 3, ArenaBuilder) draws the Battle Arena's world GUIs instead of the HUD,
  like `portal`: the real LobbyBuilder + ArenaBuilder build the arena (as the server), a sample ArenaState goes through
  `ApplyArenaState` (`countdown`: the next Boss Raid in 1:35 + Double Rewards, `raid`: a live raid with its HP bar,
  `idle`: the next raid 20 minutes away), then every SurfaceGui (event board, trophy leaderboard, gate and arch signs,
  both faces) is drawn at its on-screen size from 30 studs and every BillboardGui (duel pad tags) at
  its pixel size, one copy of each; e.g. `python3 tools/render_gui.py arenaboards:raid -o boards.png`.
* `portal` draws world GUIs instead of the HUD: the real LobbyBuilder + PortalService run (as the server) with
  `players` members on the pad (default 1 on Medium), and the portal's GUIs are mirrored flat into a ScreenGui: the
  pixel billboard at its own size (it keeps that size on screen), the eye-level countdown face (a SurfaceGui) at the
  size it has on this screen from `studs` away (default 36: a friend just outside the lock walls with the default
  camera; 70 degree vertical field of view) over a sketch of the gate's swirl, and the face's canvas at 1:1. The
  report's smallest text is then the face's real on-screen size from that distance.
* Screen: `--size WxH` (default 1920x1080). The smaller side <= 500 px boots a touch device (RUN / DASH buttons,
  raised HUD); `--touch` / `--no-touch` override (use `--touch` for tablets). Roblox's top bar (the 58 px inset) and,
  on touch devices, its thumbstick and jump button are sketched as faint ghosts (`--no-chrome` hides them).
* Output: the PNG plus a report on stdout: object and text counts, the game's script errors, every text under the
  readability floor (15 px on screens >= 1000 px tall, 14 px below) and the **smallest on-screen text** with its path.
  `--json FILE` keeps the dump (absolute boxes, ZIndex, colours, corner radius, strokes, gradients, text properties).
  Other flags: `--bg lobby|grey|sky|dark`, `--ss` (supersampling), `--no-labels`, `--echo`, `-v` (font mapping, warns).
* Fonts are substitutes found with `fc-list`: a bold rounded sans when installed (Fredoka, Nunito, Varela Round...),
  otherwise Inter, then DejaVu Sans; symbols fall back to DejaVu, emoji to Noto Color Emoji. Glyph shapes and widths
  differ a little from Roblox's FredokaOne / Gotham / Builder Sans, so a text that only just fits (or only just gets
  truncated) deserves a look in Studio. ImageLabels and ViewportFrames are labelled placeholders (a viewport shows a
  blob tinted by ImageColor3, so Index silhouettes come out black); animations are frozen at the moment of the dump.
* `tools/smoke_polish_guitool.lua` (smoke scenario `client_gui_dump`) checks the dumper against the live client UI
  and the gallery.

## Smoke test files

`smoke.py` loads every `tools/smoke_*.lua` file it lists (it fails when a `smoke_*.lua` file is not wired in) and runs
their scenarios in the server, client or phone world; `python3 tools/smoke.py --list` prints every scenario and
`--only a,b` runs a few (handy while you work; a full `--quick` run takes about 20-30 minutes). The Phase 5 files
(ARCHITECTURE_V3.md "Phase 5 build contract" 12.1; each owner registers its own line in `smoke.py`):

| File | What it checks |
|---|---|
| `smoke_p5_data.lua` | the Phase 5 save: teams of 3 (a 4-key preset loads with 3), the Dungeon record (merge, the one-time Trial -> floor migration), berries, settings, the home fold's data step, the Phase 4 -> 5 rollout against the frozen `tools/fixtures/DataService_phase4.lua` |
| `smoke_p5_battlecore.lua` (replaces `smoke_p3_battlecore.lua`) | the level formula, roles (Support x2.6 / x1.5), the fighter engine (attack, ELEMENT shapes, specials, dash i-frames, swap, buffs, lives, the move clamp), the NPC AI, every mode, the wire format, determinism, the Dungeon catalog and `p5battle_balance` (a short `sim_battle.lua` run) |
| `smoke_p5_home.lua` | the 11 stations, the fold of Phase 4 homes (Home Level and food never drop), pad signs, HomeRoam (the same plan on server and client), berries and the Berry Basket, the Cloud Cash ledger; client half: roaming pets, the coins and the home window strip |
| `smoke_p5_world.lua` | LightingService (painted sky vs the fallback), LightingStack, the art rules (`p5world_style`), the lobby and the Gate Court, GateService, the one obby portal and its level picker |
| `smoke_p5_gui.lua` | the Neon kit, stamina 150 with its dash ticks, the HUD pills and `client_p5gui_cover`: every window at four screen sizes covers at most 60 % (one named block per window owner) |
| `smoke_p5_battleservice.lua` | BattleService's command ladder, the server fighter that follows the character (the leash), fair duels, raids, the ring, the encounter API the Dungeon uses, shutdown |
| `smoke_p5_dungeon.lua` | parties (create, join, ready, kick), runs (rooms, waves, doors, the treasure), loot paid once per room and member, first clears once, every way a run ends, the world, the net; client half: the Dungeon window, run card and end card |
| `smoke_p5_battleclient.lua` | the battle HUD (fighter card, helpers, enemy rows), input (keys bound only in battle, hold to attack, swap hold, Tab), the models, the result card, phone and landscape layouts |
| `smoke_p5_follow.lua` | the follow formation (`FormationFor`), the motion (gaps, lag, never ahead) and the Wild look of dungeon enemies |
| `smoke_p5_looks.lua` | evolved looks at every site (Pets, Index, Team, Fusion, Care rows, garden, reveal, Ring card, followers), the Pet Podium, Support battle power, the Team of 3 |
| `smoke_p5_menu.lua` | the server-held spawn (`MenuPlay`, the 90 s fallback), the loading screen, the main menu, settings, the UI gate |
| `smoke_p5_tutorial.lua` | tutorial texts and targets, chapter 3's Dungeon step, chapter 2 against a Phase 5 home, the obby portal step, NPC lines |
| `smoke_p5_flow.lua` | end-to-end runs: a new player from PLAY to the Dungeon and the ring, a Phase 4 save migrating, a Dungeon party, rejoin, merges |
| `smoke_p2_final.lua` | `README.md` against the game: the station and house tables, the Garden / berries / Food Machine, training, evolution, Vault, prestige, fusion, the fighter / helper rules and keys, the Dungeon, duels, raids, the Champion Ring, NPC, developer-tool and tutorial numbers, the "Phase 5: the Big Sky Update" section and the numbered "Phase 5: owner checklist" (`checkPhase5`) are read from the catalogs and must match the text |

The Phase 4 files (still run, updated for Phase 5 where 12.2 says so):

| File | What it checks |
|---|---|
| `smoke_p4_data.lua` | the save fields of Phase 4 (pet growth: evolutions, ranks, training jobs; the ring record; the kept garden places and prices), the one-time migration of Phase 3 saves, two-server merges, the Phase 3 -> Phase 4 rollout against the frozen `tools/fixtures/DataService_phase3.lua`, `/petlevel` |
| `smoke_p4_economy.lua` | TycoonCatalog: the stations, star prices, coin values, Lucky coins, the lawn, feeding (berries) and training prices, and that `tools/sim_tycoon.py` uses the same numbers |
| `smoke_p4_garden.lua` | the Pet Garden: placing pets, meals and coins, the lawn, naps, scooping (only the owner), the Welcome-back pile, offline coins; client half: the coins, the "Zzz", the scoop pop and the cards of garden pets |
| `smoke_p4_portal.lua` | the home portal: Go home, the refusals (match, battle, portal party), walking in, the arrival swirl; client half: HomePortalFx and the pets diving in |
| `smoke_p4_care.lua` | the Food Machine (berries, XP, the level-100 cap), EVOLVE, the Training Place (cost, time, the training lock, Stop and its refund, auto-return), the old Gym emptied |
| `smoke_p4_careui.lua` | CareController: the Food Machine list, the garden picker, the training window, the EVOLVE confirm and moment, the Pets panel and Home window, phone sizes |
| `smoke_p4_ring.lua` | the Champion Ring: entry rules, chained rounds, rewards (Cash floor, record x3, the first boss clear), every way a run ends |
| `smoke_p4_pets_client.lua` | the pet cards (PetCard) and the followers |
| `smoke_p4_ui.lua` | the tutorial chapters 2 and 4, the NPC tips and the ring window (ArenaController) |
| `smoke_p4_flow.lua` | end-to-end runs of several players through the home: garden, coins, Food Machine, EVOLVE, training, the ring, the portal, prestige, rejoin |

### Mesh mode: `--mesh` (Phase 6)

`python3 tools/smoke.py --quick --mesh` runs the pet scenarios again on Blender-mesh pets (about 1 minute). Real
games get their meshes from Roblox asset ids, and the mock has none, so this mode sets `NC_MESH_FIXTURES=1`:
`smoke_p6_pets.lua` installs fake MeshIds and fixture templates built from the committed
`src/shared/MeshManifests/*.lua` (every pet-class key: `pet_`, `wing_`, `acc_`, `hyb_`, `evo1_`, `evo2_`, `evowing_`,
`star_gold`) into the real `MeshLibrary` on both worlds, so `PetBuilder.Build` takes the mesh path.

* Without `--only` it runs a fixed set of pet scenarios (petbuilder, evolved, p3evo_pets, storm_pet, client_pets,
  the follower / looks / evolved / fusion scenarios ...). With `--only a,b` it runs those plus the two
  `*_mesh_on` install scenarios.
* A mesh pet carries `ML_Mesh = true`. Checks that count voxels (part floors, "two nostril dots", ">= 20 magma
  cracks", "High detail = more parts than Low") are gated on that attribute (recipe 4.9): in mesh mode they check that
  the named part is there, that the model stays under the same part cap, and read `PB_Detail` for the detail level.
  Name checks (`Basalt`, `HydraHead`, `EyeIris` Neon on Glow pets ...) still apply in both modes.
* `tools/run_checks.sh` runs it as the step "Smoke test, mesh mode" after the normal smoke test (skipped when you
  pass `--only`).

## Gate vortex textures (Phase 6 W2b)

`blender/textures/build_vortex.py` (numpy + Pillow, seeded, about a second) writes the white + alpha PNG layers of the
gates' swirling vortex to `blender/textures/vortex/` (disc, core, arms, fine, streaks, rim, crackle 1-4) and the index
`blender/textures/textures.json`; `python3 blender/textures/build_vortex.py --sheet x.png` adds a contact sheet. They
are uploaded later with `python3 tools/upload_assets.py --textures` (dry run by default; `--upload` only with the
player's OK), which writes `src/shared/TextureIds.lua` (numbers only, check.mjs rule `texture-ids`). Until then
`client/PortalVortex.lua` draws the effects-only fallback (Beam spiral arms, inward particle streaks, rim crackles);
with every id present it shows the textured SurfaceGui layers. `tools/smoke_p6_portalfx.lua` covers both modes.

## Phase 6 tools: the Blender models

The Blender kit itself is described in `blender/README.md`; the upload checklist for the owner and the upload session
is `docs/phase6/OWNER_UPLOAD.md`. Blender runs as a Python module: `/tmp/claude-0/bpyenv/bin/python` (setup in
`blender/README.md`). Everything here works offline; nothing talks to Roblox unless `upload_assets.py` gets `--upload`.

**Build the meshes:** `blender/build_all.py` reads `blender/catalog/<class>.json` and writes `blender/out/<key>.fbx`
(+ `.manifest.json`, `.tris.json.gz`; not committed), the committed `src/shared/MeshManifests/<key>.lua` and
`blender/meshes.json` (the uploader's index: fbx, displayName, contentHash, structureHash).

```sh
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets             # one class (repeatable)
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key pet_dog --key acc_crown
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --all                    # every class
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets --preview   # + Cycles sheets of the class's previews
python3 blender/build_all.py --class home --no-export                         # no bpy: manifests + numbers, no FBX
python3 blender/build_all.py --list                                           # every class and key
```
Classes: `calibration` (cal_axes + the test key prop_portal_reference), `pets`, `evolved`, `creatures`, `gates`,
`lobby`, `home`, `arenadungeon` (717 uploadable keys). A key over its budget fails the build (exit 1), and so does
any catalog `set` over its budget. `--no-export` still rewrites the manifests and `meshes.json`: finish with an export
build. Same input = same bytes and the same `contentHash`.

**Budgets:** `python3 tools/mesh_budget.py` prints the triangle / MeshPart sum of a scene from the committed
manifests (default: the busiest phone view, 16 players x 3 pets in the lobby + every gate / lobby key + 4 max-tier
home plots, budget 300k triangles / 400 parts). `--keys` adds every key, `--scene <file.json>` sums another scene
(for example `docs/phase6/review/home/plot_scene.json`), `--check` exits 1 when the scene is over its budget.

**Name contract:** `python3 tools/mesh_names.py` lists every part / palette name the game or a test looks up by name
(those must never be baked into a `Fixed` part); `python3 tools/mesh_names.py --check blender/out/*.manifest.json`
exits 1 when a built key bakes one. The kit uses the same list.

**Look at a mesh** (no Studio; the manifest's boxes coloured like the game colours them):
```sh
python3 tools/render_model.py meshkey:pet_dog:pebble_pup -o key.png      # one key, coloured for a pet's look
python3 tools/render_model.py meshpet:pebble_pup -o pet.png              # body + wings + accessory (add :Low)
python3 tools/render_model.py meshevo:twilight_dragon:2 -o evo.png       # evolved body + its evo wings (1 or 2, add :Low)
```
(These targets are not in `--list`.) `meshpet` picks the body variant from the pet id (`waffle_corgi` -> `pet_dog_corgi`)
and puts the accessory at its manifest's `Meta.attach`; `meshevo` puts the wings at the wing manifest's attach.

**Tests:** `python3 tools/test_upload_assets.py` runs the uploader against a local fake of the Open Cloud Assets API
on 127.0.0.1 (create, PATCH keeping the id, new asset on a structure change, 429 retry, resume after a timeout,
refresh, moderation, creator lock, throttle; 34 checks). `python3 blender/kit/selftest.py` checks the kit (hooks,
recipes, determinism, manifests). `python3 tools/smoke.py --quick --mesh` runs the pet scenarios on mesh pets (see
"Mesh mode" above). The Phase 6 smoke files: `smoke_p6_mesh.lua` (MeshLibrary: empty ids = no-op, fit, loader,
Assemble, Swap, Tag / Dress), `smoke_p6_pets.lua` (the pet mesh path), `smoke_p6_evofx.lua` (PetFx),
`smoke_p6_creatures.lua`, `smoke_p6_gates.lua`, `smoke_p6_lobby.lua` (world meshes),
`smoke_p6_portalfx.lua` (gate animation + vortex); the arena, dungeon and home mesh checks live in
`smoke_p3_arenaworld.lua`, `smoke_p5_dungeon.lua` and `smoke_p2_homeworld.lua` (`p3arena_mesh`, `p5dgn_mesh`,
`p2home_mesh`).

**Upload (dry run):** `python3 tools/upload_assets.py --help` explains everything. Without `--upload` it only
prints the requests it would send (the key hidden) and writes nothing:
```sh
python3 tools/upload_assets.py                    # every key in blender/meshes.json
python3 tools/upload_assets.py --only cal_axes    # some keys (repeatable or comma separated)
python3 tools/upload_assets.py --textures         # the vortex images (blender/textures/textures.json)
```
`--upload` (real; only with the owner's OK, see `docs/phase6/OWNER_UPLOAD.md`) needs `ROBLOX_API_KEY`,
`ROBLOX_CREATOR_ID` and `ROBLOX_CREATOR_TYPE` in the environment and writes `blender/upload_state.json` +
`src/shared/MeshIds.lua` (or `blender/textures/upload_state.json` + `src/shared/TextureIds.lua`). Other flags:
`--refresh` (re-read moderation), `--force` (send unchanged keys), `--poll-timeout N` (seconds, default 300).

**Vortex textures:** `python3 blender/textures/build_vortex.py` (no `--help`: it builds at once) rewrites the 10 PNG
layers and `textures.json`; see "Gate vortex textures" above.
