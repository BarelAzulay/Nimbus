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

`sim_tycoon.py` replays the Phase 4 tycoon homes (pets make the money: rainbow coins from the Pet Garden, the food
plants, the Coin Magnet, the Food Machine, EVOLVE at 20 / 50, pets growing to level 100, prestige with x1.5 prices
per star, the Vault's offline coins) for an active player and 120 typical ones (3 prestige runs each), prints when
each milestone is reached (first paid pad, Villa, first prestige, first EVOLVE, later runs, prestige Gems per hour)
and checks the pacing targets of ARCHITECTURE_V3.md "Phase 4 build contract" 3.12 / 8.3: it must print
`ALL TARGETS MET`. Its constants block mirrors `src/shared/TycoonCatalog.lua` (and the pet data of `PetCatalog` /
`Config`): change both together (the smoke test `p2_economy`, `tools/smoke_p4_economy.lua`, fails while they
disagree).

```sh
python3 tools/sim_tycoon.py                 # timeline of one player + Monte Carlo + targets (~20 s)
python3 tools/sim_tycoon.py --quiet         # summary only
python3 tools/sim_tycoon.py --ring 0.08     # a kid who climbs the Champion Ring regularly (+8% Cash)
python3 tools/sim_tycoon.py --feed 0.5      # a heavy feeder (half the coins go to the Food Machine)
python3 tools/sim_tycoon.py --mode combat   # the timeline player only gets Combat pets
python3 tools/sim_tycoon.py --check         # catalog == sim: effect tables, pads with star prices, income, feeding (lupa)
python3 tools/sim_tycoon.py --migrate       # 300 Phase 3 homes on their first Phase 4 login (Home Level, dead ends, pad time)
python3 tools/sim_tycoon.py --plan yard.png # the yard from above: stations, pads, garden walks, coin piles (lupa + Pillow)
```

* `--check` loads the real catalog (and PetCatalog) with lupa and compares every constant, `AvailablePads` (incl.
  `PriceAt` with stars and `LegacyPrices`), `FoodOf`, `GardenSlots`, `IncomePerSecond`, `PileSeconds`, `ScoopRadius`,
  `OfflineEarnings` and `StationsAfterPrestige` on 400 random homes, `FeedXp` / `FeedPrice` / `TrainCost` /
  `TrainSeconds` at every level and rank, and runs `Validate()`.
* `--migrate` imports the frozen Phase 3 sim (`tools/fixtures/sim_tycoon_phase3.py`) by path, stops 300 old homes at
  random moments, applies the one-time migration (LegacySlots, LegacyPrices) and gates on: Home Level unchanged in
  every home, no dead end, and a median time-to-the-next-pad ratio <= 1.0 in every house tier / star bucket.
* Exit status 1 when a target is missed (or `--check` / `--migrate` finds a problem).

## Battle balance simulation (Phase 3 + Phase 4)

`sim_battle.lua` runs the **real** battle engine (`src/shared/BattleSim.lua` on the numbers of
`src/shared/BattleCatalog.lua`, with PetCatalog / PetKeys / TycoonCatalog) inside the Roblox mock under lupa, like
`smoke.py`, and prints a balance report with `TARGET ok / MISS` lines: the Trial curve 1-30 against typical teams along
the tycoon progression (early players clear ~1-8, mid game ~10-20, prestiged players reach 30), equal-power fights
being fair, mirror duels at ~50%, one element-counter pet at ~60-65%, boss raids with 1 / 3 / 8 scripted players who
RETREAT out of telegraphs (won in 100-240 s, non-dodgers see several telegraphs), every special useful but none an
auto-win, no one-shots, no unkillable sustain teams, no stalls, and the step cost of a full raid. It boots the mock by
itself (run it from the repo root), so no Python wrapper is needed beyond lupa:

```sh
python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
SIM_BATTLE="quick only=trials,raids" python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
```

* `SIM_BATTLE` options: `quick` (32 seeds per matchup, ~20 s) or `full` (100 seeds, the default), `seeds=N`,
  `only=roster,duels,elements,trials,raids,dodge,specials,extremes,perf,training,ring,level100,progression`,
  `verbose` (section timings).
* Phase 4 sections (`ARCHITECTURE_V3.md` "Phase 4 build contract" 8.3): `training` (TeamPower with all four skills at
  rank 5 x1.25-1.4 and rank 10 x1.6-1.85, Evolved I / II x1.25 / x1.5, trained mirror duels 35-65% with no draws or
  timeouts, a trained + evolved team still needs 100-240 s for a raid with dodging players), `ring` (the Champion Ring:
  rounds 1-3 won >= 95% by every single level-1 rollable Common / Uncommon, the single-pet average >= 85% at rounds 4-5
  and >= 50% at round 8, the median record per stage S1 13-19 / S3 20-26 / S5 25-31 / S7 33-39 / S9 41-47 / S10 48-54,
  fights 4-40 s, the champion's power never dropping to round 120, Boost from rounds 40-50, the round table with its
  rewards), `level100` (the player's level-100 rule: the S10 pets at level 100, Evolved II, every skill at rank 10 ->
  raids 100-240 s, no duel hit above `Damage.MaxHit` (no one-shots), fair mirrors, the duel practice gap
  `DUEL_POWER_GAP` read from BattleService catches the maxed L100 team vs an L50 team) and `progression` (the XP behind
  each stage and its Food Machine price, `TycoonCatalog.FeedPrice`). `SIM.Stages` are the Phase 3 stages, unchanged.
* Change a number in `BattleCatalog` -> re-run the sim. The smoke scenario `p3battle_balance`
  (`tools/smoke_p3_battlecore.lua`) loads this file as a library (`SIM_BATTLE_LIBRARY = true`) and runs a short subset.
* The scripted player (`SIM.Player`) presses SPECIAL when a meter is full, focuses a wounded enemy and retreats out of
  telegraph shapes after a human-ish 0.4-0.9 s reaction; `Auto = true` teams cast on their own like NPC teams.

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
  boards, the bridge and the Trial Portal; `lobby+arena` with `--box` shows the plaza link) and `pocket[:<index>]`
  (one private trial pocket from `ArenaBuilder.BuildPocket`).
