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
