#!/usr/bin/env python3
"""Offscreen calendar integration; no provider accounts or network requests."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-calendar-ui-') as tmp:
    base = Path(tmp); source = base / 'shell'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '.local', '__pycache__'))
    harness = (ROOT / 'tests/core/CalendarHarness.qml').read_text().replace('"../.."', '"."').replace('"../../', '"')
    (source / 'preview.qml').write_text(harness)
    runtime = base / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else base / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic',
           'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'QSG_RENDER_LOOP': 'basic',
           'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(base / 'config'), 'XDG_STATE_HOME': str(base / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    try: result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired as error:
        print(error.stdout or b'', error.stderr or b''); raise SystemExit('Calendar UI test timed out')
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: calendar agenda' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output); raise SystemExit(1)
    assert (shots / 'calendar-connected.png').is_file() and (shots / 'calendar-connections.png').is_file()
    print('PASS: calendar agenda, all-day dates, connection controls, narrow layout and lock privacy')
