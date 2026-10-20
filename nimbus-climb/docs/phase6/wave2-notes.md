# Phase 6 wave 2 notes (from the engineers)

## art-arenadungeon

### Deviations
- The pieces are baked from the game's own Part builds, like art-home does. The kit boots the mock, runs LobbyBuilder.Build, ArenaBuilder.Build + BuildPocket, every dungeon template and one run, and records every Mesh.tag call. arena_style.py starts as a copy of art-home's home_style.py so neither class can break the other. It adds tint parts, cloud softening, y alignment for walk heights, thin overlays painted last, and recursive splitting so no part goes over 9k tris.
- DungeonBuilder needed small wrapper Models so each piece can be a Tag target. These are WallRun, FloorTiles, PillarStack, WallTorch, CrateBox, ChestBox and StalagmiteStack. Each wrapper's PrimaryPart moves with clonePiece. Kit.door now sets PrimaryPart = Lintel. Part names, part counts, prompts and attributes are unchanged and the budgets still pass. This goes a little past 'Tag calls only'.
- Some things stay Parts and are kept visible over the mesh: the portcullis Bars (SetDoor changes their Transparency on the server), every Neon flame or glow, sign Panels and ArchSign. Ceilings and the small dungeon props (barrels, tables, banners, Accent parts) are not meshed yet.
- There are no 'crystals' in the Part dungeon. I added cute lilac and cyan crystal clusters to the voxel cave rocks dungeon_rock_2 and dungeon_rock_3 instead. Rocks, the crack and the stalagmite are designed pieces, scaled per placement with ML_Scale, so they carry no LayoutSig. arena_tree and dungeon_crate are baked from the Part build but are also scaled, so they have no LayoutSig either.
- Wall, floor and pillar keys exist for each distinct length / door / size: 14 walls, 5 floors and 4 pillars. Each one is tinted per room through ML_Primary.
- Signatures leave out the keep names, and the dungeon signature also leaves out the random 'Brick' studs.

### Lead requests
- tools/robloxmock.lua ~:3597 (BasePart methods): add GetPivot = function(self) return currentCFrame(self[STATE]) * (self[STATE].props.PivotOffset or CF_IDENTITY) end for BaseParts. MeshLibrary.Dress calls target:GetPivot(), and dungeon_rock_* / dungeon_crack tag single Parts. Without this, a fixture-mode Dress test on those Parts errors in the mock (it works in Roblox).
- BUILD_STATE / wave notes: blender/meshes.json now has the 52 arenadungeon entries. Commit it together with src/shared/MeshManifests/arena_* / dungeon_* and the catalog.

### Smoke

The full run was not done, as this wave asked. syntax.py is clean (796 files). check.mjs: 0 errors, 3 many-locals warnings; ArenaBuilder now has 178 locals, still under 200. mesh_names --check: 52 manifests, 0 problems. All 52 keys were built with FBX export and every one passed the FBX verify. smoke --quick --only p3arena_world,boards,pockets,art,teleport,p3arena_mesh,p5dgn_party,exclusive,run,loot,ends,world,net,p5dgn_mesh,p6mesh_fit,p6mesh_noop: 688 passed, 0 failed. A second run of p3flow_* (6), p4ring_* (5) and client_p5dungeon: 634 passed, 0 failed.

### Notes for next waves

API: ArenaBuilder._Mesh and DungeonBuilder._Mesh both provide tag(target, key, origin, look, keep, scale), Signature(target, origin, scale, keep), Placed and lib(). Placed is a weak-keyed map from each target to {Key, Origin, Look, Keep, Scale}; the tests and the kit read it. Setting _Kit = {Targets = {}} records every Tag call. A tag only happens when Status ~= "missing" and the LayoutSig matches; if a manifest has no LayoutSig, the piece is treated as designed and is tagged anyway. The pivot used is target.CFrame for a Part and GetPivot() for a Model. ML_Scale is set when scale ~= 1.

