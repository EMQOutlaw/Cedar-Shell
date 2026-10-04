#!/usr/bin/env python3
"""Render every desktop page offscreen with fixtures and isolated preferences.

Optional first argument: directory to retain screenshots. No live settings apply.
"""
from pathlib import Path
import os
import json
import re
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-ui-') as tmp:
    p=Path(tmp); source=p/'shell'; shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log'))
    runtime=p/'runtime'; runtime.mkdir(mode=0o700)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else p/'screenshots'; shots.mkdir(parents=True,exist_ok=True)
    harness=(ROOT/'tests/qml/DesktopHarness.qml').read_text().replace('../../modules','modules').replace('../../services','services').replace('import "../.."','import "."')
    roles=json.loads((ROOT/'data/default-apps.json').read_text())
    fixture={'roles':[{**r,'current':'zen.desktop' if r['id']=='browser' else 'dev.zed.Zed.desktop','mixed':False,'recommended':['zen.desktop','dev.zed.Zed.desktop']} for r in roles], 'apps':[{'id':'zen.desktop','label':'Zen Browser'},{'id':'dev.zed.Zed.desktop','label':'Zed'}]}
    harness=harness.replace('DEFAULT_APPS_FIXTURE',json.dumps(fixture))
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic',
         'QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),
         'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=25)
    output=result.stdout+result.stderr
    if 'PASS: Settings search, scoped reset, external changes, and draft navigation' not in output or result.returncode or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign',output):
        print(output); raise SystemExit(1)
    images=list(shots.glob('*.png'))
    if len(images)<35: print(output); raise SystemExit('Missing rendered pages')
    print('PASS: 16 Settings pages at wide and narrow sizes, 3 Control Center tabs, and Settings interaction checks passed')
