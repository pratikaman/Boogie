# Character artwork

Boogie's realistic companions are rendered from scanned people by **Renderpeople**.
These are human scans, not photographs of celebrities or generated identities.

| Companion | Source model | Motion |
| --- | --- | --- |
| Sophia | `rp_sophia_animated_003_idling.fbx` | Retargeted from Manuel's dance onto Sophia's skeleton |
| Manuel | `rp_manuel_animated_001_dancing.fbx` | A loop assembled from the supplied motion capture |

Source: [Renderpeople free animated people](https://renderpeople.com/free-3d-people/).
The official FBX download is
<https://renderpeople.com/sample/free/renderpeople_free_animated_people_FBX.zip>.
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

```sh
blender -b -t 6 --python tools/characters/render.py -- \
  --source /path/to/rp_manuel_animated_001_dancing.fbx \
  --output /tmp/manuel-frames --id manuel
blender -b -t 6 --python tools/characters/render.py -- \
  --source /path/to/rp_sophia_animated_003_idling.fbx \
  --motion-source /path/to/rp_manuel_animated_001_dancing.fbx \
  --output /tmp/sophia-frames --id sophia
python3 tools/characters/pack.py /tmp/manuel-frames assets/characters/manuel
python3 tools/characters/pack.py /tmp/sophia-frames assets/characters/sophia
```

Adaptations: soft studio lighting, transparent backgrounds, consistent framing,
retargeting, a shortened loop with a blended seam, and interaction poses. The
renderer uses 384 × 512 frames at 20 fps. The app changes playback speed with tempo
and caches atlas pages on demand.
