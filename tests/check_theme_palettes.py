#!/usr/bin/env python3
"""Load every bundled palette through Theme.qml and render the real picker.

Optional first argument: directory in which to retain the screenshots.
All settings, runtime sockets and rendered source are isolated from the desktop.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import desktop_runtime

with tempfile.TemporaryDirectory(prefix='cedar-theme-palettes-') as tmp:
    base = Path(tmp)
    source = base / 'shell'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.log'))
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    config = base / 'config'
    (config / 'cedar').mkdir(parents=True)
    env = {**os.environ, 'CEDAR_TEST': '1',
           'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic',
           'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QUICK_BACKEND': 'software',
           'QSG_RENDER_LOOP': 'basic', 'XDG_CONFIG_HOME': str(config),
           'XDG_STATE_HOME': str(base / 'state'), 'XDG_RUNTIME_DIR': str(runtime)}
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)
    # No personal palettes from the developer's desktop enter the fixtures.
    from unittest.mock import patch
    with patch.dict(os.environ, XDG_CONFIG_HOME=str(config)):
        items = desktop_runtime.themes()
    template = (ROOT / 'tests/core/ThemePaletteHarness.qml').read_text()
    template = template.replace('"../.."', '"."').replace('"../../', '"')
    template = template.replace('BUNDLED_THEMES_FIXTURE', json.dumps(items))
    for item in items:
        (config / 'cedar/theme.json').write_text(json.dumps(
            {key: item[key] for key in ('name', 'mode', 'colors')}))
        (source / 'preview.qml').write_text(template.replace('EXPECTED_THEME_FIXTURE', json.dumps(item)))
        env['CEDAR_THEME_SCREENSHOT'] = str(shots / (item['name']+'.png')) if shots else ''
        result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if result.returncode or f"PASS: bundled theme {item['name']}" not in output or re.search(
                r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|FAIL:', output):
            print(output)
            raise SystemExit(f"Theme rendering failed: {item['name']}")
    print(f'PASS: {len(items)} palettes loaded through Theme.qml and rendered in Appearance')
