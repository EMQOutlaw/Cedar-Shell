#!/usr/bin/env python3
"""Quiet controls and overlay popup checks with isolated preferences; no hardware actions."""
from pathlib import Path
import os,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-core-ui-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else p/'shots';shots.mkdir(parents=True,exist_ok=True)
    harness=(ROOT/'tests/core/ControlsHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    (source/'tests/response_limit.py').write_text('import sys,time\nsys.stdin.readline()\nsys.stdout.write("x"*100000);sys.stdout.flush()\ntime.sleep(10)\n')
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=60)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: quiet controls' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:',output):
        print(output);raise SystemExit(1)
    if re.search(r'FAIL!|[1-9][0-9]* failed',output): print(output); raise SystemExit(1)
    print('PASS: offscreen Qt pointer/keyboard controls, overlay placement and geometry; native Wayland/scale not tested')
