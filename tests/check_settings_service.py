#!/usr/bin/env python3
"""Offscreen: SettingsService routes, navigation, drafts, depth, search, persistence and lock guard, with isolated preferences and state."""
from pathlib import Path
import json,os,re,shutil,subprocess,sys,tempfile
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
    restored=subprocess.run(['qs','-p',str(source/'preview.qml')],env={**env,'CEDAR_TEST_RESTORE':'1'},capture_output=True,text=True,timeout=30)
    output=restored.stdout+restored.stderr
    if restored.returncode or 'PASS: Settings service' not in output or re.search(r'ReferenceError|TypeError|Binding loop|FAIL:',output):
        print(output);raise SystemExit('Settings state did not survive a fresh service process')
    print('PASS: Settings service routes, navigation, drafts, depth, search, persistence and lock guard')

    # A private fake executable makes Dictation's asynchronous lock race
    # reproducible and ensures these checks never reach an installed Voxtype.
    binary=p/'bin';binary.mkdir()
    fake=binary/'voxtype'
    fake.write_text('#!'+sys.executable+'\n'+'''
import json, os, pathlib, sys, time
base=pathlib.Path(os.environ['XDG_RUNTIME_DIR'])
state=base/'voxtype/state';state.parent.mkdir(exist_ok=True)
if not state.exists(): state.write_text('idle')
if sys.argv[1] == 'status':
    print(json.dumps({'alt': state.read_text(), 'model': 'fake', 'device': 'fake'}))
elif sys.argv[1] == 'record':
    verb=sys.argv[2]
    if verb == 'start': time.sleep(.15)
    with (base/'commands.jsonl').open('a') as log: log.write(json.dumps(verb)+'\\n')
    state.write_text('recording' if verb == 'start' else 'idle')
else: raise SystemExit(1)
''')
    fake.chmod(0o755)
    harness=(ROOT/'tests/core/DictationHarness.qml').read_text().replace('"../.."','"."').replace('"../../','"')
    (source/'preview.qml').write_text(harness)
    env['PATH']=str(binary)+os.pathsep+os.environ.get('PATH','')
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=15)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Dictation state' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:',output):
        print(output);raise SystemExit(1)
    commands=[json.loads(line) for line in (runtime/'commands.jsonl').read_text().splitlines()]
    if 'start' not in commands or commands[-1] != 'cancel' or (runtime/'voxtype/state').read_text() != 'idle':
        print(output);raise SystemExit('A start finishing after lock was not cancelled: '+str(commands))
    print('PASS: Dictation state, daemon loss, command guards and in-flight lock cancellation (fake Voxtype)')
