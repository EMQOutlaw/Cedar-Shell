#!/usr/bin/env python3
"""Prove the timer persists, pauses and completes across shell process restarts."""
from pathlib import Path
import json,os,re,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
QML='''import QtQuick
import Quickshell
import "."
import "services"
ShellRoot {
    CoreTimer { id:timer }
    Timer {
        interval:500;running:true;repeat:true
        property int step:0
        onTriggered:{
            const mode=Quickshell.env("TIMER_TEST");
            if(mode==="write" && step++===0){timer.start(300,"Persisted tea timer");timer.toggle();return;}
            const ok=mode==="write" || (mode==="reload" ? timer.active && timer.paused && timer.remaining===300 && timer.label==="Persisted tea timer":timer.completed && !timer.active);
            if(!ok){console.error("FAIL: timer "+mode);Qt.exit(1);return;}
            console.log("PASS: timer "+mode);Qt.quit();
        }
    }
}'''
with tempfile.TemporaryDirectory(prefix='cedar-timer-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700);(source/'preview.qml').write_text(QML)
    settings=p/'state/cedar';settings.mkdir(parents=True)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state')}
    for mode in ('write','reload','elapsed'):
        if mode=='elapsed':
            data=json.loads((settings/'core-timer.json').read_text());data.update(paused=False,deadline=time.time()*1000-1000)
            (settings/'core-timer.json').write_text(json.dumps(data))
        result=subprocess.run(['qs','-p',str(source/'preview.qml')],env={**env,'TIMER_TEST':mode},capture_output=True,text=True,timeout=5)
        output=result.stdout+result.stderr
        if result.returncode or 'PASS: timer '+mode not in output or re.search(r'ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|FAIL:',output):print(output);raise SystemExit(1)
    print('PASS: timer persistence, paused restore and completion after restart')
