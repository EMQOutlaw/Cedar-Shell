#!/usr/bin/env python3
"""Resize the actual Settings window and verify pages fit at normal/large text."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import desktop_runtime

with tempfile.TemporaryDirectory(prefix='cedar-responsive-') as tmp:
    p=Path(tmp)
    source=p/'shell'
    shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('.git','__pycache__','*.log'))
    runtime=p/'runtime'
    runtime.mkdir(mode=0o700)
    fixture=(ROOT/'tests/qml/DesktopHarness.qml').read_text().split('Component.onCompleted: {',1)[1].split('\n        }\n        property int step',1)[0]
    roles=json.loads((ROOT/'data/default-apps.json').read_text())
    fixture=fixture.replace('DEFAULT_APPS_FIXTURE',json.dumps({'roles':[{**r,'current':'','mixed':False,'recommended':[]} for r in roles],'apps':[]}))
    with patch.dict(os.environ,XDG_CONFIG_HOME=str(p/'config')):
        themes=desktop_runtime.themes()
    harness=(ROOT/'tests/core/SettingsResponsiveHarness.qml').read_text()
    harness=harness.replace('"../.."','"."').replace('"../../','"')
    harness=harness.replace('FIXTURE_SETUP',fixture).replace('THEME_FIXTURE',json.dumps(themes))
    (source/'preview.qml').write_text(harness)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else None
    if shots: shots.mkdir(parents=True,exist_ok=True)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic',
         'QT_QUICK_CONTROLS_STYLE':'Basic','QT_QUICK_BACKEND':'software','QSG_RENDER_LOOP':'basic',
         'XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),
         'CEDAR_SCREENSHOT_DIR':str(shots) if shots else ''}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=150)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Settings responsive layouts' not in output or re.search(
            r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|FAIL:',output):
        print(output)
        raise SystemExit(1)
    print(next(line for line in output.splitlines() if 'PASS: Settings responsive layouts' in line))
