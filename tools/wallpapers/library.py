import json
import os
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from desktop_runtime import wallpapers
data = wallpapers()
cache = Path.home() / '.cache/omarchy/image-selector'
index = {}
try:
    for line in (cache / 'index.tsv').read_text().splitlines():
        parts = line.split('\t')
        if len(parts) == 3:
            index[(parts[0], parts[1])] = parts[2]
except OSError:
    pass
for item in data['items']:
    path = Path(item['path'])
    stat = path.stat()
    key = index.get((str(path), f'{stat.st_size}:{int(stat.st_mtime)}'))
    thumbnail = cache / (key + '.jpg') if key else path
    item['preview'] = (thumbnail if thumbnail.is_file() else path).as_uri()
print(json.dumps(data))
