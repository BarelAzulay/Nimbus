# Phase 6 research: Open Cloud upload, runtime loading, colour, limits (from the design scout; sources inside)

## uploadFlow

Short version: upload each FBX as a Model asset, then PATCH the same asset id to make new versions. The uploader is written and tested against a local fake API only; nothing was sent to Roblox.

Tags: DOC = official Roblox docs (creator-docs repo, commit 7400643, 2026-10-20; same text as create.roblox.com/docs). PLUGIN = Roblox's own Blender add-on (github.com/Roblox/roblox-blender-plugin), which uploads through this same API. FORUM = DevForum. INFERRED = my conclusion, to check on the first real upload.

1. Create (DOC: cloud/guides/usage-assets, reference/cloud/assets/v1)
- POST https://apis.roblox.com/assets/v1/assets with header x-api-key.
- Body is multipart/form-data with two parts:
  - request (JSON): {assetType:Model, displayName, description (max 1000 chars), creationContext:{creator:{userId or groupId}}}
  - fileContent: the file, Content-Type model/fbx.
- Key permission: "assets" API, Read + Write (asset:read and asset:write).
- A key unused for 60 days auto-expires (DOC api-keys).
- If the filter catches the whole display name, the upload fails with HTTP 400, so use plain names (FORUM t/2298007).

2. Asset type
- Use Model. FBX, glTF and GLB become "a Model container containing one or more MeshPart objects", uploaded as a package (DOC).
- The Mesh type only accepts Roblox-format mesh data from Asset Delivery and cannot be updated, so it is not usable for FBX (DOC).

3. Owner (user or group)
- The asset belongs to the creator in creationContext.
- InsertService:LoadAsset only loads assets owned by or shared with the game creator (DOC).
- So upload with the user id of the game owner. If the game ever moves to a group, upload with groupId instead.
- A game owner different from the asset owner gives "User is not authorized to access Asset" (FORUM t/4765232).

4. Getting the result
- Every call returns {path: "operations/ID"}.
- Poll GET /assets/v1/operations/ID until done is true.
- The result holds response.assetId, revisionId and moderationResult.moderationState (Reviewing, Rejected or Approved), or an error (DOC).
- The add-on polls 5 times, 5 seconds apart (PLUGIN). The prototype backs off from 2 to 10 seconds with a 300 second timeout.

5. Moderation
- The docs give no review time.
- GET /assets/v1/assets/ID refreshes the state.
- Rejected ids are left out of the generated Luau table. An asset still under review simply fails to load, and the game falls back to the Part build.

6. Rate limits (DOC openapi x-roblox-rate-limits, per API-key owner)
- Create and update: 120 per minute.
- Get operation: 300 per minute.
- Get asset: 120 per minute.
- Versions, rollback, archive: 100 per minute.
- Files: up to 20 MB per call.
- Undocumented limits also exist, so the uploader handles HTTP 429 with retry-after or exponential backoff (DOC rate-limits).
- The add-on limits itself to 25 uploads per minute (PLUGIN).

7. Updating with the same id
- PATCH https://apis.roblox.com/assets/v1/assets/ASSETID with request {assetType:Model, assetId, creationContext} and the new fileContent creates a new version (DOC).
- Content updates work only for FBX files and only for Models, so export FBX, not glTF (DOC).
- Images, Decals, Audio and Meshes cannot be updated (DOC).
- Versions can be listed and rolled back with the versions:rollback endpoint.
- The add-on stores the asset id on the Blender object and re-uploads as a new version (PLUGIN).
- At runtime LoadAsset and LoadAssetAsync load the latest version, so a PATCH reaches new servers without a code change. Running servers keep their copy. LoadAssetVersion pins a version.

