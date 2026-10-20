# Mesh fixtures (Phase 6, MeshLibrary tests)

Test inputs for `tools/smoke_p6_mesh.lua`, not game data: nothing here is mounted into the place.

* `pet_dog.lua`, `wing_feather_L.lua`, `wing_feather_R.lua`, `acc_crown.lua`: frozen byte copies of the kit's
  generated manifests (`src/shared/MeshManifests/<key>.lua`, KitVersion 2, wave 1). The tests build fake LoadAsset
  results from them (MeshParts with the manifest names, sizes and centres, turned by a yaw, scaled 100x / 0.01x,
  mirrored, a part missing ...) and run them through `MeshLibrary._Fit` and the background loader.
* `prop_arch.lua`: a small hand-made, asymmetric world prop with lower-case field names (MeshLibrary accepts both
  cases) used for `Tag` / `Dress` and the mirror / misplaced-part refusals.

The live manifests are tested too: `p6mesh_fit` fits every module in `src/shared/MeshManifests` (yaw 180), so a kit
format change shows up there. Refresh the frozen copies only on purpose (a format change the runtime follows).