* Phase 3 bosses (`shared/BossBuilder.lua`): `boss:<bossId>[:<pose>[:High|Low]]` (pose Idle | Windup | Attack |
  Basic | Enrage | Hurt | Down at its strongest moment; `Windup/chain` picks the attack id, a trailing `!` shows it
  enraged, e.g. `boss:storm_titan:Attack/slam`, `boss:lava_golem:Enrage!`) and `bosses[:<pose>[:Low]]` (the roster).
* Phase 3 battles (`client/Controllers/BattleController.lua`, client world): `battle[:<trial|duel|raid>[:<seconds>[:specials]]]`
  steps a real BattleSim at 10 Hz and feeds it to the real BattleController the way BattleService sends it, then dumps
  what the client drew (`workspace.ClientBattle`: unit models, boss, telegraphs, effects). `battle:raid:9` catches the
  boss's first telegraph filling; `:specials` fills the local team's meters and casts every special just before the
  dump, e.g. `python3 tools/render_model.py battle:raid:9:specials --views threequarter,top --size 1400 -o raid.png`.
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
* `battle[:<trial|duel|raid|spectate>[:<fight|ready|retreat|result|lost>]]` (Phase 3, BattleController): the battle
  HUD fed by a real BattleSim stepped at 10 Hz through BattleState: top card, team rows with SPECIAL buttons (`ready`
  lights two of them), ATTACK / RETREAT (`retreat` shows the regroup countdown), the result card (`result` / `lost`),
  or the slim WATCHING card of a spectator; e.g. `python3 tools/render_gui.py battle:raid:ready --grid -o raid.png`.
* `arena[:<view>[:<arg>]]` (Phase 3 UI: MenuController's Team window, ArenaController): a profile with a battle team,
  trophies and trials 1-6 cleared, then `team` (default), `team4` (Prestige 1: four slots), `newteam` (empty presets),
  `trials[:<level>]` (the Trial window on that level), `duels` / `raid` / `leaders` (the Arena panel's tabs, with two
  more players to challenge, a running raid, Double Rewards) or `side` (no window: the duel invite, the queue, the raid
  join card and the event countdown at the right edge); e.g. `python3 tools/render_gui.py arena:trials:12 --grid`.
* `arenaboards[:<countdown|raid|idle>]` (Phase 3, ArenaBuilder) draws the Battle Arena's world GUIs instead of the HUD,
  like `portal`: the real LobbyBuilder + ArenaBuilder build the arena (as the server), a sample ArenaState goes through
  `ApplyArenaState` (`countdown`: the next Boss Raid in 1:35 + Double Rewards, `raid`: a live raid with its HP bar,
  `idle`: the next raid 20 minutes away), then every SurfaceGui (event board, trophy leaderboard, gate and arch signs,
  both faces) is drawn at its on-screen size from 30 studs and every BillboardGui (duel pad tags, the Trial Portal) at
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
