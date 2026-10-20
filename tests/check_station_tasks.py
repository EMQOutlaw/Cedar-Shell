#!/usr/bin/env python3
"""Field Station migration: unchanged Overview, one launch action, no retired page."""
from pathlib import Path
import os,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-field-regression-') as tmp:
    base=Path(tmp);source=base/'shell'
    shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('.git','.local','__pycache__'))
    runtime=base/'runtime';runtime.mkdir(mode=0o700)
    (source/'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "modules"
import "services"
import "components"
ShellRoot {
    FloatingWindow {
        id: host
        visible: true; implicitWidth: 1000; implicitHeight: 1000
        FieldStation { id: field; width: 960; active: true }
        function check(ok,message){if(!ok){console.error("FAIL: "+message);Qt.exit(1);}return ok;}
        function all(item,result){result.push(item);for(const child of item.children||[])all(child,result);}
        Timer { interval: 500; running: true; onTriggered: {
            const items=[];host.all(field,items);
            const texts=items.filter(i=>i instanceof StrataButton).map(i=>i.text);
            host.check(!texts.some(t=>/Tasks.*performance/i.test(t)),"Retired navigation absent");
            for(const name of ["Terminal","Browser","Files","Update CEDAR","Task Manager"])
                host.check(texts.filter(t=>t===name).length===1,"One existing utility action: "+name);
            host.check(items.filter(i=>i.objectName==="taskManagerLauncher").length===1,"One task launcher");
            host.check(field.page==="overview","Field Station always retains Overview");
            let before=TaskManager.testLaunches;
            items.find(i=>i.objectName==="taskManagerLauncher").clicked();
            host.check(TaskManager.testLaunches===before+1,"Utility button launches standalone app");
            Canopy.openStation("tasks");Canopy.open("system");
            host.check(TaskManager.testLaunches===before+3&&Canopy.stationPage==="overview","Legacy routes cannot open retired page");
            ShellState.locked=true;TaskManager.launch();Canopy.openStation("tasks");
            host.check(TaskManager.testLaunches===before+3,"Launch lock guard");
            ShellState.locked=false;field.width=440;
            console.log("PASS: Field Station Overview, utility actions, retired routes and launch guards");Qt.quit();
        }}
    }
}
''')
    env={**os.environ,'QT_FORCE_STDERR_LOGGING':'1','CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_BACKEND':'software','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(base/'config'),'XDG_STATE_HOME':str(base/'state')}
    try: result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=25)
    except subprocess.TimeoutExpired as error:
        raise SystemExit('Field Station harness timeout: '+str(error.stdout)+' '+str(error.stderr))
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Field Station' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|Failed to load',output):raise SystemExit(output)
    print(next(line for line in output.splitlines() if 'PASS:' in line))