8. What the uploaded Model contains
- Several mesh objects in one FBX become one Model with several MeshParts (DOC).
- MeshPart names should be the Blender object names (INFERRED from the importer's defaults).
- Objects ending in _Att become Attachments (DOC parts/meshes). Use Pivot_Att, Head_Att and FxPoint_Att as sockets.
- Importer defaults, assumed for Open Cloud: Anchored off, Merge Meshes off, Ignore Vertex Colors off, pivot at scene origin, not double-sided (DOC importer).
- Scale: the add-on exports with global_scale 0.01 (comment: "Blender Meters are 100:1 to Studio Studs"), axis -Z forward and Y up, path_mode COPY and embed_textures (PLUGIN). That gives 1 Blender metre = 1 stud.
- Mesh ids probably change with every version, so always reference the Model id, never the mesh ids (INFERRED).
- Upload each reused prop once and clone it: identical MeshContent with the same material is drawn in one instanced draw call. A whole scene imported at once loses this (DOC performance-optimization/improve).
- The docs do not say whether textures embedded in an Open Cloud Model upload become Image assets. Recommendation: no textures, vertex colours only.

9. Prototype: research/upload_assets.py (standard library only)
- Reads ROBLOX_API_KEY, ROBLOX_CREATOR_ID and ROBLOX_CREATOR_TYPE (user by default) from the environment. The key is never printed.
- Reads the manifest blender/meshes.json. Each entry: fbx path, displayName, description, maxTrianglesPerMesh (refused above 20000) and expectedSize.
- Writes the id table blender/mesh_ids.json atomically after every asset.
- --emit-lua src/shared/MeshIds.lua writes the Luau table with numbers only. tools/check.mjs bans rbxassetid:// literals outside Config.Art.
- Idempotent: a sha256 fingerprint means unchanged files are skipped and changed files are sent as a PATCH (new version, same id).
- An interrupted poll is saved as pendingOperation and resumed on the next run, so a crash never creates a duplicate asset.
- Throttles to 100 writes and 250 reads per minute and retries 429 and 5xx errors.
- Refuses to run for a creator other than the one recorded in the id table.
- Other options: --dry-run (prints the exact requests and a curl equivalent, with the key masked), --only, --force, --refresh, --root.

10. Evidence
- research/test_upload_assets.py runs the uploader against a local fake of the documented API on 127.0.0.1: 14 of 14 checks pass (create, 429 retry, polling, Luau table, skip when unchanged, PATCH keeping the id, resume, refresh, creator mismatch).
- The exact dry-run requests are in research/sample/dry_run_new.txt (POST) and research/sample/dry_run_update.txt (PATCH).

Verify on the first real upload:
- Upload sample/SampleTwoMesh.fbx. Check the MeshPart names, that Head_Att became an Attachment, that the sphere is 2 studs across, that vertex colours show, that parts are unanchored, and whether a PackageLink is present.
- PATCH it once: the id should stay the same and the mesh ids should change.
- Upload one FBX with an embedded PNG to see whether textures come through.

## loadingFlow

Short version: load each Model on the server, keep one clean template in ReplicatedStorage, and clone it everywhere. Fall back to today's Part builders whenever a template is not there.

1. Ways to load (DOC: InsertService, AssetService, MeshPart, TriangleMeshPart)
- InsertService:LoadAsset(modelId), server only.
  - Ownership check: the asset must be owned by the game creator, shared with them, or owned by Roblox.
  - It yields and can fail if Roblox's asset servers have problems, so wrap it in pcall.
  - It returns a Model that wraps the asset.
- AssetService:LoadAssetAsync(modelId) is the "modern replacement".
  - It loads the latest version and returns a sandboxed Model, which is fine for meshes.
  - The ownership rule is the same unless third-party loading is turned on.
- Neither works on clients. LoadAsset has been blocked on clients since 2016 (FORUM t/30327 staff; t/2564555 confirms). Load on the server, put the result in ReplicatedStorage, and let clients clone it.
- MeshPart.MeshId and MeshContent cannot be set from scripts (write security NotAccessibleSecurity, DOC).
- AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {CollisionFidelity, RenderFidelity}) is allowed (DOC).
  - It costs about 22 ms plus 0.27 ms per 1,000 triangles, blocking the main thread (FORUM t/4752538).
  - InsertService:CreateMeshPartAsync is plugin-only (FORUM t/2848207).
  - MeshPart:ApplyMesh copies a mesh in about 0.01 ms.
  - Use CreateMeshPartAsync only to re-make one template that must collide with a chosen fidelity, never per spawn.
