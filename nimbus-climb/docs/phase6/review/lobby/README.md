# Lobby meshes (Phase 6 W2, art-lobby)

62 keys in `blender/catalog/lobby.json`, built with `blender/build_all.py --class lobby [--preview]`.

| Kind | Keys | How they are made |
|---|---|---|
| Designed props | `prop_tree_round / _blossom / _pine`, `prop_lamp`, `prop_bench`, `prop_flowerbed`, `prop_fountain` + `_water`, `prop_welcome_arch`, `prop_obelisk`, `prop_banner`, `prop_board_s / _l`, `prop_roulette`, `prop_item_stall`, `prop_token_statue`, `prop_shop_arch`, `prop_pond` + `_water` | `blender/kit/props/lobby.py`: the Lua builds' sizes and pivots, re-sculpted at 2.5-6 voxels per stud (stone courses, plank seams, flutes, leaf clusters, apples, pixel flowers) |
| Home plot | `prop_plot` | the plot's cloud from the game's own spec (2-stud voxels; Lua 6) + its lawn / street / hedge boxes + sculpted fence posts, gate and mailbox. The podium stays a Part. |
| Clouds | `cloud_plaza`, `cloud_shop`, `cloud_garden_blossom / _pond`, `cloud_puff_s`, `cloud_sky_big / _small` | `kit/props/lobby_world.py`: the VX.Cloud spec the game records, re-voxeled finer (`LobbyBuilder._CloudGrid`) |
| Floors | `floor_plaza_*` (8), `floor_shop_1..5`, `floor_garden_*_1..4`, `floor_junction_<plain/spoke/garden/arena/altar>`, `floor_spoke`, `floor_garden_bridge`, `floor_altar_bridge` | meshed from the Part build's own boxes (exact walk heights) |
| Storm Altar | `cloud_altar`, `prop_altar_ring / _portal / _crystals / _sign`, `cloud_storm_puff` | the island's rim / belly re-voxeled finer (`StormAltar._Blueprint`), the rest from its boxes |

Layout-baked keys (clouds, floors, plot, altar) carry the `LayoutSig` attachment; LobbyBuilder / StormAltar tag
them only while the live build still matches it (a Config change keeps the Part build).

Sheets: `1_plaza_props.png`, `2_court_and_fountain.png`, `3_shop.png`, `4_plot_clouds_altar.png` (Cycles previews,
3/4 + front), `5_in_place_parts_vs_meshes.png` (render_model.py `lobby` vs `meshlobby`).
Budget: `python3 tools/mesh_budget.py --scene docs/phase6/review/lobby/scene_plaza_phone.json` (the spawn view:
the lobby keys come to about 112k triangles, plus the gates).
