# Phase 6: uploading the Blender models (the checklist)

This is the one checklist for putting the Blender models of Nimbus Climb into the live game. Two people use it:

* **You, the owner** (Windows, Roblox Studio, Rojo 7.7.1). Your steps are marked **OWNER**.
* **The upload session**: a NEW Claude session that can see your Open Cloud key. Its steps are marked **CLAUDE**.

Until this is done, the game runs exactly like today: `src/shared/MeshIds.lua` is empty (`return {}`), so every pet,
gate and building uses its old Part model (the bright voxel look). Each model switches to its Blender mesh by itself
as soon as its id is in `MeshIds.lua`. A model that fails to load just keeps its Part model. Nothing breaks.

Rules (they win over everything below):

1. **Never paste the API key into the chat.** It lives only in the environment settings (step 1). Claude never
   prints it; the tool shows it as `<hidden>`.
2. **No real upload without your OK in the chat.** The first real upload is `cal_axes` (step 3), and Claude asks you
   before each new step. Uploads go to your Roblox account.
3. **Never fake an id.** Every id in `MeshIds.lua` / `TextureIds.lua` comes from `tools/upload_assets.py`.
4. **Do not go around moderation.** A model Roblox rejects stays a Part model (step 8a).

The technical background is in `docs/phase6/recipe.md` (4.7 and section 6) and `docs/phase6/research.md`.

---

## 1. OWNER: make the key (once, about 10 minutes)

1. **Who owns the game?** Open create.roblox.com -> **Creations**. If the experience is under your own name, the
   owner is a **user**. If it is under a group, the owner is a **group**. Write down the owner's **id**: your user id
   is the number in your profile link (`roblox.com/users/<id>/profile`); a group id is the number in the group link.
   The models MUST be uploaded by the same owner as the game, or Roblox refuses to load them in the game
   (they would all stay Part models).