- A later option, not the first step: download the processed .rbxm through Asset Delivery (scope legacy-asset:manage) and let Rojo sync it. Rojo's file library may break Roblox file details (FORUM t/4022082).

2. MeshLibrary sketch: research/MeshLibrary.lua
- Plain Lua 5.1 syntax. tools/check.mjs reports 0 errors and 0 warnings.
- research/test_meshlibrary.py runs it inside the repo's own tools/robloxmock.lua (used read-only): 23 of 23 checks pass.

Server, MeshLibrary.Start():
- Reads shared/MeshIds. An empty table means the game behaves exactly as today.
- Loads in the background, up to 4 at a time: LoadAssetAsync first, then LoadAsset, inside pcall.
- Retries after 2, 5 and 12 seconds. "Not authorized", "does not exist" and "invalid" errors are not retried.
- Normalises each result:
  - unwraps the wrapper Model;
  - deletes PackageLink and any scripts;
  - sets Anchored on every part, because the importer leaves parts unanchored;
  - turns CanCollide, CanTouch and CanQuery off on visual parts;
  - sets MeshPart Color to white or a tint, because vertex colours multiply with Color;
  - sets Material to SmoothPlastic and PrimaryPart to Root, then Body, then the largest part;
  - takes the pivot from Pivot_Att and fixes a 100x scale mistake with Model:ScaleTo.
- Parents the template to ReplicatedStorage.MeshLibrary.KEY with attribute ML_Status = ready and the load time in ML_LoadMs.
- A failed load leaves ML_Status = failed and the error in ML_Error.

Client:
- Templates replicate like any other instance.
- Calls ContentProvider:PreloadAsync on each template. A key counts as usable on that device only after its mesh data has downloaded.
- A failed download (Enum.AssetFetchStatus.Failure) keeps the Part build on that device only. This covers the July 2026 report of fresh meshes not drawing for some players (FORUM t/4730088).

Public API (synchronous, like PetBuilder.Build and BossBuilder.Build today):
- Clone(key, {Scale, Tint, RenderFidelity}) returns a Model or nil.
- Build(key, opts, fallbackFn, ...) returns the model and either "mesh" or "parts".
- IsReady, Status, OnReady and Tint.
- Tag(partModel, key, keepNames) on the server, with Dress on the client, for world pieces built at boot. The Part build stays the real model: it replicates, collides and keeps the part names the tests use. Each client that has the mesh hides those Parts locally and shows the mesh on top. Parts named in keepNames, such as signs, stay visible.

3. Latency and caching
- Load time is not documented, so the sketch logs it.
- Each server loads each asset once. There is no cache shared between servers; Roblox's own asset cache sits underneath.
- A PATCHed version reaches new servers; use Migrate to Latest Update to move live servers.

4. Animation constraint
- PetBuilder's rig is driven by attributes (PB_Rig, PB_G, PB_Base, PB_Pulse, PB_Hue) and moves parts by CFrame.
- Blender exports must keep animated pieces (wings, tail, ears, eye parts) as separate MeshParts with the same names.
- Those attributes have to be written onto the template by a MeshSpecs table. FBX custom properties are not documented to become attributes.

5. Tests stay green
- Without ids, or in the mock where LoadAssetAsync does not exist, Clone returns nil and every builder runs unchanged.

## colourStrategy

Recommendation: vertex colours plus MeshPart.Color, no textures.

How colouring works:
- MeshPart.Color can be set at runtime (write security None).
- Imported vertex colours are multiplied by Color. The default Medium Stone Grey (163,162,165) darkens them, so set Color to white (255,255,255) to see them exactly (FORUM t/3050119, a Roblox staff article). The docs agree: "Non-white vertex colors can tint the mesh appearance" (DOC marketplace/validation-system).
- FBX and glTF vertex colours import by default ("Ignore Vertex Colors" is off; DOC studio/importer).
- Blender 5.2's FBX exporter writes them by default (colors_type SRGB). Checked: research/sample/SampleTwoMesh.fbx contains its colour layer and keeps its object names, built by research/tools/make_sample_fbx.py.
- SpecialMesh does not show vertex colours (FORUM t/4752538), so use MeshParts.

