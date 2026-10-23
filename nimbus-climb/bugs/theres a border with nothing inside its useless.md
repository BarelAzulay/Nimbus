# theres a border with nothing inside its useless (in progress, 2026-10-23)

**Report:** the Storm Altar poster's left frame ("ArtWell") is empty.

**Cause (confirmed in Studio):** `Config.Art.StormfangImage` held the upload's **Decal** id 129423539279679
(asset type 13). An ImageLabel needs an **Image** id, so the fetch failed (`AssetFetchStatus.Failure`) and the
frame stayed empty. The same id feeds Stormfang's Pet Index banner, which was blank too.

**Step 1 (done):** switched to the Decal's Image 106396716077974 (`InsertService:LoadAsset`), which loads
(`Success`, `IsLoaded = true`). Contract and ARCHITECTURE_V3 updated.

**Step 2 (waiting on an upload):** that uploaded image has a gray/white checkerboard painted where the
background should be transparent, so the art now shows on a checkerboard. `branding/stormfang-art.png` is truly
transparent; a cleaned copy (transparent pixels recoloured to the well's dark blue, no gray fringe) is on the
Desktop as "UPLOAD ME - stormfang-art-clean.png". Once it is uploaded, put its Image id in Config.Art,
contract.json and ARCHITECTURE_V3, check the poster in Studio, then move this bug to fixed/.