2. **Make the Open Cloud API key.** create.roblox.com -> **Open Cloud** -> **API Keys** -> **Create API Key**
   (for a group game: make it on the group's Open Cloud page instead).
   * Name: `Nimbus Climb uploads`.
   * **Access Permissions**: add the API system **Assets** and tick **Read** and **Write**
     (these are the scopes `asset:read` and `asset:write`; `tools/upload_assets.py` only calls
     `POST /assets/v1/assets`, `PATCH /assets/v1/assets/{id}`, `GET /assets/v1/assets/{id}` and
     `GET /assets/v1/operations/{id}`). Nothing else is needed.
   * **Security / Accepted IP Addresses**: the Claude cloud session has no fixed address, so add `0.0.0.0/0`
     if the page asks for one.
   * Expiration: your choice. A key that is not used for 60 days stops working by itself.
   * Click **Save & Generate Key**, then **Copy Key to Clipboard**. Roblox shows it only once.
3. **Put it in the environment settings, not in the chat.** In the Claude session, open the cloud environment menu
   in the title bar -> **Edit** (the environment's settings). Add three environment variables (or put the key under
   **Network secrets** / **API credentials** if that section is there):

   | Name | Value |
   |---|---|
   | `ROBLOX_API_KEY` | the key you just copied |
   | `ROBLOX_CREATOR_ID` | the owner id from step 1 (only digits) |
   | `ROBLOX_CREATOR_TYPE` | `user` or `group` (empty = `user`) |

   Save. Also check **Network access** there: `apis.roblox.com` must be allowed (add it under **Allowed domains**
   if the level is Limited).
4. **Start a NEW session** (a running session does not see new settings) and tell it:
   "Do the Phase 6 upload: follow docs/phase6/OWNER_UPLOAD.md". Then wait for it to ask for your OK.

---

## 2. CLAUDE: prepare (no upload yet)

The key is read from the environment only; never `echo` it, never write it to a file.

```bash
cd /home/user/roblox/nimbus-climb
git checkout v3-phase6 && git pull            # or the branch the lead named (after the merge: main)
python3 -m venv /tmp/claude-0/bpyenv          # once per container: bpy 5.2 as a module (headless Blender)
/tmp/claude-0/bpyenv/bin/pip install bpy==5.2.2 numpy lupa pillow
```

Pin **bpy 5.2.2**: the FBX stores the Blender version, so 5.2.3 or later gives other `fbxSha256` values than
`blender/meshes.json` (same models, other bytes) and the no-change check in step 1 fails.

1. **Rebuild the FBX files.** `blender/out/` is not committed, so a new container has no FBX. Build every class
   (one at a time is easiest to watch; a class takes a few minutes):

   ```bash
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class calibration
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class evolved
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class creatures
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class gates
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class lobby
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class home
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class arenadungeon
   ```
   (`--all` does the same in one go.) The build is deterministic, so afterwards `git status` must show **no change**
   in `blender/meshes.json` or `src/shared/MeshManifests/`. If something changed, stop and tell the lead: the
   manifests in git and the FBX you would upload no longer match.
2. **Run the checks** (all offline):
   ```bash
   python3 tools/test_upload_assets.py           # the uploader against a local fake API (76 checks today)
   python3 tools/mesh_names.py --check blender/out/*.manifest.json
   python3 tools/syntax.py && node tools/check.mjs
   ```
3. **Dry run** (sends nothing, writes nothing; it prints every request it would make, with the key hidden):
   ```bash
   python3 tools/upload_assets.py                # every key in blender/meshes.json (798 today)
   python3 tools/upload_assets.py --only cal_axes
   python3 tools/upload_assets.py --class pets   # one catalog class (section 5)
   python3 tools/upload_assets.py --textures     # the 10 vortex images
   ```
   Check the first line: it names the creator (`for user <id>` or `for group <id>`). It must be the game's owner.
   A key that says `FAILED: ... was not exported from this contentHash` has a stale FBX (its last build was
   `--no-export`, so `blender/meshes.json` has `"fbxSha256": null` for it): rebuild that key with the Blender python
   (`/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key <key>`) before it can go up. The tool never uploads it
   as it is.
4. Show the owner the dry-run summary and ask: "OK to upload the calibration model cal_axes?" Wait for a yes.

---

## 3. Calibration: `cal_axes` (the first real upload)

`cal_axes` is a small test model (a blue F-shaped arrow, a red and a green bar, a colour-gradient cube and a white
cube named `Head_Att`). One look at it tells us if Roblox turns, mirrors or scales our models.

**CLAUDE** (after the owner's OK):
```bash
python3 tools/upload_assets.py --upload --only cal_axes
git add src/shared/MeshIds.lua blender/upload_state.json
git commit -m "Phase 6 upload: cal_axes"     # + the attribution lines; push
```
The tool prints `done: asset <id> revision 1 moderation ...` and writes `blender/upload_state.json` and
`src/shared/MeshIds.lua`. Always commit those two files together (the state file is how the next run knows what is
already uploaded; losing it means duplicate uploads).

**OWNER** (in Studio, about 5 minutes):
1. Get the new files (the same way as every update), start `Start-Rojo-Windows.bat`.
2. Open the **published** game in Studio (create.roblox.com -> your experience -> **Edit in Studio**). Roblox only
   loads your models in a place that belongs to the same owner. Click **Plugins -> Rojo -> Connect**.
3. Press **Play** (F5). In **View -> Output** look for `[MeshLibrary] 1 mesh model(s) to load` (a slow load also
   prints `cal_axes took ... s to load`, that is fine). A yellow line `cal_axes (asset ...) stays on the Part build:
   ...` means it failed: copy that whole line into the chat.
4. In the **Explorer**, open **ReplicatedStorage -> MeshLibrary -> cal_axes** and click it. In **Properties ->
   Attributes**, copy these into the chat: `ML_Status` (should be `ready`), `ML_Yaw`, `ML_Scale`, `ML_FitErr`,
   `ML_Error` (if any).
5. Look at it: right-click `cal_axes` -> **Copy**, press **Stop**, right-click **Workspace** -> **Paste Into**, then
   select it and press **F** to zoom. Tell Claude: is the cube **colourful** (black, red, green, blue corners) or
   grey? Can you read the blue **F** the right way round from above? Is `Head_Att` (inside the model) an Attachment
   or a part? Then delete the pasted copy (do not publish it).

**CLAUDE**: compare with `blender/kit/calib.py` (the F points to -Z, red bar +X, green bar +Y, cube centred at
(0, 1, 0)). Yaw and scale are fixed by `MeshLibrary` automatically; a **mirror** or a **grey cube** is a stop: report
it to the lead (exporter change), do not upload more. Optional (recipe section 6 step 4): change one colour in
`blender/kit/calib.py`, rebuild `--key cal_axes`, upload again: the tool must say `update` and the id must stay the
same; then `git checkout blender/kit/calib.py`, rebuild and upload once more.

---

## 4. One pet, live: Pebble Pup

Pebble Pup is the Dog body with feather wings; the crown is the accessory of the same test set.

**CLAUDE** (ask the owner first):
```bash
python3 tools/upload_assets.py --only pet_dog,pet_dog_low,wing_feather_L,wing_feather_R,wing_feather_L_low,wing_feather_R_low,acc_crown,acc_crown_low
python3 tools/upload_assets.py --upload --only pet_dog,pet_dog_low,wing_feather_L,wing_feather_R,wing_feather_L_low,wing_feather_R_low,acc_crown,acc_crown_low
```
Commit `MeshIds.lua` + `upload_state.json`, push.

If a key says **`the create of KEY may have reached Roblox`** (the connection broke after the upload was sent), the
tool refuses that key until someone looked: open Creator Hub -> **Creations** -> **Development Items** -> **Models**
(**Decals** for a texture) and look for the name it printed, made at that time. Found it: run
`python3 tools/upload_assets.py --upload --only KEY --adopt KEY=<its id>` (records that id, no new upload). Not there:
`python3 tools/upload_assets.py --upload --only KEY --not-created KEY` (uploads it again). Never just run the upload
again without one of the two: that could make a second copy.

**OWNER** (Studio, published game, Rojo connected, **Play**):
1. Output: `[MeshLibrary] 9 mesh model(s) to load` (cal_axes + 8) and no yellow `stays on the Part build` line.
   `ReplicatedStorage -> MeshLibrary -> pet_dog` has `ML_Status = ready`.
2. Type `/pet pebble` in the game chat: a Pebble Pup appears in front of you (`/clearpets` removes it). It should
   look like the approved preview (`docs/phase6/img/pebble_pup_preview.png`): smooth fine voxels, no holes, no
   flicker. Watch for 10 seconds: the wings flap, the eyes blink, it bobs.
3. If you own a Pebble Pup, equip it: it follows you as a mesh pet. Put one in your Pet Garden too (garden pets use
   the `_low` models).
4. Tell Claude what you saw (a screenshot helps). If something looks wrong, nothing more is uploaded until it is
   fixed.

---

## 5. Batches by class

**CLAUDE**: one class per batch, in this order: `pets`, `evolved`, `creatures`, `gates`, `lobby`, `home`,
`arenadungeon`. Ask the owner before each batch. For a class `C`:

```bash
python3 tools/upload_assets.py --class C                 # dry run (C = pets, evolved, creatures, ...)
python3 tools/upload_assets.py --upload --class C        # real
```
`--class C` takes every key of `blender/catalog/C.json` that is uploaded (its `_low` keys too); it can be repeated
and mixed with `--only` (`--class gates --only cal_axes`). A key of the catalog that is not built yet is refused
with the build command to run. Keys already uploaded and unchanged are skipped (`skip: unchanged`). The first line of
the dry run counts the keys; today: pets 94, evolved 354, creatures 60, gates 6, lobby 63, home 168,
arenadungeon 52 (with cal_axes: 798). The tool keeps under the Roblox limits by itself (100 writes and 250 reads per
minute), so a big class takes several minutes.

**`_low` keys.** Pets, evolved forms, creatures, the lobby plot (`prop_plot_low`) and the home plots
(`home_<station>_<level>_low`, new in Phase 6 W3: the far-away version of every home station, house, fence, fountain
and podium; the Garden bed pieces have none) have a lighter `_low` copy. They are ordinary models: upload them in the
same batch as their High keys (`--class` does that by itself). A `_low` key that is missing, rejected or still in
review just keeps the High mesh at a distance: nothing breaks, it only costs a little more on phones.

A key that says `the create of KEY may have reached Roblox`: see section 4 (check Creator Hub, then `--adopt` or
`--not-created`), or 8g.

After each batch: commit `src/shared/MeshIds.lua` + `blender/upload_state.json`, rebuild the place file
(`rojo build default.project.json -o play/NimbusClimb.rbxlx`, then `python3 tools/verify_place.py`), push, and ask
the owner to Play-test that class:

* **pets / evolved**: `/pets` lines up every pet, `/pets 1` and `/pets 2` the evolved forms (auras, glow, particles).
* **creatures**: `/raid` starts a Boss Raid; look at the sky dragon, the NPC pedestals, the coins.
* **gates / lobby**: walk the Gate Court and the plaza.
* **home / arenadungeon**: your home (build it up), the Battle Arena, a Dungeon run.

In Output, any yellow `[MeshLibrary] <key> ... stays on the Part build` or `could not be downloaded on this device`
line goes to Claude.

---

## 6. The vortex textures (the magic swirl inside every gate)

10 PNG layers in `blender/textures/vortex/` (built by `python3 blender/textures/build_vortex.py`). Today the gates
show the effects-only fallback swirl; with all ids the textured swirl appears.

**CLAUDE** (ask first):
```bash
python3 tools/upload_assets.py --textures                # dry run
python3 tools/upload_assets.py --textures --upload       # real: writes blender/textures/upload_state.json + src/shared/TextureIds.lua
```

**Decal or Image id? Check it before the game uses them.** The tool uploads each PNG as a **Decal**. A Decal id does
not always show in an ImageLabel; the game needs the **Image** id.

**OWNER** (Studio, edit mode, after Roblox approved the images):
1. Explorer -> **StarterGui** -> **+** -> **ScreenGui**, then inside it **+** -> **ImageLabel**.
2. Properties of the ImageLabel: **BackgroundColor3** black (the layers are white), **Size** `{0, 300},{0, 300}`,
   **Image** = `rbxassetid://<the vortex_arms id from TextureIds.lua>`.
3. You see a white swirl: good, the id works. The **Image** box changed to a different number by itself: that new
   number is the Image id. Nothing shows: it is the Decal id. Tell Claude which (and both numbers).
4. **Delete the test ScreenGui** (otherwise players see it).

**CLAUDE**, only if the ids are Decal ids: get the Image id of each texture from the owner the same way (paste each
id into the ImageLabel), then record them all in one go (check with the dry run first; nothing is sent to Roblox):
```bash
python3 tools/upload_assets.py --textures --set-id vortex_arms=<image id>,vortex_rim=<image id>            # dry run
python3 tools/upload_assets.py --textures --upload --set-id vortex_arms=<image id>,vortex_rim=<image id>   # writes
```
It puts each Image id as `assetId` in `blender/textures/upload_state.json`, keeps the Decal id next to it as
`decalAssetId` (later `--refresh` runs read the moderation from the Decal) and rewrites `TextureIds.lua`. It refuses
an unknown key, an id that is not a number, the Decal id itself and a key that was never uploaded; a wrong Image id
is fixed by running `--set-id` again with the right one.
The tool never PATCHes images: a changed PNG uploads as a NEW Decal (the old id goes to previousAssetIds), so repeat
the Image-id check for that key; --force on an unchanged image is refused.

Then commit `src/shared/TextureIds.lua` + `blender/textures/upload_state.json`. **OWNER** Play-test: every gate in the
Gate Court shows the textured swirl, the rim glows, small lightning flickers, and the light streaks pull **inward**
to the centre (not outward). Graphics **Low** in SETTINGS: the gates stand still.

---

## 7. OWNER: ship it

When a batch looks good in Play: File -> **Publish to Roblox**, then **Migrate to Latest Update** on the Creator Hub
(README "Publishing an update"). Old servers keep their models; new servers load the new ones.

---

## 8. When something goes wrong

**a. Moderation rejected a model.** The tool prints `WARNING: <key> was REJECTED by moderation` and leaves that key
out of `MeshIds.lua`: the game keeps its Part model there. Check the key's preview
(`python3 tools/render_model.py meshkey:<key> -o x.png`) for anything that could look bad, change the design or its
name in the catalog, rebuild the key (`--key <key>`) and upload it again (it becomes a new version), then
`python3 tools/upload_assets.py --upload --refresh --only <key>` later to read the new moderation state. Still
rejected: leave it as a Part model and tell the owner. A model in review (`Reviewing`) is already in `MeshIds.lua`; it
just fails to load and falls back until it is approved. Run `python3 tools/upload_assets.py --upload --refresh` an
hour later to record the final states, and commit.

**b. HTTP 429 / 5xx / network errors.** The tool waits (it honours `retry-after`) and retries up to 6 times by
itself. If it still gives up, or the session stopped half way: run the **same command again**. Finished keys are
skipped, and an upload that was still processing (`still running ...; saved, the next run resumes it`) is resumed, never
sent twice. A proxy `403` or "host not allowed" means the environment's network settings block `apis.roblox.com`
(step 1.3).

**c. 401 / 403 from Roblox on the first key.** The key is wrong, expired (60 days unused), lacks Assets Read + Write,
or its IP list blocks the session. Stop the run (Ctrl-C). OWNER: make a new key (step 1.2), replace
`ROBLOX_API_KEY` in the environment settings, start a new session. A new key is fine: the ids stay the same.

**d. `refused: upload_state.json belongs to user X, not group Y`.** The creator changed. The tool never switches
owners, because the game could not load assets of another owner. If the game really moved to a group, ask the lead:
every model must be uploaded again under the new owner (a new state file).

**e. A model changed after it was uploaded (the structureHash rule).** Rebuild it with `build_all.py`, then run the
uploader for that key:
* same **structureHash** (only colours or shapes changed, same parts): `update` = a PATCH, a new version of the
  same id. `MeshIds.lua` does not change. New servers load the new version; running servers keep the old one.
* different **structureHash** (parts added, removed or renamed): `new-asset` = a NEW id. The new id in
  `MeshIds.lua` and the new manifest in `src/shared/MeshManifests/` MUST go into the **same commit** and the same
  publish, so an old server never loads a mesh its manifest does not describe. The old id is kept under
  `previousAssetIds` in the state file.
* World pieces (lobby, home, arena, dungeon) also check a `LayoutSig`: if the Part build of that piece changed in
  the code, the old mesh no longer fits and that piece quietly stays a Part model until it is rebuilt and uploaded.

**f. `[MeshLibrary] <key> could not be downloaded on this device`.** One player's device failed to fetch it; that
player sees the Part model for that key. Nothing to do unless it happens for everyone.

**g. `the create of KEY may have reached Roblox`.** The upload was sent but the answer got lost (a 500 / 502 / 504, a
dropped connection, or the session stopped half way through a create). The key is marked `pendingCreate` in the
state file and every run refuses it until it is settled. OWNER or CLAUDE: Creator Hub -> **Creations** ->
**Development Items** -> **Models** (**Decals** for a texture); look for the name the message printed, made at the
time it printed. Found: `python3 tools/upload_assets.py --upload --only KEY --adopt KEY=<id>`. Not there:
`python3 tools/upload_assets.py --upload --only KEY --not-created KEY`. (Add `--textures` for a texture key.)

**h. `FAILED: <key>: ... was not exported from this contentHash`.** The FBX on disk is not the one the last build
described: the last build was `--no-export` (plain `python3`, no Blender), so `blender/meshes.json` has
`"fbxSha256": null` for that key, or the file changed since. Rebuild it with the Blender python
(`/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key <key>`, or `--class <class>`) and run the upload again.

---

## 9. Roll back

Everything goes back to the Part models when `MeshIds.lua` is empty:

* **All models:** CLAUDE writes `src/shared/MeshIds.lua` back to the stub (the 2 comment lines + `return {}`),
  commits, rebuilds the place file. OWNER publishes. The same for the swirl: `TextureIds.lua` -> `return {}`.
* **One model:** delete its line (`key = 123,`) from `MeshIds.lua`, commit, publish.
* Keep `blender/upload_state.json`: it still knows every uploaded asset, so going forward again needs no new upload.
  But the next uploader run writes **all** known ids back into `MeshIds.lua`: after any later run, check
  `git diff src/shared/MeshIds.lua` and remove the line again.

---

## 10. Quick reference

| What | Command |
|---|---|
| uploader help | `python3 tools/upload_assets.py --help` |
| dry run (default) | `python3 tools/upload_assets.py [--only k1,k2] [--class pets] [--textures]` |
| real upload | `python3 tools/upload_assets.py --upload --only k1,k2` |
| one class (with its `_low` keys) | `python3 tools/upload_assets.py --upload --class pets` |
| re-read moderation | `python3 tools/upload_assets.py --upload --refresh` |
| "the create of KEY may have reached Roblox" | found in Creator Hub: `--upload --only KEY --adopt KEY=<id>`; not there: `--upload --only KEY --not-created KEY` (8g) |
| texture Decal id -> Image id | `python3 tools/upload_assets.py --textures --upload --set-id KEY=<image id>` (section 6) |
| "was not exported from this contentHash" | `/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key <key>` (8h) |
| re-send unchanged | `--force` (meshes only, rarely needed; refused for images) |
| wait longer per upload | `--poll-timeout 600` (seconds, default 300) |
| offline tests | `python3 tools/test_upload_assets.py` |
| build a class / a key | `/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets` / `--key pet_dog` |
| look at a key | `python3 tools/render_model.py meshkey:pet_dog:pebble_pup -o x.png` |
| place file | `rojo build default.project.json -o play/NimbusClimb.rbxlx` then `python3 tools/verify_place.py` |

Files the upload writes (commit them together): `src/shared/MeshIds.lua`, `blender/upload_state.json`,
`src/shared/TextureIds.lua`, `blender/textures/upload_state.json`.
