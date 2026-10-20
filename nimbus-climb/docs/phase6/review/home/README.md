# Home plot meshes: art review (Phase 6 W2, art-home)

Keys come from `blender/catalog/home.json` (88 keys). They are built by `blender/kit/props/home.py` and
`blender/kit/props/home_style.py`:

```
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class home     # about 2 minutes, all 88 keys
python3 tools/mesh_budget.py --scene docs/phase6/review/home/plot_scene.json --check
python3 tools/smoke.py --quick --only p2home_mesh
```

## Keys

| Key | What it is | Levels |
|---|---|---|
| `home_farm_<L>` | the Berry Farm | 1-40 |
| `home_garden_<L>` | the Pet Garden without its bed pieces | 1-8, any open count |
| `home_foodmachine_<L>` | the Food Machine | 1-5 |
| `home_training_<L>` | the Training Place | 1-5 |
| `home_vault_<L>` | the Vault | 1-5 |
| `home_house_<L>` | the house tiers: Cottage, Villa, Manor, Sky Castle | 1-4 |
| `home_fusion_<L>` | the Fusion Machine | 1-3 |
| `home_arena_1` | the Arena Gate station | 1 |
| `home_fence_<L>` | the Yard Fence | 1-3 |
| `home_fountain_<L>` | the Fountain | 1-3 |
| `home_podium_<L>` | the Pet Podium | 1-3 |
| `home_bed_<frame/cushion/headboard/roof/soil/stem/sprout/post>` | one Garden bed piece per Part. The cushion is tinted by `ML_Primary`, which is the part's own colour. | - |

## What the mesh is

The mesh is the game's own Part build, rebaked. The kit calls `HomeBuilder.BuildStationModel(id, level)` in the
mock world and turns every visible box into voxels: 0.25 stud for the stations and fence, 0.125 for the Arena Gate,
the cushion, the stem and the sprout. Footprints, walk heights and colliders therefore match the Part build.

The bake adds the cute detail that Parts cannot afford:

- shapes:
  - round, chunky voxel bushes and tree crowns
  - berries with a highlight
  - cloud puffs
  - rounded basins, bowls, barrels and glass pods
  - chamfered vines
- surface detail:
  - brick courses with staggered joints and quoins on walls
  - vertical boards on the barn
  - plank seams on wood
  - shingle rows on roofs
  - tile seams on stone floors
  - leaf clusters
  - grass tufts and speckles on lawns
  - soil crumbs
  - soft seams on cushions
  - water ripples
- shading, like Voxel.Shade: a light top skin, dark undersides, and the P4 palette with each part's own jitter

Colours are baked into one SmoothPlastic part, `Fixed` (with `Fixed2` and up only if a part would pass 10k
triangles), plus one `Glass` part for each glass transparency. When a key goes over its budget, the detail steps down
in this order: tufts, joints, speckles, clusters.

The following stay **Roblox Parts**. HomeBuilder writes them into `ML_Keep` through `HomeBuilder._Mesh.keepOf`:

- Neon and ForceField parts: lanterns, crystals, the portal, inlays, the Starberry (HomeFx and the lights pulse them)
- the Fusion `Swirl`, which HomeFx spins
- SurfaceGui sign boards: text stays Parts
- the Garden's bed pieces, which carry their own keys
- every prompt, `PromptPoint*` / `Spot<i>` attachment, billboard and zone
- pads, ghosts, paths and the house lot, which are untouched

## Tagging (`HomeBuilder._Mesh`, Tag calls only)

`placeStation` and `BuildStationModel` call `Mesh.station`. It tags the station model as
`home_<stem>_<level>`, with `Offset` set to the station origin and the keep list. It then tags each Garden bed
piece Part with its own key. A key is tagged only when two things are true:

- `MeshLibrary.Status(key) ~= "missing"`: the shipped empty MeshIds change nothing.
- The manifest's `LayoutSig` still matches the live Part build. LayoutSig is the count plus position and size sums of
  the visible, not-kept parts, the same formula the lobby uses.

If an art change ever breaks the match, the station silently keeps its Parts, and `p2home_mesh` fails with the
message "rebuild".

## Budgets

| Budget | Triangles | MeshParts | Keys |
|---|---|---|---|
| `station` | 4k | 8 | food machine, training, vault, fusion, arena, fountain, podium, cottage / villa |
| `stationBig` | 8k | 8 | farm, garden, fence |
| `house` | 10k | 8 | Manor, Sky Castle |
| `element` | 600 | 2 | bed pieces |

A max-tier plot is about 41k triangles and 65 MeshParts (`plot_scene.json`; the test caps it at 50k). The P4 Part
plot was about 950 parts.

## Sheets

These come from the scratch `preview.py` (render_model mesh path), after 3+ rounds:

- `houses_part_vs_mesh.png`
- `stations_part_vs_mesh.png`
- `farm_garden_part_vs_mesh.png`: farm 10 / 40, and garden 8 with 3 and with 12 open beds
- `castle_farm_closeup.png`

Rounds:

1. The first bake.
2. Coarse-blob bushes and crowns, which saved 4k triangles on the farm. Bigger bricks on big walls, no shingle tabs on
   spires, sparser tufts.
3. Crossed swords readable (thin parts at an angle get a connected line), squarer fountain basin, barn boards,
   tinted cushions.

## Plot LOD (perf-plots, Phase 6 W3)

The busiest lobby phone view went over the 300k scene budget once the home plots counted. The client now picks a
level per plot, from the camera distance to the plot centre, every 0.5 s (HomeFx `updateNear`, never per frame), with
20 studs of hysteresis:

| Tier | Distance | What shows | Max plot + its base |
|---|---|---|---|
| High | < 120 (leave at 140) | every High key: your own yard, a visit | 48.8k tris, 68 parts |
| Low | 120-200 | every key on `<key>_low` (the High key while no _low is uploaded): a neighbour seen from your yard | 17.1k with the _low keys |
| Far | >= 200 (leave at 180) | only the landmarks (house + the lobby's plot base) on _low; stations, decor and their kept glow hidden. Every plot seen from the plaza is Far. | 5.3k, 5 parts |

`MeshLibrary.SetLod(target, "High" | "Low" | "Hide")` does the work and touches only dressed targets, so empty
MeshIds (today's game) change nothing. `MeshLibrary.LowKey(key)` takes `<key>_low` only when it is usable on the device
and was baked from the same layout (LayoutSig).

Requested keys (not built yet, catalog owner): `home_<station>_<L>_low` for every station key (vs 0.5, detail 1; the
house at detail 0) and `prop_plot_low` (cloud cushion V 4). Their cost, measured with the kit in a scratch run, is in
`low_keys_estimate.json`; `python3 tools/mesh_budget.py` prints the busiest views before the rule, with the rule on
today's keys and with the requested keys.

Sheets (scratch `w6/perf-plots/plotrender.py`: the Sky Castle plot composed from its station meshes at the
TycoonCatalog slots; low keys baked in memory):

- `plot_lod_tiers.png`: the same plot at High / Low / Far.
- `plot_lod_onscreen.png`: High next to the tier it gets, at the size it has on a landscape phone (150 / 300 / 420
  studs).

Rounds: 1. Low hid the decor (the Garden looked bare at 150 studs). 2. Low keeps the decor on low keys; it costs
about 1.3k tris in the worst view, because the plaza only ever sees Far plots. 3. Checked at the on-screen size: Low is
hard to tell from High. Far keeps the castle and the yard frame, and loses the farm and station colour. That is the
trade-off for 8 plots across the plaza.
