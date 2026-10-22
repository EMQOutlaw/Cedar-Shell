#!/usr/bin/env python3
"""Render the Understory rail offscreen over the test services and check its routing."""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-understory-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    harness = (ROOT / 'tests/core/UnderstoryHarness.qml').read_text().replace('"../.."', '"."').replace('"../../', '"')
    (source / 'preview.qml').write_text(harness)
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Understory rail' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output); raise SystemExit(1)
    if not (shots / 'understory.png').exists(): raise SystemExit('Missing render: understory.png')
    print('PASS', shots / 'understory.png')
