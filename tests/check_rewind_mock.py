#!/usr/bin/env python3
"""Render the Trail Rewind mock offscreen into ~/Pictures/trail-rewind (or argv[1])."""
from pathlib import Path
import os,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-rewind-mock-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.home()/'Pictures'/'trail-rewind';shots.mkdir(parents=True,exist_ok=True)
    harness=(ROOT/'tests/mock/RewindHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=30)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Trail Rewind mock' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:',output):
        print(output);raise SystemExit(1)
    renders=len(list(shots.glob('rewind-*.png')))
    if renders<4: raise SystemExit('Missing renders: '+str(renders)+' of 4')
    print('PASS: Trail Rewind mock — '+str(renders)+' renders in '+str(shots))
