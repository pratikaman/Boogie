# Character artwork

Boogie's realistic companions are rendered from scanned people by **Renderpeople**.
These are human scans, not photographs of celebrities or generated identities.

| Companion | Source model | Motion |
| --- | --- | --- |
| Sophia | `rp_sophia_animated_003_idling.fbx` | Retargeted from Manuel |
| Manuel | `rp_manuel_animated_001_dancing.fbx` | Supplied motion capture |
| Carla | `rp_carla_rigged_001_zup_t.fbx` | Retargeted from Manuel |
| Nathan | `rp_nathan_animated_003_walking.fbx` | Retargeted from Manuel |

Source: [Renderpeople free 3D people](https://renderpeople.com/free-3d-people/).
The official FBX downloads are
[animated people](https://renderpeople.com/sample/free/renderpeople_free_animated_people_FBX.zip)
and [rigged people](https://renderpeople.com/sample/free/renderpeople_free_rigged_people_FBX.zip).
Downloaded 29 September 2026.

## Usage terms

These assets are **not CC0 or covered by a source-code license**. Renderpeople's
[terms](https://renderpeople.com/general-terms-and-conditions/) apply. Section 2.5
covers the free models; section 4.1 permits rendering still images and animations
for private and commercial projects. Sections 4.2 and 4.3 restrict redistribution
of source 3D data and sale as stock imagery. Source FBX files, textures, and rigs
are not included in this repository or app. The packaged PNG atlases are rendered
animation artwork for Boogie, not a redistribution of the source models. Do not
repackage these characters as a standalone asset library.

## Reproduction

Normal builds use the committed atlases and require no downloads or Blender.
To regenerate artwork, download and extract the original FBX archives outside
this repository. Keep each model's `tex/` directory beside its FBX file. Use
Blender 4.5 and Python 3 with Pillow:

All four people use the same three excerpts from Manuel's original 30 fps
capture. Start frames are inclusive; the final 12 output frames blend back to
the opening pose. Horizontal travel is removed so people stay on the Dock.

| Clip ID | Name | Source start | Duration | Facing | Playback beats |
| --- | --- | ---: | ---: | ---: | ---: |
| `dance` | Easy groove | 2 | 12 s | 0° | 24 |
| `high-kicks` | High kicks | 422 | 8 s | 180° | 16 |
| `step-dip` | Step & dip | 812 | 8 s | 180° | 16 |

For example, render Sophia's three routines, then pack them together:

```sh
blender -b -t 4 --python tools/characters/render.py -- \
  --source /path/to/rp_sophia_animated_003_idling.fbx \
  --motion-source /path/to/rp_manuel_animated_001_dancing.fbx \
  --output /tmp/sophia-dance --id sophia --in-place
blender -b -t 4 --python tools/characters/render.py -- \
  --source /path/to/rp_sophia_animated_003_idling.fbx \
  --motion-source /path/to/rp_manuel_animated_001_dancing.fbx \
  --output /tmp/sophia-kicks --id sophia --in-place \
  --clip high-kicks --start 422 --duration 8 --yaw 180
blender -b -t 4 --python tools/characters/render.py -- \
  --source /path/to/rp_sophia_animated_003_idling.fbx \
  --motion-source /path/to/rp_manuel_animated_001_dancing.fbx \
  --output /tmp/sophia-dip --id sophia --in-place \
  --clip step-dip --start 812 --duration 8 --yaw 180
python3 tools/characters/pack.py /tmp/sophia-dance assets/characters/sophia \
  /tmp/sophia-kicks /tmp/sophia-dip
```

Repeat with each model and its matching `--id`; omit `--motion-source` when
rendering Manuel himself. Carla uses the **Z-up T-pose** FBX variant. The base
`dance` pass also renders the three lid-crouching poses. `--preview` and
`--preview-frame 450` render one pose for inspection without a full bake.

Adaptations include soft studio lighting, transparent backgrounds, consistent
framing, retargeting, in-place motion, blended loop seams, and interaction poses.
Frames are 384 × 512 at 20 fps. The app maps each routine to its beat duration,
changes speed with tempo, and caches atlas pages on demand. Normal builds use
the committed atlases and require no downloads or Blender.
