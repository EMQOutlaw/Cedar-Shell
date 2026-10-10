#!/usr/bin/env python3
"""Render the actual bar contents and Core without a live Wayland connection."""
from pathlib import Path
import os,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-core-bars-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else p/'shots';shots.mkdir(parents=True,exist_ok=True)
    harness=(ROOT/'tests/core/BarHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QT_QUICK_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=25)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: six bar layouts' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:',output):
        print(output);raise SystemExit(1)
    if len(list(shots.glob('bar-*.png')))!=36:print(output);raise SystemExit('Missing bar screenshots')
    print('PASS: six production bar layouts at 640/960/1280px and enlarged text, Core space and centered fallback')
