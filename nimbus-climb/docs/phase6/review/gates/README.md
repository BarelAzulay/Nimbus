# Gate meshes: art review (Phase 6 W2, art-gates)

Keys: `gate_obby`, `gate_ring`, `gate_arena`, `gate_dungeon`, `gate_home`, `gate_altar`. They are built by
`blender/kit/props/gates.py` (prop `gate`) from `blender/catalog/gates.json`:

```
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class gates [--preview]
```

The key comes from the glyph, as set in `WorldStyle.GateMeshKey`:

| Glyph | Key |
|---|---|
| cloud | `gate_obby` |
| crown (the arch) | `gate_ring` |
| swords | `gate_arena` |
| torch | `gate_dungeon` |
| house | `gate_home` |
| bolt | `gate_altar` |

An unknown glyph on a hoop gets `gate_obby`. The arena's green Return gate uses the house glyph, so it wears `gate_home`.

## What the mesh is

The mesh is a finer re-sculpt of the W1 Part gate. Gate voxels are 0.5 studs and crest voxels are 0.25 studs. It is
built on the Part gate's own lattice, so it sits flush around the parts that stay. It contains:

- **Base:** the stone base slab with tile seams.
- **Pillars:** 3 x 3 stone pillars with soft courses, a foot moulding and little cloud puffs at the feet.
- **Caps:** stepped caps in the gate colour, with gold collars that hold the Neon glow blocks.
- **Ring:** a round chunky pixel band in the gate colour, with 12 gold studs on the front and back. Inside it is the white cloud frame: a shallow channel with soft cloud bumps.
- **Keystone:** a keystone wedge with a gold socket for the Neon gem.
- **Crests:**
  - Obby: gold post, bar and cradles under the 5 star gems.
  - Arena: a heater shield tinted in the gate colour with a gold rim and chevron, and two crossed steel swords.
  - Dungeon: a rounded skull with dark eye sockets, a navy nose and a tooth row, over knobbly crossed bones.
  - Home: a cottage with a stepped coral roof, a plank door, window frames, flower boxes, a chimney and smoke.
  - Altar: a puffy storm cloud with a misty underside.
- **Ring gate (crowned arch):** coursed pillars, bevelled gold bands, gold gem sockets, a gold lintel on a stone course, and a stepped crown with gold rims.

The following stay **Roblox Parts**, and the dress keeps them visible:

- the Neon parts: glow ring, swirl, gems, star gems, skull eyes, house windows and the bolt (PortalFxController animates them)
- the pad and the lanterns
- GlowCore, PromptAnchor and the tag
- builder extras such as the dungeon torches and the Ring pedestals

## Budgets (recipe 4.2: gate <= 8k tris, <= 20 MeshParts)

| Key | Tris | MeshParts |
|---|---|---|
| gate_obby | 3680 | 12 |
| gate_ring | 2272 | 7 |
| gate_arena | 4070 | 14 |
| gate_dungeon | 3744 | 10 |
| gate_home | 3794 | 12 |
| gate_altar | 3896 | 11 |

Trim and CrestShield are tinted by `ML_Primary` (the gate colour). Stone, Frame and Gold are their own parts, because
the game looks up those names. Every other constant colour is baked into `Fixed` / `Fixed2`;
`tools/mesh_names.py --check` passes on all six keys.

## Rounds

1. **`r1_obby_part_vs_mesh.png`**: the first pass. In each pair the top render is the Part gate (render_model) and the bottom one is the dressed gate (Part render with the hidden parts removed and the mesh added). Problems seen: mortar stripes too dark, foot puffs reading as debris, the skull's bone knobs running through the whole depth.
2. **Fixes:** softer mortar, 2-stud courses, bigger front-only puffs, bone knobs limited to the bone layer, longer bones, and no dark shading on the frame and gold.
3. **`r4_cycles_mesh_only.png`**: Cycles previews of the six meshes alone (front, 3/4 and side). The empty hoop is expected, because the glow and swirl are Parts.
4. **`r4_part_vs_mesh_all.png`** and **`r4_crests_closeup.png`**: the final comparison of all six gates, Part (left) against mesh (right), plus close-ups of the crests. Before this round two keys were renamed, Base to SlabStone and Roof to RoofCoral, because both names are referenced elsewhere and could not be baked.

The compose tool is in the scratchpad: `w6/art-gates/compose.py <round> [ids]`. It builds the WorldStyle sample dump,
swaps the parts in `GATE_MESH_HIDE` for the manifest's MeshParts, and renders both versions with
`tools/render_model.py`.
