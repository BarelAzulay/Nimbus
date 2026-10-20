# Phase 6 W2 art-arenadungeon review

52 keys (blender/catalog/arenadungeon.json): 20 arena_* + 32 dungeon_*. Baked from the game's own Part builds
(blender/kit/props/arena.py "ad_baked" + arena_style.py bake) or designed (props/dungeon.py: rocks, crack, stalagmite).
Rebuild: `/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class arenadungeon`.

| sheet | what |
|---|---|
| arena_overview.png | the whole island from the forum side, every arena key at its Tag origin (gates = Part build, art-gates) |
| arena_part_vs_mesh.png | main gate area: W1 Part fallback vs the meshes (same layout, finer voxels, bricks / cobbles / tiles) |
| arena_pieces.png | one 3/4 view per arena key (seats / banners / ring accents are tint parts) |
| dungeon_rooms.png | Cave_1 and Throne_1 room shells assembled from reusable wall / floor / pillar / torch / rock pieces |
| dungeon_pieces.png | one 3/4 view per dungeon piece |

Review rounds: r1 (runner hidden under tiles -> thin overlays painted last; stalagmite was 3 stacked boxes -> designed
terraced cone; chest plain -> gold straps / corners; crate framed), r2 (chest gold toned down, rock scale capped by the
block's thinnest side, tree / lantern / hedge lighter), r3 (final renders above). Arena total ~280k tris over 75
placements (test cap 300k); heaviest dungeon room < 90k tris.

Known nits: wall-bulge rocks in the Cave poke a little through the outside of the wall (never visible from inside);
a dark sliver where two wall runs overlap at a corner (under the ceiling).