How to model for it:
- Split each model into MeshParts by colour role, using the names the Part builders already recolour: Body, Belly, EyeIris, EyePupil, EyeShine, Wing_L, and so on.
- Give parts that must change at runtime white vertex colours, then set part.Color: hybrids, Golden and Rainbow finishes, the Wild look, element colours, evolution glow.
- Paint fixed detail (blush, paw pads, soft shading) as vertex colours.
- PetBuilder's applyWild already recolours by part name and sets Neon on eyes, so it keeps working on MeshParts.
- MeshLibrary.Tint and Clone(opts.Tint) apply colours by part name.

Textures and SurfaceAppearance:
- MeshPart.TextureID can be changed at runtime, but it cannot override PBR maps (DOC parts/meshes).
- SurfaceAppearance texture maps (ColorMap, NormalMap, RoughnessMap, MetalnessMap and their Content versions) are PluginSecurity, and "most SurfaceAppearance properties cannot be modified by scripts" (DOC).
- Writable at runtime: SurfaceAppearance.Color (a tint that multiplies the colour map at no extra cost), AlphaMode (Overlay shows MeshPart.Color through the alpha; TintMask tints only where alpha is set), EmissiveTint, EmissiveStrength and ResampleMode (DOC art/modeling/surface-appearance).
- CreateSurfaceAppearanceAsync only takes EditableImage content.

Why no textures:
- Images cannot be updated in place through the API.
- Images are moderated separately.
- The docs do not say whether embedded textures survive an Open Cloud Model upload.
- Built-in materials use "far less memory than custom textures" on phones (DOC performance-optimization/design).

The existing blender/pebble_pup.py comment that "Roblox needs a texture for colours" is out of date: vertex colours work.

## limits

Hard limits (DOC):
- Triangles: 20,000 per mesh (art/modeling/specifications). Geometry must be watertight, use quads where possible (no n-gons), and have no zero-thickness parts.
- Upload size: 20 MB per call (usage-assets).
- Textures, if ever used: up to 4096x4096. Guideline: 256 px for 5x5 studs, 512 for 10x10, 1024 for 20x20 (texture-specifications).
- MeshParts per Model: no hard limit is documented. The docs warn that "too many parts in a Model could cause rebuilds more often".
- Draw calls: each distinct mesh with its own material is a separate draw call. Copies with identical MeshContent and identical material, texture or SurfaceAppearance are instanced into one (performance-optimization/improve).

Collision (DOC):
- CollisionFidelity options: Box, Hull, Default, PreciseConvexDecomposition, Tunable.
- It "cannot be read or manipulated by scripts during runtime" (TriangleMeshPart).
- Default and Precise use far more memory, and collision geometry stays in memory even with CanCollide off, so lower fidelity and turn CanCollide, CanTouch and CanQuery off where possible.
- Open Cloud uploads have no import options, so they keep the import default.
- Plan: visual meshes do not collide, and the existing simple Parts stay as invisible colliders through Tag and Dress.
- If one mesh must collide precisely: build one template with AssetService:CreateMeshPartAsync(part.MeshContent, {CollisionFidelity = Box, Hull or Precise}). This costs about 22 ms, once per server.

Rendering and LOD (DOC):
- RenderFidelity Automatic switches detail by distance: Highest under 250 studs, Medium from 250 to 500, Lowest beyond 500. Performance is also available.
- RenderFidelity does not replicate, so set it on the client, for example Performance on low graphics quality through GraphicsQuality.lua. Clone supports this with the RenderFidelity option.
- Model.LevelOfDetail = SLIM, with instance streaming, gives lighter models at a distance.
- Double-sided rendering costs more. Shadows degrade and turn off below quality level 4.

Phones (DOC):
- The docs' example for a low-end baseline device: stay below 1,000 draw calls and 1,000,000 triangles (performance-optimization/design).

