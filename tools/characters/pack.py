"""Pack one or more rendered clips into 4x4 PNG atlases.

python3 tools/characters/pack.py BASE_FRAMES DESTINATION [EXTRA_CLIP_FRAMES ...]
Pillow is a development-only dependency; source models remain outside the repo.
"""
import argparse
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
parser.add_argument('extra', type=Path, nargs='*')
args = parser.parse_args()
manifest = json.loads((args.source / 'frames.json').read_text())
width, height = manifest['width'], manifest['height']
manifest.update(columns=4, rows=4, clips={})
frames = []
for source in [args.source] + args.extra:
    data = json.loads((source / 'frames.json').read_text())
    assert (data['width'], data['height'], data['fps']) == (width, height, manifest['fps']), 'Incompatible clip format'
    count = max(c['start'] + c['count'] for c in data['clips'].values())
    for name, clip in data['clips'].items():
        assert name not in manifest['clips'], f'Duplicate clip: {name}'
        assert clip['start'] >= 0 and clip['count'] > 0, f'Invalid clip: {name}'
        manifest['clips'][name] = {'start': len(frames) + clip['start'], 'count': clip['count']}
    frames.extend(source / f'{index:04d}.png' for index in range(count))
assert all(frame.is_file() for frame in frames), 'Render every frame before packing'
count = len(frames)
destination = args.destination
destination.mkdir(parents=True, exist_ok=True)
for start in range(0, count, 16):
    page = Image.new('RGBA', (width * 4, height * 4))
    for index in range(start, min(start + 16, count)):
        with Image.open(frames[index]) as frame:
            assert frame.size == (width, height)
            cell = index - start
            page.paste(frame, ((cell % 4) * width, (cell // 4) * height))
    output = destination / f'atlas-{start // 16:03d}.png'
    temporary = output.with_suffix('.tmp.png')
    page.save(temporary, optimize=True)
    temporary.replace(output)
(destination / 'animation.json').write_text(json.dumps(manifest, indent=2) + '\n')
for stale in destination.glob('atlas-*.png'):
    if int(stale.stem.split('-')[1]) >= (count + 15) // 16:
        stale.unlink()
print(f'Packed {count} frames into {(count + 15) // 16} atlases: {destination}')