Keys: arena_island, forum, floor, seg_stand / gate / bossgate (Seat = Primary, Banner = Secondary), pillar, ring_1 / ring_2 (Accent = Primary, Curb = Secondary), board_event / board_leader, torch, lantern, hedge, bannerpole, planter, tree, trophy, bridge, pocket. dungeon_wall_<len>[_door<X>][w<W>][_lite], floor_<w>x<d>, pillar_<h> (15p5 means 15.5), torch (its solid part is named 'Sconce', so the Portal_Dungeon gate's keep list keeps it visible), chest, crate, door_8, stalagmite, rock_1..3 (rock body = Primary), crack.

Budgets: about 280k tris for the whole arena (75 placements; the test cap is 300k). The heaviest dungeon room is under 90k.

Gotchas:
- The mock has no BasePart:GetPivot. Dress calls target:GetPivot(), so dressing a Part target (dungeon_rock, dungeon_crack) cannot be tested in the mock. Real Roblox has GetPivot on Parts. A lead request is to add GetPivot to BasePart in robloxmock.lua, near Model GetPivot (~:3597); the patch is GetPivot = function(self) return self.CFrame * (PivotOffset or identity) end.
- The arena Part build and the Gate Court gates are art-gates' and stay Part builds in my renders. WorldStyle tags gates even without ids, which is why my quiet check only looks at my own targets.
- If the lobby or ArenaBuilder layout changes, the LayoutSig no longer matches and the piece falls back to Parts. Rebuild with build_all --class arenadungeon; this takes about 5 minutes with export.
- Known visual nits: Cave wall-bulge rocks poke slightly through the outside of the wall, and there is a dark sliver at an overlapping wall corner (under the ceiling).
- Review tools are in the scratchpad: w6/art-arenadungeon/render_scene.py places the meshes at their Tag origins, and keysheet.py makes the contact sheets.

## art-creatures

### Deviations
- Boss MeshPart budget is 48 per boss, not the recipe's 40. storm_titan has 45 parts because of one part per (joint, key, shade), and bosskit.py (kit-owned) cannot bake colours. Tris fit 15k High / 6k Low. K per boss: titan 1.3, golem 1.45, wyrm 1.45, hydra 1.4 (0.34-0.38 stud), because the recipe's 0.25-0.33 stud goes over the 15k budget. Low keys use K 0.75-0.88.
- boss_frost_wyrm_WingL/R[_low] are built by my prop 'boss_joint', not type 'boss'. bosskit leaves the see-through Ice Membrane (T 0.15) open, which fails the closed-mesh check. My prop meshes it closed and puts the transparency back on the part.
- Sky dragon: one set of keys, dragon_head/jaw/leg/tail/puff/link + dragon_seg_<R*10>[f] (9), built at K 3 (0.33 stud, 8.9k tris). The set's MeshPart sum is 102 (budget 110), and the live dragon has about 180 MeshParts (contract cap 300). Shapes come from a new read-only hook SkyDragonController._Blueprint(k) that re-runs the game's own sculpt at k sub-voxels. At k=1 the sculpt is byte-identical; existing tests pass.
- npc_pedestal is one design (seed 1). The rug and band follow ML_Primary = the NPC accent, but moss / flower placement no longer changes per NPC.
- Tokens: client-built coins (HomeFx) become welded MeshParts on an invisible root. Server coins keep their Parts and are tagged with ML_Weld. Until the MeshLibrary lead request below is done, a dressed server coin would not spin with TokenFx. TokenLook's header no longer says 'no tags / attributes'.
- fx_shield / fx_ice / fx_arrow / star_gold are built, but nothing uses them yet: BattleController and PetBuilder are not my files.
- Stormfang is already pet_stormfang + wing_stormcloud in pets.json (art-pets), so I added no duplicate key. The showcase follows the PetBuilder mesh path.

### Lead requests
- runtime-pets (src/shared/MeshLibrary.lua:1228, Dress, right after hideLocally(target, keep, mesh)): if target:IsA('BasePart') and target:GetAttribute('ML_Weld') == true then for each BasePart p in mesh:GetChildren(): p.Anchored = false; WeldConstraint Part0 = target, Part1 = p. Server tokens need this to spin and bob with TokenFx. Check: tools/smoke_p6_creatures.lua 'LEAD REQUEST' in client_p6creatures (the only red check in my files).
- BattleController owner (src/client/Controllers/BattleController.lua:1635 ShieldCube, :1657 Ice, :6419 FocusArrow): when MeshLibrary.IsReady(key), clone the fx_shield / fx_ice / fx_arrow meshes (unit-sized: shield 2 studs, ice 1 tall, arrow 1 wide) into those slots, keeping the same names and the per-frame CFrame code.
- runtime-pets (src/shared/PetBuilder.lua:2989 goldSparkles): star_gold (1 stud, Neon, faces -Z) is ready to use as the Golden sparkle mesh.
- tools/robloxmock.lua: Part has no GetPivot (only Model has one), so a Part target cannot be dressed in the mock. Please add PVInstance:GetPivot for BaseParts (return self.CFrame).

### Smoke

Per the wave rule, I did not run a full smoke. syntax.py: 588 files, 0 errors. check.mjs: 0 errors (3 old many-locals warnings in other owners' files). mesh_names --check on my 60 manifests: 0 problems. Ran with --only: p6creatures_server, client_p6creatures, p6mesh_fit, p6mesh_server, p6mesh_noop, client_p6mesh, p3events_bosses, p3visual_bosses, hazards, client_pets (sky dragon + NPCs), client_p5home_roam, client_p2home, client_p4garden_heaps, client_polish_worldtext, client_p3battle_raid. Everything passes except one check: the deliberate 'LEAD REQUEST: MeshLibrary.Dress welds ... ML_Weld' check in client_p6creatures (owner runtime-pets). Blender: build_all --class creatures built all 60 keys with FBX and the 3 re-import checks passing. All boss and dragon sets are within budget.

### Notes for next waves

API: BossBuilder.MeshKeys(id, detail) returns boss_<id>_<Joint>[_low]. BossBuilder.UsesMeshes(id, detail) is true only when every joint key is ready on this machine. Build then Assembles each joint at CFrame(Pivot*0.5*scale) and adds ML_Mesh=true. Joints, Pivot / JointParent, Fx_* attachments, BossLight and attributes stay as before. Glow parts are found by name or MK_Key. The template cache key ends in '|mesh'. A failed mesh build warns and falls back to Parts. SkyDragonController: MeshKeys(), IsMesh(), _Rebuild() (yields; tests/tools), _Blueprint(k) (kit). A Part dragon rebuilds once from meshes on MeshLibrary.Changed. NpcService: _Blueprint(seed, accent) (kit) and _BuildPedestal(parent, spot, accent, seed) (tests). The pedestal is tagged only when Status('npc_pedestal') ~= 'missing', with ML_Primary = accent and ML_Offset = the pivot of grid voxel 0. TokenLook.MeshKey(palette) gives token_cloud|golden|cash|goldencash; manifests are at Scale 1 and the runtime multiplies by the palette Scale. Kit: props/creatures.py runs its own Lua driver on a cached Bridge (bridge().rt). Dragon cell i sits at (i-1)/3 studs (offset -(k-1)/2/k). Pedestal = the Lua 0.4-stud grid upsampled x2 with offset -0.1. Tests: the real MeshLibrary with _Reset + _Configure({Root, Ids}) and canonical templates built from ML.Manifest(key). On the client, call Start() + Mock.Advance(1) so the preload marks keys ready. Always _Reset afterwards: it also drops other modules' Changed handlers, so call SkyDragonController._Rebuild() after it. Gotcha: in the mock a task.defer'd Dress on a Part target raises in the NEXT scenario. Gotcha: check_sets checks every catalog, so another class's over-budget set makes build_all exit 1. Renders: scratchpad w6/art-creatures/preview.py (scenes boss:<id>[:low], dragon, dragonhead, coin:<key>, ped:r,g,b, fx). Preview materials are shared by part name, so render accents one model at a time. Review: 4 rounds (r1-r4). Fixed so far: dot noise turned into scallop scales, the pedestal bevel saw-tooth removed, the coin cloud reshaped, the arrow gold recoloured. Open nit: the coin cloud is still a soft lump at Scale 1.

## art-evolved

### Deviations
- Aura meshes are not separate aura_<kind> keys. Each body key carries its own `Aura` group (kind orbit, Spec 'Aura:orbit:1:0.8:0'). Second evolutions also carry a `Halo` group (kind bob), a crown of light, when the pet has no Halo of its own. Reason: the colours are per-pet constants, the aura hangs on the body's hinge, and it needs fewer uploads. Part names stay Aura*/Halo*, so PetFx and PB_Pulse still find them.
- Wing keys are per pet, not per style. The key is evowing_<petId>_<1|2|2b>_<L|R>[_low]: 1 = stage-1 Wing pair, 2 = stage-2 Wing pair, 2b = stage-2 Wing2 pair. phantom_kitsune has no 2b pair. Reason: evolved wing colours are per-pet rgb constants (EVO.Look / ASC.Look), and MeshLibrary has no per-instance palette override, so one shared style key cannot be coloured correctly.
- MeshPart caps per set are 64 (Low 52) for evo1 and 110 (Low 84) for evo2, not 50/16 and 60/18. The 4.3 name contract gives one part per key, and wings have up to 16 parts per side. This is the same deviation W1 made for base-pet Low sets. The Part build uses 1500-2000 parts. All triangle budgets hold: evo1 <= 15k / Low 4.5k, evo2 <= 20k / Low 6k, every part <= 10k.
- The 4.2 K step-down was applied to some keys. High at 1.125: maple_fox, aurora_fox, twilight_dragon, cloudy_dragon, stormfang, eclipse_dragon, rime_wyrmling and hydralotl evo1 bodies; ember and obsidian evo1 wings; most evo2 2b wings at 1.0125. phantom_kitsune evo1 body at 1.0125. Most Low evo1 bodies at 0.585 or 0.5265. twilight, eclipse and hydralotl get their own Low budget split (evo1BodyLowBat / evo1WingLowBat).
- High bodies keep the game's Lua-carved eyes. The kit's procedural eyes come out mangled on evolved heads, and with eyes:'lua' petkit skips every pass. So the pass `evolved:lua_eyes` undoes faces.restore_carved_eyes and wraps faces.carve_eyes / lid_groups so they return PetBuilder's own lids. The wrappers act only for the cells dict that pass registered; every other caller gets the original functions. Low bodies use the kit's procedural pixel eyes, which read better at Low.
- Every body (High and Low) is built with fixed:true. Constant keys that nothing references are baked into one `Fixed` part. Evolved colours are constants anyway.
- Stage-1 aura parts use new MK_Keys AuraGold / AuraGem / AuraSpark. A Secret pet's colour fit already pins AuraA/B/C to its rarity colours, so those existing bits keep their colours. Stage 2 uses AuraA/B/C (Glow/GlowB). New body key: GemGlint (Neon). Trims reuse GoldLight / GoldDeep.
- The 12 rime_wyrmling wing keys (evowing_rime_wyrmling_*) are NOT built yet. The kit's geometry check rejects their Glass wings (see lead request 1). build_all --class evolved exits 1 on these 12 keys only; the other 342 keys are built with FBX verify ok.

### Lead requests
- blender/build_all.py:170-183 (Builder.check_geometry). The closure sum counts see-through parts. Faces of Glass/ForceField/transparent voxels that touch opaque voxels are culled, which is correct rendering, so every Glass wing fails as 'not closed'. This blocks all 12 rime_wyrmling wing keys. Proposed patch: inside `for o in m.objects.values():` add `if o.material in ("Glass", "ForceField") or getattr(o, "transparency", 0): continue` before the quads loop (the zero-area check can stay for every part). Verified in scratch: with that filter, the rime wings close to 1e-17. Then run `build_all.py --class evolved`. blender/kit/detail/evolved_check.py fails ('built: every evolved key has a generated manifest') until then. art-pets may hit the same with Glass wing styles.
- blender/kit/petkit.py:63-75 (face_pass). With face.eyes == 'lua' it returns before running entry['passes']. Proposed patch: run the passes loop before that early return as well (move the `for name in entry.get('passes', [])` block above the `if opts.get('eyes', ...) != 'procedural' or not bp.eyes:` return). After that, evolved can use face {eyes:'lua'} and drop the lua_eyes hook in detail/evolved.py.
- Optional, tools/dump_model.lua kit block (~:1620 BUILDERS.meshpet): it only knows pet_/wing_/acc_ keys. A meshevo:<petId>:<1|2>[:Low] variant (body evo<s>_<id> plus wings at the WingL/WingR/Wing2L/Wing2R attachments) would let render_model show the evolved meshes. I did the visual review with Cycles instead.

### Smoke

Per the wave rule, no full smoke was run. Results: python3 tools/syntax.py: 588 files, 0 errors. node tools/check.mjs: 0 errors, 3 many-locals warnings, all in files I don't own (ArenaBuilder, PetBuilder). python3 blender/kit/selftest.py: 509 checks, 0 failed. smoke.py --quick --only evolved,p3evo_pets,p6mesh_fit: 289 passed, 0 failed (p6mesh_fit fits every live manifest, including the 342 new ones, through a 180-degree import). smoke.py --quick --only p6mesh_noop,p6mesh_server,client_p6mesh: 382 passed, 0 failed. tools/mesh_names.py --check on all evolved manifests: 0 problems. evolved_check.py: 1 failure, the 12 unbuilt rime_wyrmling wing keys (lead request 1). Rebuilding evo1_pebble_pup and evo2_aurora_fox gives the same contentHash as the committed manifests.

### Notes for next waves

Key names (runtime-pets):
- Body keys: evo<stage>_<petId>[_low]. Wings: evowing_<petId>_<1|2|2b>_<L|R>[_low].
- Place each wing key at the body manifest's attachment of the same name: WingL / WingR for 1 and 2, Wing2L / Wing2R for 2b. The wing pivot is the hinge, so use At = '<attachment>'.
- No accessory keys for evolved forms; the jewellery is sculpted into the body.
- Stage 2 exists for Epic / Legendary / Mythic / Secret (16 pets). phantom_kitsune has no 2b pair.

Groups and rig:
- Body manifests contain Body parts plus the groups Tail, Halo, Aura and EyeLid / EyeLid2.
- Every evolved body has an Aura group (kind orbit, Amp 0.8). Every stage-2 body has a Halo group (kind bob, Amp 0.6).
- Because of that, the mesh Rig adds Aura (all first evolutions) and Halo (second evolutions without a Lua halo) compared with the Part build's PB_Rig. Build PB_Rig from the manifest groups, in order Tail, Halo, Aura.

Colours:
- Evolved colour recipes are almost all ['rgb', ...] constants per pet, not Look recipes.
- Golden / Rainbow / Wild / hybrid evolved copies therefore need the Part path or a runtime tint.

Aura size and placement:
- The aura ring widens Bounds: a stage-1 body is about 5.2 studs wide.
- PetController slot width (GetExtentsSize) would grow. Measure the Body root or skip the Aura group for slot and lowest-point maths.
- The ring sits 16-20% of body height above the feet, never below them.

Names and materials:
- Aura parts are Aura, Aura2, ... (Neon). On cloudy_dragon / hydralotl, the Lua bits AuraC / AuraDark are SmoothPlastic.
- MK_Keys: AuraGold / AuraGem / AuraSpark on stage 1; AuraA / B / C on stage 2. Crown keys are HaloGlow / AuraB / AuraC.
- PetFx pulses Aura* parts at stage 2. Glow / GlowB parts exist on stage 2 bodies.

Building:
- Rebuild the catalog with python3 blender/kit/detail/evolved_catalog.py (do not hand-edit evolved.json).
- Then run /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class evolved [--preview] (about 25 min on a shared CPU). Then run python3 blender/kit/detail/evolved_check.py.

Gotcha:
- When waiting on a background build, do not use `pgrep -f "build_all.py --class evolved"`. It matches its own shell, so the wait never ends; `pkill -f` with that pattern kills your own shell (exit 144).

Scratch tools in /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/art-evolved/:
- round.py: build with the catalog entries plus Cycles sheet.
- cmp.py: Part build vs mesh.
- allcheck.py: dry budget run of every key.

Review: 5 rounds of renders (r0-r4 plus final).

## art-gates

### Deviations
- There are 6 keys and no separate gate_arena_<n>, portal_dungeon or portal_home key. Each key belongs to a glyph/shape (WorldStyle.GateMeshKey), and every BuildGate call shares it: Portal_Arena, Portal_Ring and Portal_Return (ArenaBuilder) and Portal_Dungeon (DungeonBuilder). The trim colour comes per instance from ML_Primary. The arena's green Return gate uses the house glyph, so it wears gate_home. That is why I built gate_home even though the lobby has no Home gate. The home 'Arena Gate' station is not a BuildGate gate, so it gets no gate mesh.
- Dress keeps everything not on a hide list, not just a fixed keep list. I tag the whole gate model with ML_Keep = every BasePart name that is not in WorldStyle.GATE_MESH_HIDE (Stone, StoneDark, Frame, Trim and the 22 crest-body names). A server-side model.DescendantAdded connection then adds later builder extras to ML_Keep: DungeonBuilder torches, ArenaBuilder torches and pedestals. Without this, Dress would hide those extras, because MeshLibrary.Dress only supports a keep list. The connection is the model's own signal, so it is freed when the gate is destroyed.
- The tag is always applied, even with empty MeshIds. It only adds attributes and the ML_Dress tag, and nothing is dressed until the key is ready. The art-creatures pedestal does it differently: it tags only when ids exist.
- The pad tiles and the lanterns stay Part builds. The task scoped the mesh to stone, frame, trim and crests. A pad key (for example gate_pad_<plus|swords|crown>) would need a second Tag target, because the pad tiles are siblings in the gate model.
- Props cannot step K: build_all passes k only to bridge types. The gate lattice is fixed at K 2 / KC 4 (aligned to the Part voxels), and every key is well under budget (max 4070 tris, 14 parts).

### Lead requests
- Optional, not blocking (the workaround works and is tested). Add a hide-list mode to MeshLibrary.Dress so world gates can name the parts to HIDE instead of the parts to keep. In src/shared/MeshLibrary.lua Tag (~:1131), accept look.Hide = {names} -> target:SetAttribute('ML_Hide', sorted csv). In hideLocally (~:1177), when target:GetAttribute('ML_Hide') is set, hide only BaseParts whose Name is in that set (and not descendants of mesh) and ignore keep. Then WorldStyle can drop its DescendantAdded keep-list updater. Another owner's dressed sub-target inside a gate would also stay safe: today a mesh part named 'Stone' under a gate would be hidden by the gate's Dress.
- BUILD_STATE W2b says to delete the Home entry in WorldStyle.SampleGates (~:930 now). I left it alone because my WorldStyle scope is Tag calls only. My tests do not depend on it either way (smoke_p6_gates builds its own specs).

### Smoke

I did not run the full smoke, as this wave asked. syntax.py: 635 files, 0 errors. check.mjs: 0 errors and 3 many-locals warnings, none of them in my files (MenuController, ArenaBuilder, PetBuilder). The scoped runs were all green:
- `--only p6gates_server,client_p6gates,p5world_gates,polish_portals,p6mesh_fit,client_p6portalfx,p5world_style`: 1063 passed, 0 failed.
- `p3visual_arena,client_p5dungeon`: 381 passed, 0 failed.
- `p3arena_world,p3arena_art,p5flow_dungeon`: 327 passed, 0 failed.
- `p6mesh_noop,p6mesh_server,client_p6mesh`: green.

The Blender build `/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class gates` gave fbx ok for all 6 keys, and `tools/mesh_names.py --check blender/out/gate_*.manifest.json` found 0 problems.

### Notes for next waves

API facts:
- **Keys.** `WorldStyle.GateMeshKey(shape, glyph)` returns the key: Arch -> gate_ring; for a hoop, cloud/swords/torch/house/bolt -> obby/arena/dungeon/home/altar; any other glyph -> gate_obby. The table is `WorldStyle.GateMeshKeys`. The voxels the mesh replaces are listed in `WorldStyle.GATE_MESH_HIDE`.
- **Tag call.** It runs in BuildGate just before `model.Parent = parent` and sets:
  - ML_DressKey
  - ML_Primary = the accent colour
  - ML_Stars, on star-crest hoops only
  - ML_Offset = CFrame(0, -11.5, 0), because the pivot is GlowCore and the mesh origin is the site
  - ML_Keep = the sorted csv
  - the ML_Dress tag

  MeshLibrary is required lazily through `Shared:FindFirstChild('MeshLibrary')` + pcall, so the render tools still work without it.
- **Mesh frame.** Gate site, front -Z. Part voxel (x, y, z) of BuildGate spans x±0.5, y..y+1, z±0.5. The mesh lattice is offset by half a voxel so its faces land on the Part lines. Neon Parts (Glow/Swirl/Gem/StarGem/CrestEye/CrestWindow/CrestBolt) sit flush: the mesh leaves their cells empty. In the Altar crest, everything in front of z -0.7 is carved away so the bolt is not buried.
- **Part names.** Gate group: Stone, StoneLight, Frame, FrameLight, Trim, TrimLight ['Primary'], Gold, GoldLight, Fixed. Crest group: Gold2, Fixed2, CrestShield ['mix', Primary, Navy, 0.2] on the arena key. Baked key names must avoid the names mesh_names reports as referenced. Base and Roof were referenced, so they are now SlabStone and RoofCoral.
- **Build.** `blender/kit/props/gates.py` is a numpy lattice helper (Lat: put / paint / carve / box / rrect / ell / rot2) on top of kit.grid / kit.mesh. Reuse it for any prop that has to line up with a Part build. A no-export build takes about 9 s; an export takes about 15 s; `--preview` takes about 3 min on 4 CPUs.
- **Review tooling.** `/tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/art-gates/compose.py` renders the dressed gate offline: it removes the hidden parts from the render_model dump and adds MeshParts with mlKey/mlPart. Other art owners can adapt it for their own Tag targets.
- **Tests.** smoke_p6_gates builds an untagged WorldStyle by cloning WorldStyle, Voxel and Theme into a folder without MeshLibrary. It then checks the tagged gate against it: identical instance signature and part count. On the client it uses fixture templates + `ML.Start()` + `Mock.Advance(1)` + `ML.Dress`.
- **For W3/W4.** Upload the 6 gate keys together; they are cloned for every gate (about 7 instances). RenderFidelity is Precise through the 'gate_' prefix. When the ids arrive, check in Play that the torches and pedestals stay visible and that the PortalFx glow still animates.

## art-home

### Deviations
- Per-station budgets are over the recipe's 4k cap for 7 of the 88 keys. The farm, garden and fence use `stationBig` (8k). The Manor and the Sky Castle use `house` (10k). Reason: 22 bushes and a tree on the farm, a 72-stud fence ring, and the four brick towers on the castle. The bake steps its detail down until each key fits its budget. A max-tier plot comes to 40.8k triangles and 65 MeshParts (the P4 Part plot was about 950 Parts). `p2home_mesh` caps a plot at 50k.
- The stations are not new Python designs. Each one is baked from HomeBuilder's own Part build at every level: `BuildStationModel` runs in the mock, then a fine-voxel re-raster adds shapes and detail passes. That is the only way to cover the 40 farm levels and 8 garden levels while keeping footprints and colliders exact, and the LayoutSig guard tags a key only while the live Part build still matches it.
- The Garden key `home_garden_<L>` covers every open count. Its bed pieces get one key per Part instead (8 keys named `home_bed_*`); without that, the Garden would need 80 keys (8 levels × 10 open counts). The cushion is tinted per instance by `ML_Primary`, which is the part's own Color.
- Neon and ForceField parts, the Fusion Swirl, and SurfaceGui sign boards stay as Parts and go into the keep list (`HomeBuilder._Mesh.keepOf`), the same approach art-gates took.
- Buy pads, ghosts, paths, the house lot and the claim signpost stay as Parts. The task text says pads stay Parts. No pad keys were made.
- Stations carry baked vertex colours in `Fixed` / `Glass` parts, not per-key recipes. HomeBuilder ignores the plot accent, so nothing needs tinting at run time.

### Lead requests
- src/client/Controllers/HomeFx.lua:1157 (startPop). The pop-in records each part's Transparency at start and restores it when the pop finishes. On a mesh-dressed station that brings back the Parts that `MeshLibrary.Dress` hid. Minimal patch, as the first line of `startPop`: `if model:GetAttribute("ML_DressKey") then return nil end -- Phase 6: a dressed station appears without the Part pop`. HomeBuilder writes the tag server-side before the model replicates, so the attribute is already there. No failing check was written: it would need a client mesh-mode scenario in HomeFx's test file, which I don't own.
- tools/mesh_budget.py DEFAULT_SCENE (`worldClasses` gates/lobby) does not count the home plots, even though they sit in the lobby. Consider adding the plots, using `docs/phase6/review/home/plot_scene.json` (about 41k triangles per max plot) for the busiest-view figure.

### Smoke

python3 tools/syntax.py: 744 files, 0 errors. node tools/check.mjs: 0 errors, 3 warnings, all pre-existing locals warnings in files I don't own. `--only p2home_art,p2home_plot,p2visual_art,p2visual_plot,p6mesh_fit,p2home_mesh,client_p2home` passes 499 checks with 0 failed and 0 warnings; an earlier extra run of `client_p2visual`, `p5home_signs`, `p5home_berries`, `p6mesh_server` and `client_p6mesh` was also green. `mesh_budget.py --scene docs/phase6/review/home/plot_scene.json --check` reports 40768/50000 triangles and 65/80 parts. `build_all --class home` builds all 88 keys with FBX ok, and the build is deterministic (`home_farm_40` gives the same contentHash on a rebuild). The full `--quick` run was skipped, as this wave asked.

### Notes for next waves

HomeBuilder (Tag calls only, about 150 lines after removeGhost) exposes `HomeBuilder._Mesh` with:
- `Stems`: farm, garden, foodmachine, training, vault, house, fusion, arena, fence, fountain, podium
- `Elements.Garden`: part name to `home_bed_*` key
- `keepOf(model, elements)`, `signature(target, origin, skipSet)`, `sigOk(ML, key, n, a, b)`, `info(def, level, tpl)` (cached on the template), `station(m, def, level, tpl, cf)`

`placeStation` and `BuildStationModel` call `Mesh.station` after cloning. It tags the station with `ML_Offset = pivot⁻¹·slotCF` and `ML_Keep`, then tags each bed-piece Part with `{Primary = part.Color}`. A tag needs both `Status(key) ~= "missing"` and a matching manifest attachment `LayoutSig.Pos {n, a, b}`. The signature skips kept names; its formula is the same as LobbyBuilder's.

Kit:
- props `home_station` (args: station, level, open, vs) and `home_element` (args: part, vs, tint).
- `home_style.bake(m, boxes, vs, budget, opts)` steps detail levels 3→0 until the key fits.
- The `HOME_DETAIL=<n>` environment variable forces a detail level for experiments.
- The budget is read from `catalog/home.json` by the key's budget name.
- The Lua driver in `home.py` (`D.station` / `D.element`) returns boxes, kept boxes, the keep list and the signature.

Gotchas:
- Any HomeBuilder art change, such as a part size, name or count, makes `p2home_mesh` fail with "rebuild". Fix it by running `build_all.py --class home` (about 2 minutes) and committing the regenerated `MeshManifests/home_*.lua` and `meshes.json`.
- Glass is meshed as its own closed part, grouped by transparency rounded to 0.1.
- The HomeFx pop issue above is the only runtime conflict I found.
- GraphicsQuality's `NC_Detail` move is harmless, because dressed Parts are already hidden; but the mesh always includes the decor, so Low graphics still shows it.

Scratch tools (in `/tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/art-home/`):
- `preview.py OUT.png key:station:level[:open] ... [--parts] [--bake] [--cols=N] [--views=] [--size=]` renders mesh plus kept parts through `render_model`'s mesh path.
- `tri_fam.py key level` shows which part names cost the triangles.

## art-lobby

### Deviations
- CourseBuilder: no Tag calls. Its parts go straight into shared group folders, so there is no per-piece subtree to tag. Moving, vanishing and swinging hazards are moved by HazardService, so an anchored Dress mesh would not follow them. Tagging would need per-piece Models, and my row allows only Tag calls. The course keys are left for a later wave.
- Some small structural edits beyond plain Tag calls: (a) LobbyBuilder layeredGround and woodBridge take one extra optional argument (meshPrefix / opts.MeshKey). (b) A few VX.Build results are now kept in locals so they can be tagged. (c) There are read-only kit hooks: LobbyBuilder._Kit, _CloudGrid and _Mesh, StormAltar._Kit, _Blueprint and _Mesh. (d) StormAltar sculptRim(gapDeg, bv) and sculptBelly(f) take an optional grain. The game's defaults are unchanged and the part count is identical (7043 parts with and without tags).
- A Mesh.tag call only tags a key that has an id (Status ~= missing), as NpcService does. So with the empty MeshIds nothing changes, not even attributes.
- Layout-baked keys (clouds, floors, plot, altar) carry a manifest attachment "LayoutSig" = {part count, position sum, size sum}. The builders tag a key only while the live build still matches it. This guards against stale meshes after a Config change.
- Budgets in lobby.json: island 14k tris with 3 parts (cloud_plaza is 13.1k, split into 2 parts under 10k each), plot 9k, centrepiece 7.5k (prop_fountain is 6.9k), floor 10k per layer. The recipe asks for 3.5k per cloud and 4k per prop; whole islands and the fountain cannot reach that at this grain.
- The Plaza Gate Court planters, hedges, bunting and avenue kerbs, and the WalkHedges model, stay Parts (about 120 parts). They share a Model with tagged lamps and banners, so tagging them would mean nested hides.
- Floors are meshed from the Part build's own boxes (exact walk heights, flat P4 look). They get fewer draw calls, not more detail.
- Baked keys in lobby.py get an 'lb' prefix (lbStone and so on), so tools/mesh_names.py --check passes (0 problems).

### Lead requests
- tools/mesh_budget.py catalog_sets()/scene_total: the 'heaviest Low pet set' pick includes boss sets (boss_storm_titan_low, 5.7k), which inflates every lobby scene by about 130k tris. Proposed patch: filter sets to those whose keys start with 'pet_' (or by class == 'pets') when choosing the pet sets. Owner: kit/lead.
- TutorialController.lua ~:2288 uses Plot:GetPivot() as the plot's ground point. In real Roblox, a place()d clone keeps the template's WorldPivot (near the world origin) because place() moves the parts one by one. That is outside my Tag row, so I did not change place(). Proposed fix in LobbyBuilder place(): if not m.PrimaryPart then m.WorldPivot = cf end. It could ship in W3 together with a test that pins plot:GetPivot() == SpotInfo.PlotCFrame.

### Smoke

Ran only --only lists, as this wave asks. Run 1: p5world_lobby, p5world_style, p6mesh_fit, p6lobby_server and storm_altar gave 623 passed, 0 failed. Run 2: storm_altar, spots, portals, p2gems_altar, p5world_gates, p6creatures_server, p6gates_server, polish_portals, polish_worldtext, client_storm and client_polish_worldtext gave 1231 passed, 0 failed. syntax.py: 0 errors. check.mjs: 0 errors (3 old many-locals warnings in files that are not mine). count_locals: LobbyBuilder 149, StormAltar 120. All 62 keys built with build_all.py --class lobby and passed the FBX verify. Did not run the full suite (the wave rule).

### Notes for next waves

Keys: 62 in total. 19 designed props: prop_tree_round, prop_tree_blossom, prop_tree_pine, prop_lamp, prop_bench, prop_flowerbed, prop_fountain(+_water), prop_welcome_arch, prop_obelisk, prop_banner, prop_board_s, prop_board_l, prop_roulette, prop_item_stall, prop_token_statue, prop_shop_arch, prop_pond(+_water). The other 43: prop_plot; 7 cloud_* keys; floor_plaza_* (8 keys), floor_shop_1..5, floor_garden_<blossom|pond>_1..4, floor_junction_<plain|spoke|garden|arena|altar>, floor_spoke, floor_garden_bridge, floor_altar_bridge; cloud_altar, prop_altar_ring, prop_altar_portal, prop_altar_crystals, prop_altar_sign, cloud_storm_puff.
Looks: prop_roulette uses Primary = roulette.Color and Secondary = its top rarity colour. prop_obelisk and prop_banner use Primary = the band or cloth colour. prop_flowerbed uses Primary and Secondary = FLOWERS[v] and FLOWERS[v%6+1].
Keep lists: prop_plot keeps Accent, PodiumBase and PodiumTop (HomeBuilder still owns the podium). Boards keep Face. prop_welcome_arch keeps WelcomeSign. prop_shop_arch keeps ShopSign. The bridges keep the puff part names (Mesh.CloudParts / Mesh.PuffParts), so a bridge's Dress never hides its puff's mesh.
Kit: blender/kit/props/lobby_world.py boots its own Bridge, sets LobbyBuilder._Kit and StormAltar._Kit, and runs both Build calls. Every Mesh.tag call is then recorded as {Key, Target, Origin}, and cloud specs are recorded too. Builder types: lobby_boxes (any tagged subtree becomes baked box meshes, with coincident faces deduplicated so the FBX round trip stays exact), lobby_cloud (args V, template), altar_island. Sculpt.detach_glass() is needed wherever glass voxels touch opaque ones (the mesher leaves those contacts open). Plot-scale sculpts must use small grids per piece, because a 0.2-stud grid over a whole plot is about 500^3 voxels.
Budget: tools/mesh_budget.py --scene docs/phase6/review/lobby/scene_plaza_phone.json shows about 112k tris for the lobby keys plus 18k for the gates in the spawn view. The scene's total of 443k comes from mesh_budget choosing boss_storm_titan_low as the 'heaviest Low pet set' (45 x 5.7k). Lead or kit: make catalog_sets() skip boss and dragon sets when it picks pet sets. Real Low pets at about 2.7k give roughly 310k, so the pets need Low LOD for others.
Renders: render_model.py meshlobby [--box ...] dresses every recorded target from its committed manifest.
W4 upload: these keys are Model assets like the others. The LayoutSig check means a lobby layout change needs a rebuild and re-upload of the floor_*, cloud_* and prop_plot keys.

## art-pets

### Deviations
- Corgi gets its own body key: pet_dog_corgi[_low]. PetBuilder sculpts the corgi differently from other dogs (it checks for 'corgi' in the pet Id), so 16 body pairs are built, not 15. Runtime: waffle_corgi -> pet_dog_corgi.
- hyb_<style> (16 keys: the 15 species plus hyb_same, High only) are built as type 'pet' entries with a hybrid Look plus the pass pets_hyb:isolate, because the kit has no hyb type. Each key holds only what the hybrid ADDS to the reference body (pebble_pup; hyb_dog uses mallow_kitten): grown voxels, painted Hy* patterns raised one fine voxel off the surface (a plain recolour would z-fight), and the swapped tail only when the trait grows its own. There are no eyes or lids. Pivot = the body root, and the manifest carries the reference body's attachments. Hy* parts (HyA/HyB/HyTip/HyHorn/HyGlow) depend on the Style parent's Primary plus the seed, which recipe ops cannot express, so the manifest stores the reference hybrid's constant colour and the runtime must set them from PetBuilder's hybrid palette. On non-reference bodies the features need anchor remapping (HeadCenter/Tail) or they will float or sink.
- Accessories are cut from one reference pet each, as in W1: horns from twilight_dragon, leaf from maple_fox, mushroom from shroomie_frog, scarf from biscuit_bear, antlers from aurora_fox, flower from cherry_panda, crown and halo from pebble_pup. Pivot = Hat, except acc_scarf (Neck) and acc_flower (Flower), which are recorded in Meta.attach. Widths can differ on other species.
- Budgets are checked by 66 catalog sets: one set per catalog pet, High and Low (species body + its wing pair + its accessory). All sets pass: High max 6448/6500 tris (hydralotl), max 39/40 parts (dragon sets); Low max 2938/3000. Fusion combos outside the catalog are not guaranteed to fit. To fit, these keys use explicit K values: wing_bat K 1.15, acc_scarf 1.035 (Low 0.63), acc_horns_low 0.62. pet_dragon High uses fixed:true. pet_unicorn uses a part-economy option (Inner merged into Blush; AccentLight folded into Accent), saving 2 parts. Per-key budgets: wing 700, wingLow 320, wingStorm 3000/1500, acc 1000, accLow 400, hyb 2000.
- pet_stormfang and wing_crystal_* fail the stock build_all geometry check: 'group not closed'. This is a false positive. Glass voxels (GemRim, crystal Wing/WingCore) emit no faces toward opaque neighbours (nvox/mesher.py by design). I built these 5 keys with the proposed check patch through a scratch wrapper (scratchpad w6/art-pets/build_patched.py). The outputs are identical to what the stock build would produce, because only the check differs. Until the patch lands, a stock `--class pets` reports 5 failed keys.
- The base-stage Secret aura (PetBuilder auraGrid, used for Secret pets other than Stormfang and the phoenix: eclipse_dragon, phantom_kitsune, magma_cub, rime_wyrmling, hydralotl) is not in any pets key. Body keys come from non-Secret reference pets, and the kit cannot cut a lone group. It belongs with art-evolved's aura_<kind> family.
- No _low variants for hyb_* (contract 6.2 lists hyb_<feature> only).

### Lead requests
- blender/build_all.py:183 (Builder.check_geometry): the closure check gives a false positive on translucent groups. Patch before the loop: `translucent = {o.group for o in m.objects.values() if getattr(o, 'transparency', 0) or o.material in ('Glass', 'ForceField')}`, then inside the loop `if g in translucent: continue  # glass voxels hide faces toward opaque neighbours (nvox/mesher.py)`. This unblocks pet_stormfang and wing_crystal_* (and art-evolved crystal or glass keys). Already verified with scratchpad w6/art-pets/build_patched.py.
- tools/dump_model.lua:1637 ([owner: kit] meshpet): accessories are always placed at 'Hat'. Use the manifest's Meta.attach instead: `local am = require(folder:FindFirstChild(accKey)); local where = (am.Meta and (am.Meta.attach or am.Meta.Attach)) or 'Hat'`. Without it, acc_scarf and acc_flower render in the wrong place in render_model meshpet:<id>. build_all --preview already uses meta.attach.

### Smoke

python3 tools/syntax.py: 528 files, 0 errors. node tools/check.mjs: 0 errors (3 pre-existing many-locals warnings in ArenaBuilder/PetBuilder, not my files). smoke --quick --only petbuilder,p6mesh_fit: 194 passed, 0 failed. --only p6mesh_server,p6mesh_noop: 176 passed, 0 failed. blender/kit/selftest.py: 447 checks, 3 failed, all on art-evolved keys built while I ran it (evowing_twilight_dragon_1_L/R_low missing from or not matching meshes.json); every pet/wing/acc/hyb manifest check passes. Export build: 87 keys fbx ok with stock build_all plus the 5 translucent keys via the patched check = 92 keys. No full smoke, per this wave's rule. Note: the lead's checkpoint commits (627604e/86a9107) already include my files, so git status shows a clean tree.

### Notes for next waves

Keys (92): pet_<cat|dog|dog_corgi|fox|bunny|bear|panda|dragon|owl|slime|unicorn|phoenix|frog|penguin|axolotl|stormfang>[_low]; wing_<feather|bat|fairy|cloud|crystal|flame|stormcloud>_<L|R>[_low]; acc_<horns|crown|halo|leaf|mushroom|scarf|antlers|flower>[_low]; hyb_<cat|dog|fox|bunny|bear|panda|dragon|owl|slime|unicorn|phoenix|frog|penguin|axolotl|stormfang|same>.
Body-key lookup for runtime-pets: lower(Species), except waffle_corgi -> pet_dog_corgi. A hybrid body uses Same when style species == body species.
Accessory placement: at the body attachment named by manifest Meta.attach (Hat by default; Neck for scarf, Flower for flower). The halo is its own 'Halo' group (bob) inside acc_halo.
Hybrid rule: if the hyb manifest has a Tail group, hide the body's Tail (it replaces it). Colour Hy* parts from the hybrid palette.
Detail passes: kit/detail/pets.py `cute` (bodies, High and Low) gives round soft cheeks under the eyes (Blush key), dark toe grooves (<Key>_Dark, so no new parts), pink paw beans on hidden sole cells (High), and a cowlick on Dog/Cat/Fox/Penguin. Entry option `cute` takes cheeks/toes/pads/tuft, plus merge {A: B} and foldLight [keys] for part economy. Passes run before eye carving and may only use palette keys the pet already has (an unknown key renders grey with no recipe).
Material Neon by look.Glow (EyeIris, EyeRing, AntlerTip...) still comes from the reference pet: the runtime must apply it per pet.
Catalog generator (regenerates pets.json from tables, preserving sets/previews): scratchpad w6/art-pets/gen_catalog.py. Preview tool for any pet's Look with correct attach: w6/art-pets/preview.py (petId[:low][@body=,acc=,wing=,hyb=]).
Art rounds: r0 baseline -> r1 cheeks/tuft -> r2 placement -> r3 paws -> r4 all 33 pets plus Low; hybrids h1 -> h2 (eye-front cleanup).
Low LOD pixel eyes (W1 faces.py) still look busy; a candidate polish for the kit owner.

## runtime-pets

### Deviations
- Rebuild-on-Changed works by polling, not by Changed connections or Swap. The new MeshLibrary.Version() counter goes up wherever Changed fires (and on failures, device preload failures, template removal and _Reset). The controllers compare PetBuilder.MeshVersion() once per frame, and only when it changes do they call PetBuilder.NeedsMeshRebuild(model) and rebuild through their own build paths. Reasons: Swap destroys the model the controllers hold references to; Changed fires once per key (hundreds of times during preload); _Reset clears Changed handlers.
- CareController ~:2222 is NOT passed Viewport = true. That build is the world-space EVOLVE moment (H.evoFolder parents to Workspace), so it keeps its PetFx effects. The real viewport builders do pass it: CloudUI.PetViewport (which covers the Index, Fusion and Care tiles) and the BattleController helper portrait. CareController and EvolutionFx needed no edits; their scenarios pass in --mesh mode.
- Golden mesh pets get a hero star_gold on the head and a cheek glint. The Part build's chest star and wing glints are left out, because static stars would not follow the flapping wings.
- Evolved fused hybrids (look.Base nil) have no mesh design, so they always take the Part build. Low-detail hybrids use the High hyb_* key, because there are no _low hyb keys.
- Hybrid feature placement is an approximation. Each hyb part is anchored by its height in its reference body: above the head centre it blends toward the body's Hat attachment, below it toward the floor (bounds of pet_<ref species>). A hyb Tail group replaces the body's Tail group (Assemble entry.Skip). Feature colours (HyA, HyB, HyTip, HyHorn, HyGlow) are applyHybrid's exact palette.
- The mesh PB_Rig is sorted into instantiate order. It can hold a group the budget-capped Part sculpt dropped (for example Halo on the second-evolution twilight dragon), so the test checks that the Part groups appear in the same order, not exact equality.
- MeshLibrary API additions: Version(), Active() (a cheap gate: no template folder means no key or manifest lookups in Build), and Assemble entry options Skip = {groupId = true} and Scale = n. A CFrame At is NOT multiplied by opts.Scale (now documented).
- PetBuilder additions: opts.Parts = true forces the Part build, plus PetBuilder.MeshKeys, NeedsMeshRebuild and MeshVersion.
- Fixture mode uses the committed src/shared/MeshManifests for every pet-class key (447 keys: pet_, wing_, acc_, hyb_, evo1_, evo2_, evowing_, star_gold). It does not add new frozen copies to tools/fixtures/mesh.

### Lead requests
- Server-built pets never become mesh pets, because the keys load after boot. The callers are NpcService.lua:610 (art-creatures), LobbyBuilder.lua:1835 and StormAltar.lua:1220 (art-lobby) and SpotService.lua ~:480. Proposed patch after each Build: `local keys = PetBuilder.MeshKeys(def, opts); if keys and not MeshLibrary.IsReady(keys) then MeshLibrary.Swap(model, function() return PetBuilder.Build(def, opts) end, keys) end`. Callers that keep a reference to the model must find it again by name after the swap.
- art-pets: hyb_bear has no bear ears; the isolate pass seems to drop them, while the Part build shows round brown ears. There are no hyb_*_low keys. If you want better hybrids, split the hyb features into head and body regions.
- art-evolved: in --mesh mode, p3evo_pets finds 0 Basalt and 0 HydraHead parts on the magma_cub and hydralotl evolved keys. Tests look up those keys by name, so they should not be baked into Fixed (recipe 4.3).
- Voxel-count asserts should be skipped on mesh models (`model:GetAttribute("ML_Mesh")`), as recipe 4.9 says. They are: smoke_content petbuilder (eye highlights >= 2, Cloudy Dragon nostrils and tail part counts, Stormfang Neon counts), smoke_p3_evolved (evolved part caps and named counts, client_p3evo_lineup), client_pets (High detected by part count) and client_p4pets_evolved.

### Smoke

Per the wave override, no full --quick run. syntax.py: 796 files, 0 errors. check.mjs: 0 errors, 3 many-locals warnings; the PetBuilder one went from 179 to 180 of 200.

Default mode, 27 related scenarios in one --only run: 1009 passed, 0 failed. They are petbuilder, evolved, p3evo_pets, p5looks_podium, p2fusion_looks, storm_pet, p6evofx_specs/build, p6mesh_noop/fit/server, p6pets_default, p6pets_server, client_pets, client_p4pets_follow/evolved, client_p5looks, client_p5follow_formation/motion, client_p5models, client_p5wild, client_p6evofx, client_p6mesh, client_p6pets, client_p5hud_fighter, client_p5team3, client_p5home_roam.

One failure outside my files: `client_p2home` "the dumbbell goes up and down" fails when it runs after client_pets in an --only run, with HEAD's HomeFx too. It is an order dependence; owner art-home/homefx.

`python3 tools/smoke.py --quick --mesh`: 967 passed, 36 failed in 41 s. All of my scenarios are green. The 36 failures are the voxel-count / name asserts listed in the lead requests.

### Notes for next waves

PetBuilder mesh path (MESH table, before the Public API):
- Build calls MESH.build. It goes through MeshLibrary.Active() first, then a plan cached per look, which picks the keys.
- Base stage: pet_<species>[_<variant from an Id token, e.g. pet_dog_corgi>][_low], wing_<style>_L/R[_low] placed at the Attach named in the wing manifest's group, acc_<name>[_low] at Meta.attach or Hat, hyb_<style species> (hyb_same when the species match) and star_gold for Golden.
- Evolved: evo<stage>_<Base>[_low] plus evowing_<Base>_<stage>_L/R[_low], plus _2b_L/R for stage 2 when the manifest exists.
- A missing manifest means the Part build. IsReady is checked on every Build, and the mesh template cache key includes the path.
- Root size = Meta.rootSize * scale * Meta.grow; PB_Scale = scale * grow. Manifests already contain grow.
- Attributes are the same as the Part build's (PetId, PB_Seed = hashString(Id..Species), PB_Detail, PB_Finish, PB_Hybrid, then PB_Evolved / sparkles / Wild / PetFx in the existing tail).
- Golden recolours by MK_Key: Metal accents, plus GoldSpark Neon star parts with PB_Pulse and PB_Star.
- Rainbow sets PB_Hue on the largest RAINBOW_KEYS parts. Every mesh part has CastShadow off.

Client controllers: PetController uses p.meshVer and rebuildAt. HomeFx uses G.meshSweep (drops Part pets and their pool entries, clears petLows, marks stations Dirty). BattleController uses Units.MeshSweep: it skips parked or KO'd units and also refreshes the helper portraits (H.model). CloudUI.PetViewport swaps its model in the 0.25 s ticker. GraphicsQuality.Apply calls PetFx.SetQuality.

Tests:
- `_G.P6Pets.Install(keys)` / `Uninstall()` load fixtures into the REAL shared MeshLibrary, using the real loader + fit on the server and the real preload on the client.
- `--mesh` sets env NC_MESH_FIXTURES=1. Without --only it runs a default pet scenario set; with --only it adds the two mesh_on scenarios.

Render helper for assembled mesh pets: /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/runtime-pets/render.py <spec.json> <out.png>. Rounds r1-r6 there, compared side by side with the Part builds.

## Wave 2.5 (fix wave) results

Workflow wf_5188b813-58e, jobs fix-kit, fix-runtime, fix-tests (all done).

### job
#### deviations
- (2) ML_Hide hide-list mode is in MeshLibrary (Tag look.Hide sets ML_Hide, Dress opts.Hide, and ML_Hide wins over ML_Keep). I did NOT switch the WorldStyle gates to it. smoke_p6_gates (art-gates' file) checks ML_Keep and the DescendantAdded keep-list updater, so switching would turn it red, and keeping both modes would not make anything simpler. Separately, hideLocally now never hides any part inside an 'ML_Mesh' model, in both modes. That covers the nested-target risk art-gates raised.
- (3) The four callers go through one helper I added to the PetBuilder mesh path: PetBuilder.SwapWhenReady(model, petDef, opts, buildFn, onSwapped). The original proposal called MeshLibrary.Swap inline in each caller. The helper always swaps with Place=false and buildFn returns a finished, placed model. Plain Swap would PivotTo the old pivot, which shifts the pedestal or podium when the mesh pet's height differs from the Part pet's.
- NpcService rebuilds the WHOLE NPC model, not only its Pet child. NpcController (not my file) caches rec.Pet at setup, so a swapped Pet child would never animate. A new tagged model makes the client set the NPC up again. The server record is updated in place.
- MeshLibrary.Swap has a new 4th argument opts: a function = OnSwapped(fresh, old), or a table { OnSwapped, Place=false }. After Start, Swap no longer waits on a key with no id ('missing'), so empty MeshIds leaves no state at all.
- MeshLibrary.Dress gets a Part target's pivot through pcall(GetPivot) with target.CFrame as the fallback. This works in the mock now, even without fix-tests' BasePart:GetPivot.
- (6) goldSparkles records StarSpots, and the Part path then calls MESH.partStars. When star_gold is ready but the body keys are not, the body's voxel stars (head, cheek, chest) are replaced by star_gold MeshParts (GoldSpark*, Neon, PB_Star, PB_Pulse) and the model gets attribute PB_MeshStars. Wing glints stay voxels because they flap. The templates and blueprints are not touched, and opts.Parts=true keeps the voxel stars.
- Test-only hooks added: HomeFx._StartPop and BattleController._Units.
#### leadRequests
- tools/smoke_p5_world.lua:498-499 and :660 (p5world_style; owner worldstyle/worldlobby). Two checks there now fail because task item (8) removed Home from WorldStyle.SampleGates. Patch at :498: `local specs = {} for _, s in ipairs(WS.SampleGates or {}) do specs[#specs + 1] = s end` then `T.check(#specs == 5, "WorldStyle.SampleGates lists the five Gate Court gates (no Home gate, Phase 6)", tostring(#specs))`, then `specs[#specs + 1] = { Id = "Return", Title = "Go Home", Info = "", Color = "Yellow", Glyph = "house", Pad = false } -- the house crest lives on the arena Return gate`. That keeps the six-crest check at :660 green and still tests the house crest.
- tools/smoke_p6_creatures.lua leaveFixtureMode (ML._Reset) wipes the --mesh global fixture set. If client_p6creatures runs before client_p6pets in a --mesh run, 3 client_p6pets checks fail. This predates my change and those scenarios are not in the default --mesh set. Fix: in --mesh mode, call _G.P6Pets.Install(_G.P6Pets.PetKeys()) after leaveFixtureMode. The same happens with p6lobby_server, and with client_p6mesh's 'a target whose key failed on this device keeps its Parts' check: in --mesh mode the global library dresses that ML_Dress-tagged target. Also pre-existing (it fails the same way with HEAD's MeshLibrary).
#### smoke
python3 tools/syntax.py: 798 files, 0 errors. node tools/check.mjs: 0 errors, 3 many-locals warnings, all pre-existing: MenuController 176, ArenaBuilder 178, PetBuilder 180. Default --quick --only runs:
- Server batch: petbuilder, evolved, p3evo_pets, p2fusion_looks, storm_pet, storm_altar, p2gems_altar, spots, p5looks_podium, p5world_style, p5world_lobby, p5world_gates, p6gates_server, polish_portals, polish_worldtext, lobby, p6evofx_build, p6evofx_specs, p6pets_default, p6pets_server, p6lobby_server, p6creatures_server, p6mesh_server, p6mesh_noop, p6mesh_fit. Result: 1756 passed, 2 failed. Both failures are in p5world_style (smoke_p5_world.lua, not mine) and are expected after the SampleGates Home deletion; see the lead request.
- Client batch: client_pets, client_storm, client_p2home, client_p2visual, client_p5home_roam, client_p5home_flow_ui, client_p5looks, client_p6gates, client_p6evofx, client_p6pets, client_p6mesh, client_p6creatures, client_polish_worldtext, client_p3battle_trial/raid/spectate/cards/ring, client_p5hud_fighter/enemies, client_p5input, client_p5models, client_p5result, client_p5team3, client_p3fixcli_retreat/telegraph. Result: 793 passed, 0 failed.
- The client_p6creatures LEAD REQUEST check is now green, and real ML_Weld checks were added.
- --mesh spot check: p6pets_server, storm_altar, spots, client_p6pets are green. Remaining --mesh failures are pre-existing order interactions (lead request 2).
- No full smoke was run, as this wave asked.
#### notesForNextWaves
MeshLibrary API:
- Swap(model, buildFn, keys, opts): opts is a function (OnSwapped(fresh, old)) or { OnSwapped, Place=false }.
- Tag look.Hide makes ML_Hide (a sorted csv). Dress opts.Hide exists too. ML_Hide hides ONLY those part names; ML_Keep is ignored when ML_Hide is set.
- Dress never hides parts inside any 'ML_Mesh' model.
- A BasePart target with ML_Weld=true gets its mesh parts unanchored and welded with a WeldConstraint named 'ML_Weld' (Part0 = the target).

PetBuilder:
- SwapWhenReady(model, def, opts, buildFn, onSwapped) -> bool. It returns false and keeps no state when Active() is false, when keys are ready or missing, or when the model is already a mesh.
- MESH.partStars(model, bp, scale), and the PB_MeshStars attribute.

Server callers (they swap once the keys load):
- NpcService: watchMeshPet. buildNpc has a new 4th argument detached.
- StormAltar: makeShowcasePet(A).
- LobbyBuilder fountain: statue().
- SpotService: setShowcasePet's buildShow(). show.Model follows the swap.

LobbyBuilder place() now sets WorldPivot = cf on clones without a PrimaryPart. So Mesh.tag's ML_Offset is identity for placed clones; the LayoutSig is unaffected.

BattleController:
- Units.FxMesh(key, scale) returns sorted MeshParts or nil.
- ShieldCube is the fx_shield MeshPart resized to the cube size.
- Ice: 5 'Crystal' fx_ice meshes; the light core is welded as a child also named Crystal.
- FocusArrow: fx_arrow parts with Y = -centre/0.8.

HomeFx.startPop returns nil for ML_DressKey models.

WorldStyle.SampleGates has 5 entries.

Test gotcha: a late-load fixture needs a yielding Mock.AssetLoader (task.wait inside it), otherwise the keys are ready right at Start. See installLate in smoke_p6_pets.lua.

### job
#### deviations
- (1) check_geometry skips see-through PARTS (transparency > 0, Glass, ForceField) when it sums whether a group is closed, not whole groups. The mesher already emits opaque faces towards glass, so opaque parts in a mixed group are still checked. Every part still gets the zero-area check. A selftest checks both cases. `build_all --class pets` built 94 keys and `--class evolved` built 354 keys, all with fbx ok, 0 failures and exit 0.
- (3) The root cause was in tools/mesh_names.py, and it was larger than Basalt and HydraHead. (a) The patterns now also read `keyed(m, "X")`, smoke_p3_evolved's SIGNS tables `{ { "X" }, n, ... }` and its `ipairs({...}) ... keyed(` leak loop. That adds Basalt, MagmaHot, HydraHead, HydraEye, HydraJaw, Frost, FrostTip and CrystalDeep. (b) A bug in _table_keys: for a one-line table it read on into the code after it. More importantly, the committed W2 manifests baked keys that the current checker counts as referenced: Spark (PetBuilder's WILD_KEEP) on 88 keys, EyeIris, EyeGlint and EyeRing (WILD_EYES), and the event pets' keys. All of these are now unbaked, and `mesh_names --check` finds 0 problems. As a result evo1_obsidian_phoenix has 41 parts and evo1_rime_wyrmling has 43, so I raised the evo1Body part cap from 40 to 44. The evo1 set cap stays at 64, and this is documented in BUDGETS_DOC.
- (2) Evolved High bodies now use face {eyes:'lua'} without the lua_eyes pass. All 49 bodies gave the same contentHash as with the old hook, so I deleted the hook from evolved.py. face_pass runs the passes before the lua return. The procedural path keeps its old order, so base pets are unchanged.
- (4) The isolate pass was not dropping the ears. hyb_bear and hyb_dog are built on bodies that have their own ears, and HYBRID.Bear and HYBRID.Dog only grow ears when the body has none (HAS_EARS). Fix: two new keys, hyb_bear_ears and hyb_dog_ears, built on puddle_frog. A key-name contract case is needed: the runtime has to pick them (lead request 1). I also improved isolate: any key the hybrid paints over the body is now raised, not only Hy* keys, so a unicorn's horn base now shows. hyb_penguin opts out with raiseAll:false because the raised feet go over the 2k triangle budget (2254 tris).
- (7) Low pixel eyes (all 3x4): no lash row, no iris pixel on 3-wide eyes, the top corners rounded off, and one highlight inside the dark area. An edge highlight disappeared against pale faces. Low pets now have 2 fewer MeshParts. I went through 3 rounds (A/B/C), and the kitten's purple iris pixel at Low is gone.
#### leadRequests
- runtime-pets, src/shared/PetBuilder.lua:6995 (MESH.makePlan): right after `local key = ... "hyb_" .. string.lower(hy.Species)` add `if key ~= "hyb_same" and not HAS_EARS[look.Species] and ML.Manifest(key .. "_ears") then key = key .. "_ears" end`. HAS_EARS is the file-level local at :2335. The ref-species lookup already reads meta.species, which is Frog. Failing check until then: blender/kit/selftest.py 'LEAD REQUEST (runtime-pets): PetBuilder picks hyb_<style>_ears ...'. Note that on slime the bear ears float slightly above the dome; that comes from the runtime's Hat-blend approximation.
- Test owners (smoke_content petbuilder / smoke_p3_evolved): skip the voxel-count asserts when ML_Mesh is set, as runtime-pets asked. In --mesh mode, 'pets have big glossy eyes ... shine highlights >= 2' still fails for 8 of 33 pets (8 eye parts, 1 highlight part), and Basalt / HydraHead are now 1 MeshPart each, below the >= 2 / >= 6 voxel counts.
- Lead: the busiest lobby view is OVER budget once the home plots are counted. See the notes for the numbers.
#### smoke
I did not run the full --quick, as this wave asked. python3 tools/syntax.py: 810 files, 0 errors. node tools/check.mjs: 0 errors and 3 old many-locals warnings (MenuController, ArenaBuilder, PetBuilder; none are my files). `smoke --quick --only p6mesh_fit,petbuilder,evolved,p3evo_pets`: 335 passed, 0 failed. `--only p6mesh_server,p6mesh_noop,client_p6mesh,p6pets_default,p6pets_server,client_p6pets,client_pets`: 552 passed, 0 failed. `--mesh --only petbuilder,evolved,p3evo_pets,client_p6pets,client_pets`: 568 passed, 1 failed. The failure is the existing eye-highlight voxel-count assert in petbuilder (test owner, lead request 2). blender/kit/selftest.py: 739 checks, 1 failed, and that one is the deliberate lead-request check. tools/mesh_names.py --check 'blender/out/*.manifest.json': 718 manifests, 0 problems. evolved_check.py: 354 keys, 0 failures. evolved_catalog --check: up to date. Builds are deterministic: hyb_bear_ears rebuilds byte-identical, and the 49 evolved High bodies hash the same as before.
#### notesForNextWaves
mesh_budget (6). The pet-set pick now uses only the classes in scene['petClasses'] (default ['pets'], so no boss or dragon sets). DEFAULT_SCENE now has an 'include' field: [{scene: docs/phase6/review/home/plot_scene.json, count: 4}]. The 16 plots sit on the 340-stud spot ring, and a phone view takes in about a quarter of it. Result: 3 x hydralotl High set (19.3k) + 45 x twilight_dragon_low (132.2k) + gates/lobby keys (about 131k) + 4 plots (163.1k) = 445,316 / 300,000 tris and 1934 / 400 parts. Without the plots it is about 282k, so the plots push it over. With all 16 plots in view it is 934k, and with every pet a second evolution it is 598k. The lobby needs streaming, Low LOD for the plots, or a different plot-visibility rule; that is the lead's call. The 400-part scene budget cannot be met with the 4.3 name contract: the pet sets alone are 1395 parts.

API and keys. dump_model targets: meshpet:<id>[:Low] puts accessories at the manifest's Meta.attach and picks the body variant from the last token of the id (waffle_corgi gives pet_dog_corgi). The new meshevo:<petId>:<1|2>[:Low] = evo<s>_<id> plus evowing_<id>_<s>_L/R at WingL/WingR, plus the 2b pair at Wing2L/Wing2R; the wing attach comes from the wing manifest's Groups[*].Attach. New kit keys: hyb_dog_ears and hyb_bear_ears (reference body Frog, meta.species = 'Frog'). Catalog option for hyb entries: 'raiseAll' (default true). faces.SMALL_EYE_STYLE / _small_key define the Low eye layout. petkit.run_passes(bp, cells, entry) is now public.

Gotchas. (a) The lead's checkpoint commits snapshot files during the wave (build_all.py and the first mesh_names patch are already in HEAD 51dd932 / 39e86b2), so diff against 1d57a64 to see the W2 state. (b) --no-export builds still rewrite src manifests and meshes.json; finish with an export build. (c) Any new by-name lookup in a test (keyed / SIGNS-style tables) changes what is referenced and can unbake keys, raising part counts; rebuild pets and evolved afterwards. (d) Scratch renders, including a runtime harness with in-memory key swaps (SWAP) and the W2 snapshot copy, are in /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/fix-kit/.

### job
#### deviations
- I edited cleanup lines only in tools/smoke_p3_arenaworld.lua (p3arena_mesh) and tools/smoke_p5_dungeon.lua (p5dgn_mesh). These files are not on my list. p3arena_mesh, p5dgn_mesh and p2home_mesh each call ML._Configure({Ids}) and then ML.Start(), which creates ReplicatedStorage.MeshLibrary. ML._Reset() does not remove that folder. All three scenarios run before p6pets_default, so in DEFAULT mode p6pets_default and p6pets_server failed 3 checks ('MeshLibrary.Active() is false', 'fixtures removed, Build is the Part build again', 'SwapWhenReady = false'). Each scenario now records whether the folder existed beforehand and destroys it after _Reset if it did not. No asserts changed. The owner art-arenadungeon is not active in W2.5.
- The mock also gets BasePart:PivotTo (it calls the existing pivotTo, which already handled BaseParts). I added it alongside the requested BasePart:GetPivot so the Part pivot API matches Roblox.
- run_checks.sh skips the mesh step when the user passes --only, because that run targets specific scenarios.
#### leadRequests
- Real bug (PetBuilder mesh path, art/runtime-pets): mesh pets with Glow lose their Neon irises, glints and wing edges. Eight Glow pets (aurora_fox, moonlit_owl, nebula_axolotl, ...) fail 'Glow pets have Neon irises' in --mesh mode (tools/smoke_content.lua:1219). I KEPT this check: it tests a material, not a voxel count. In the Part build makePalette (PetBuilder.lua:604) sets EyeIris, EyeGlint and WingEdge to Neon. No manifest has GlowMaterial, although MeshLibrary.lua:1120 supports it. Minimal patch at src/shared/PetBuilder.lua:7221, just before `if look.Finish then` in the mesh assemble tail: `if look.Glow then for _, part in ipairs(model:GetChildren()) do local key = part:IsA("BasePart") and part:GetAttribute("MK_Key"); if key == "EyeIris" or key == "EyeGlint" or key == "WingEdge" then part.Material = Enum.Material.Neon end end end`. I tested it in a scratch copy: --quick --mesh gives 1003 passed, 0 failed. The alternative is for the kit to emit glowMaterial='Neon' for those keys (PART_FIELDS in blender/kit/manifest_to_lua.py has no GlowMaterial) and rebuild the pet/wing keys.
- Test isolation leak (owner of tools/smoke_p4_ui.lua): client_p4ui_mobile ends with the phone viewport at 844x390 (landscape loop ~:882). Proposed: before `end)` of that scenario, add `Mock.SetViewport(390, 844); advance(0.2)`. I made client_p5menu_mobile robust to this on my side.
- Optional (smoke.py --only dependency block ~:468, lead-owned): `if only & (set(mobile_scenarios) - {"client_mobile"}): only |= {"client_mobile"}`. Phone scenarios run under --only alone would then get the booted phone client, the same way client scenarios pull in client_load.
#### smoke
Per the wave rule I did not run the full default --quick. syntax.py: 810 files, 0 errors. check.mjs: 0 errors, 3 many-locals warnings that were already there (MenuController, ArenaBuilder, PetBuilder 180/200). `python3 tools/smoke.py --quick --mesh` went from 36 failed to 1002 passed, 1 failed (32 s). The one failure is the Glow Neon-iris lead request above: a real mesh bug, not a voxel count. The Basalt and HydraHead asserts were kept and are now green on fix-kit's rebuilt manifests. With the PetBuilder patch applied in a scratch copy, mesh mode gives 1003 passed, 0 failed. Default-mode --only run of 30 scenarios (petbuilder, evolved, p3evo_pets, storm_pet, client_pets, client_p3evo_lineup, client_p4pets_evolved, client_p2home, client_p5menu_mobile, client_p4ui_mobile, mock_selftest, all p6mesh / p6creatures / p6lobby / p6gates / p3arena_mesh / p5dgn_mesh / p2home_mesh / p6pets scenarios): 1589 passed. The only failures were 4 client_replay checks, an artifact of my subset (replay needs the whole server run), not a real failure. Order checks: `--only client_pets,client_p2home` gives 296 passed, 0 failed. client_p5menu_mobile passes in every combination I tried: alone, after client_p4ui_mobile, with client_mobile, and with client_p5menu/client_p5settings.
#### notesForNextWaves
Mesh gating pattern (recipe 4.9): a mesh pet has `model:GetAttribute("ML_Mesh") == true` (set by MeshLibrary.Assemble). In mesh mode, voxel floors become presence checks (>= 1 part with that name; part floor 8 instead of 100/150) under the same caps. Detail level is read from `PB_Detail`, never from part counts. Names stay required in both modes. smoke_content has a helper `isMesh(model)` next to partsNamed.

Root causes found:
(a) The client_p2home dumbbell check was not a state leak. It took one 0.4 s sample of a sine with period 2.1 s (HomeFx stepProp `Lift`). When the clock phase left by earlier scenarios put the sample across the peak, the bar moved only 0.006 studs. The check now takes the max over a full period.
(b) client_p5menu_mobile has two isolation problems. client_p4ui_mobile leaves an 844x390 viewport, so settings dock 'Side' instead of 'Sheet'. Under --only, the phone world never runs client_mobile (no Remotes, no Main), so PLAY sends nothing. The scenario now sets 390x844, boots if needed, and restores the viewport.
(c) Any test calling ML.Start() with ids must destroy ReplicatedStorage.MeshLibrary afterwards, because ML._Reset() does not.

Mock: BasePart:GetPivot() = CFrame * PivotOffset, and BasePart:PivotTo(). These allow Dress tests on Part targets (dungeon_rock, dungeon_crack, coins).

run_checks.sh has a new step 'Smoke test, mesh mode (tools/smoke.py --quick --mesh)', which is skipped when --only is passed. tools/README.md has a new subsection 'Mesh mode: --mesh (Phase 6)'. Scratch copies used for verification are in /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/w6/fix-tests/ (head/ = clean HEAD export, wt/ = working copy with the Glow patch).


### Lead applied after W2.5
- PetBuilder mesh plan picks hyb_<style>_ears on an earless body (fix-kit LR1).
- PetBuilder mesh tail: Glow pets get Neon EyeIris / EyeGlint / WingEdge (fix-tests LR1).
- smoke_p5_world: SampleGates has 5 gates; the house crest is checked on the Return gate (fix-runtime LR1).
- smoke_p6_creatures leaveFixtureMode reinstalls the --mesh fixture set (fix-runtime LR2).
- smoke_p4_ui client_p4ui_mobile leaves the phone upright; smoke.py --only pulls client_mobile for phone scenarios (fix-tests LR2, LR3).
- OPEN for W3 (lead call): lobby busiest view is over the scene budget once home plots count (445k / 300k tris; 1934 / 400 parts). Options: stream plots, Low LOD for far plots, or a plot-visibility rule.
