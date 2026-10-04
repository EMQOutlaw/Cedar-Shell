#!/usr/bin/env python3
"""List the selected theme's available wallpapers as safe JSON argv paths."""
from pathlib import Path
import json
import os

home = Path.home()
state = Path(os.environ.get('XDG_STATE_HOME', home/'.local/state'))/'omarchy/current'
try:
    theme = (state/'theme.name').read_text().strip().lower()
except OSError:
    theme = 'cedar'
roots = [state/'theme/backgrounds', Path(os.environ.get('XDG_CONFIG_HOME', home/'.config'))/'omarchy/backgrounds'/theme,
         Path(__file__).resolve().parents[1]/'themes/backgrounds']
paths = {}
for root in roots:
    try:
        for path in root.iterdir():
            if path.is_file() and path.suffix.lower() in {'.png','.jpg','.jpeg','.webp','.bmp'}:
                paths.setdefault(path.name.lower(), {'path':str(path.resolve()),'name':path.stem.replace('_',' ').replace('-',' ').title()})
    except OSError:
        continue
try:
    selected = str((state/'background').resolve(strict=True))
except OSError:
    selected = ''
print(json.dumps({'selected':selected,'items':sorted(paths.values(),key=lambda row:row['name'].lower())}))
