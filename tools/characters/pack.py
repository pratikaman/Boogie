"""Pack rendered frames into 4x4 PNG atlases; Pillow is a development-only dependency."""
import json
import sys
from pathlib import Path
from PIL import Image

source, destination = map(Path, sys.argv[1:3])
manifest = json.loads((source / 'frames.json').read_text())
width, height = manifest['width'], manifest['height']
manifest.update(columns=4, rows=4)
count = max(c['start'] + c['count'] for c in manifest['clips'].values())
destination.mkdir(parents=True, exist_ok=True)
for start in range(0, count, 16):
    page = Image.new('RGBA', (width * 4, height * 4))
    for index in range(start, min(start + 16, count)):
        with Image.open(source / f'{index:04d}.png') as frame:
            assert frame.size == (width, height)
            cell = index - start
            page.paste(frame, ((cell % 4) * width, (cell // 4) * height))
    output = destination / f'atlas-{start // 16:03d}.png'
    temporary = output.with_suffix('.tmp.png')
    page.save(temporary, optimize=True)
    temporary.replace(output)
(destination / 'animation.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Packed {count} frames into {(count + 15) // 16} atlases: {destination}')
