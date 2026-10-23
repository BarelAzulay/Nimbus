# theres a border with nothing inside its useless (fixed 2026-10-23)

**Report:** the Storm Altar poster's left frame ("ArtWell") was empty.

**Cause (confirmed in Studio):** `Config.Art.StormfangImage` held the upload's **Decal** id 129423539279679
(asset type 13). An ImageLabel needs an **Image** id, so the fetch failed (`AssetFetchStatus.Failure`) and the frame
stayed empty. The same id feeds Stormfang's Pet Index banner, which was blank too. And that first upload had a
gray/white checkerboard painted where the background should be transparent.

**Fix:** uploaded `branding/stormfang-art.png` (truly transparent; hidden pixels recoloured to the well's dark blue so
no gray fringe) through Studio as Image **101827417487186** and set it as `Config.Art.StormfangImage` (contract.json
and ARCHITECTURE_V3 updated). Assets for ImageLabels must be Image ids, never Decal ids (see the Config comment).

**Evidence:** asset type 1 (Image), creator TellingBarel1234, `PreloadAsync` Success; live playtest at the altar:
`StormfangArt.IsLoaded = true` and the poster shows the Stormfang art on dark blue, no checkerboard.
