#!/usr/bin/env python3
"""Exercise real QWindows on two offscreen outputs, including hot reload.

The production host component supplies selection and lifecycle. Its layer-window
delegate is replaced by a floating QWindow only because this test has no Wayland
compositor. Preferences and reloads are confined to the temporary shell.
"""
from pathlib import Path
import json,os,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-host-check-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    config=p/'config/cedar';config.mkdir(parents=True)
    (config/'settings.json').write_text(json.dumps({'mainDisplay':'DP-2','coreEnabled':True,'coreWarnings':False,'reducedMotion':True}))
    screens=p/'screens.json';screens.write_text(json.dumps({'screens':[{'name':'DP-1','width':1280,'height':720},{'name':'DP-2','x':1280,'width':1920,'height':1080}]}))
    harness=(ROOT/'tests/core/HostHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen:configfile='+str(screens),'QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state')}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=15)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Core host identity' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:|has crashed',output):
        print(output);raise SystemExit(1)
    print('PASS: stable Core host, two virtual displays, fallback and two hot reloads')