Suggested budgets (my recommendation, derived from the numbers above):
- Pet: 2,000 to 4,000 triangles (rigid avatar accessories have an official 4,000 budget). Evolved pet: up to 6,000. Boss: up to 12,000 to 15,000. Prop: up to 1,500. Floor or wall tile: up to 500.
- Busiest phone view (lobby with 16 players and their pets): at most about 300,000 visible triangles and about 400 draw calls.
- SmoothPlastic or Neon only, no textures, and one asset per reused prop, cloned.

Delivery risk (FORUM t/4730088): fresh mesh assets sometimes fail to draw for some clients. MeshLibrary handles this with a per-device fallback after PreloadAsync fails.

## sources

- https://create.roblox.com/docs/cloud/guides/usage-assets (local: research/docs/cd/content/en-us/cloud/guides/usage-assets.md)
- https://create.roblox.com/docs/reference/cloud/assets/v1 (local: reference/cloud/assets/v1.json; per-endpoint rate limits in reference/cloud/openapi.json)
- https://create.roblox.com/docs/cloud/reference/rate-limits
- https://create.roblox.com/docs/cloud/reference/patterns
- https://create.roblox.com/docs/cloud/auth/api-keys
- https://create.roblox.com/docs/reference/engine/classes/InsertService
- https://create.roblox.com/docs/reference/engine/classes/AssetService
- https://create.roblox.com/docs/reference/engine/classes/MeshPart
- https://create.roblox.com/docs/reference/engine/classes/TriangleMeshPart
- https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance
- https://create.roblox.com/docs/reference/engine/classes/EditableMesh
- https://create.roblox.com/docs/reference/engine/classes/PackageLink
- https://create.roblox.com/docs/studio/importer
- https://create.roblox.com/docs/parts/meshes
- https://create.roblox.com/docs/art/modeling/specifications
- https://create.roblox.com/docs/art/modeling/export-requirements
- https://create.roblox.com/docs/art/modeling/surface-appearance
- https://create.roblox.com/docs/art/modeling/texture-specifications
- https://create.roblox.com/docs/art/blender (Adjust scale FBX, Vertex painting)
- https://create.roblox.com/docs/art/modeling/roblox-blender-plugin
- https://create.roblox.com/docs/projects/assets/privacy
- https://create.roblox.com/docs/projects/assets/packages
- https://create.roblox.com/docs/performance-optimization/improve
- https://create.roblox.com/docs/performance-optimization/design
- https://create.roblox.com/docs/marketplace/validation-system (vertex colour tinting)
- https://github.com/Roblox/creator-docs (commit 7400643, 2026-10-20: source of all docs above)
- https://github.com/Roblox/roblox-blender-plugin (commit 37a7306: lib/export_fbx.py, lib/upload_operator.py, lib/constants.py, dependencies_private/assets_upload_client.py)
- https://devforum.roblox.com/t/open-cloud-upload-support-for-more-asset-types/4022082 (staff 2025-10-23: legacy upload endpoints deprecated; rbx-dom caveat)
- https://devforum.roblox.com/t/vertex-colored-meshes-using-blender-and-studio/3050119 (staff: vertex colour multiplied by Color; default grey)
- https://devforum.roblox.com/t/coming-changes-to-insert-service/30327 (staff: client LoadAsset blocked)
- https://devforum.roblox.com/t/insert-models-on-the-client/2564555
- https://devforum.roblox.com/t/2339955 (packages load with InsertService)
- https://devforum.roblox.com/t/allow-applying-baked-mesh-content-to-a-meshpart-without-a-lag-spike/4752538 (CreateMeshPartAsync about 22 ms blocking; ApplyMesh about 0.01 ms)
- https://devforum.roblox.com/t/createmeshpartasync-doesnt-work/2848207 (InsertService:CreateMeshPartAsync plugin-only)
- https://devforum.roblox.com/t/4730088 (2026-07: fresh meshes invisible for some clients)
- https://devforum.roblox.com/t/4765232 (2026-07: LoadAsset not authorized when owners differ)
- https://devforum.roblox.com/t/opencloud-assets-api/2298007 (moderated name gives 400; multipart 415)
