#!/usr/bin/env python3
"""Offscreen: SettingsService routes, navigation, drafts, depth, search, persistence and lock guard, with isolated preferences and state."""
from pathlib import Path
import os,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-settings-service-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    harness=(ROOT/'tests/core/SettingsServiceHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QT_QUICK_BACKEND':'software','QSG_RENDER_LOOP':'basic','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state')}
    try:
        result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=30)
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b'').decode(errors='replace')+(error.stderr or b'').decode(errors='replace'))
        raise SystemExit('Settings service checks timed out')
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Settings service' not in output or re.search(r'Quickshell has crashed|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:',output):
        print(output);raise SystemExit(1)
    state=p/'state/cedar/settings-window.json'
    if not state.is_file() or '"width": 1300' not in state.read_text().replace('"width":1300','"width": 1300'):
        print(output);raise SystemExit('The remembered window size was not written to the private state directory')
    print('PASS: Settings service routes, navigation, drafts, depth, search, persistence and lock guard')
