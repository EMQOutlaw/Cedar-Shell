#!/usr/bin/env python3
"""Exercise the real async service from Quickshell using isolated user directories."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-theming-ui-') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('.git','__pycache__'))
    bin_dir=p/'bin';bin_dir.mkdir();(bin_dir/'foot').write_text('#!/bin/sh\nif [ "$1" = "--version" ]; then echo "foot version: 1.28.0"; fi\nexit 0\n');(bin_dir/'foot').chmod(0o700)
    cfg=p/'config';(cfg/'foot').mkdir(parents=True);(cfg/'foot/foot.ini').write_text('[main]\nterm=xterm-256color\n')
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    (source/'preview.qml').write_text('''import QtQuick
import Quickshell
import "modules"
ShellRoot {
 FloatingWindow {
  id: window
  implicitWidth:1250; implicitHeight:850; visible:true
  ApplicationThemingSettings { id:page; width:1200 }
  property int step:0
  Timer {
   interval:150; running:true; repeat:true
   onTriggered: {
    if (page.busy || page.stateData.settings===undefined) return;
    if (window.step===0) {page.setOption("enabled",true);page.setOption("inherit",false);page.setOption("apps",["foot"]);page.request("preview");window.step++;}
    else if (window.step===1) {if (!page.plan || page.plan.reports.some(r=>r.status==="Blocked")) {console.error("FAIL preview: "+page.message);Qt.exit(1);return;}page.request("apply");window.step++;}
    else if (window.step===2) {if (!page.stateData.canRestore) {console.error("FAIL apply: "+page.message);Qt.exit(1);return;}page.request("reset");window.step++;}
    else {console.log("PASS: Themings async Preview Apply Reset");Qt.quit();}
   }
  }
  Timer { interval:20000; running:true; onTriggered:{console.error("FAIL timeout: "+page.message);Qt.exit(1);} }
 }
}''')
    env={**os.environ,'PATH':str(bin_dir)+os.pathsep+os.environ.get('PATH',''),'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software',
         'XDG_CONFIG_HOME':str(cfg),'XDG_DATA_HOME':str(p/'data'),'XDG_STATE_HOME':str(p/'state'),'XDG_RUNTIME_DIR':str(runtime)}
    r=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=25)
    output=r.stdout+r.stderr
    if r.returncode or 'PASS: Themings async Preview Apply Reset' not in output or re.search('ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign',output):
        print(output);raise SystemExit(1)
    assert (cfg/'foot/foot.ini').read_text()=='[main]\nterm=xterm-256color\n'
    assert not (cfg/'cedar/application-theming.json').exists()
    print('PASS: Real QML-to-Python Preview, Apply, Reset and exact original configuration restoration.')
