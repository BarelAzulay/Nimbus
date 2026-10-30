# Sky (Blender)

- `render_sky.py`: the shipped Nimbus sky (pink / purple / blue clouds, small stars). Writes `branding/sky/`.
- `sky_themes.py`: 21 painted skybox options for the sky pitch (7 skies x 3 directions: Day, Dawn / Sunset, Night,
  Storm Titan, Lava Golem, Frost Wyrm, Shadow Hydra). One shared world shader (same elevation ramp, same cloud
  language, same horizon calming), one palette + one or two signature features per theme. The theme table is at the
  top of the script.

## Sky themes

Render (headless Blender 5.2, one process at a time):

```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python sky_themes.py -- --themes all --res 512
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python sky_themes.py -- --themes day_vivid --res 1024 --skip-view --skip-pano
py -3.12 sky_themes.py --contact
```

Per theme it writes `.superpowers/sky-pitch/<theme>/` (in the main Nimbus folder, not committed):
`SkyboxBk/Dn/Ft/Lf/Rt/Up.png` (RES x RES, Roblox face names), `view.jpg` (75 degree game view, 10 degrees up, toward
the sun / feature), `view_up.jpg` (45 degrees up, for zenith features) and `pano.jpg` (equirectangular). It prints a
seam score per edge (mean RGB step across the cube edges; the "inner" number is the same step between two neighbouring
columns inside a face, so a seam score close to it means no visible seam). `--contact` builds `contact.jpg` from all
`view.jpg`.

Faces follow the same convention as `render_sky.py` (Ft -Z, Bk +Z, Rt +X, Lf -X, Up +Y, Dn -Y). Themes with a zenith
or nadir feature (vortex, rift, ribbon, lava veins) put detail on Up / Dn, so check those two faces' rotation in Studio
once before shipping one of them.

## The shipped themes (the living sky)

The player's picks (2026-10-30, `docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md`): 7 themes at 1024 px,
one per sky the game shows (`Config.Sky.Themes` / `Config.Sky.RaidThemes`):

| Sky | Theme id | Name |
|---|---|---|
| Day (6 min) | `day_vivid` | Vivid Skylands |
| Dawn (2 min) + Sunset (9 min) | `dusk_amber` | Amber Burn |
| Night (3 min) | `night_aurora` | Aurora Slumber |
| Storm Titan raid | `storm_teal` | Thunderhead Teal |
| Lava Golem raid | `lava_obsidian` | Obsidian Furnace |
| Frost Wyrm raid | `frost_glacial` | Glacial Void |
| Shadow Hydra raid | `shadow_eclipse` | Eclipse Shadow |

`build_sky_manifest.py` copies the final renders (main Nimbus folder `.superpowers/sky-final/<theme>/Skybox<Face>.png`)
to `blender/textures/sky/<theme>/` (committed) and adds the 42 keys `sky_<theme>_<Face>` to
`blender/textures/textures.json`, keeping the vortex keys and the file's format. Run it again after
`build_vortex.py` (that script rewrites textures.json with the vortex keys only).

```
py -3.12 blender/sky/build_sky_manifest.py --dry-run   # check the 42 renders, write nothing
py -3.12 blender/sky/build_sky_manifest.py             # copy + index
```

The faces reach the game through the keyed upload (`docs/phase6/OWNER_UPLOAD.md` section 6c) into
`src/shared/TextureIds.lua`; `src/shared/SkyFaces.lua` reads them. A theme shows only once all six of its faces have
Image ids; until then that sky keeps LightingService's boot faces and the cycle changes only the light.

**Roblox face slots (checked in Studio 2026-10-30):** Roblox draws `SkyboxRt` on the -X side and `SkyboxLf` on the +X side, the opposite of this script's Lf (-X) / Rt (+X). The game swaps them in `src/shared/SkyFaces.lua` (SLOT), so the files and texture keys keep the render names. Painted skies also hide the engine sun and moon (`CelestialBodiesShown = false`).
