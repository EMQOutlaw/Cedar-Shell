#!/usr/bin/env python3
"""Exercise identity content offline, narrow/wide, scaling, fonts and persistence."""
from pathlib import Path
import json,os,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar identity ') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700);config=p/'config/cedar';config.mkdir(parents=True)
    (config/'settings.json').write_text(json.dumps({'unknownExtension':{'preserved':True},'reducedMotion':True,'interfaceFont':'CEDAR intentionally missing font','fontScale':1.5}))
    shots=Path(sys.argv[1]) if len(sys.argv)>1 else p/'shots';shots.mkdir(parents=True,exist_ok=True)
    (source/'identity.qml').write_text('''import QtQuick
import QtQuick.Layouts
import Quickshell
import "."
import "modules"
import "components"
ShellRoot {
    FloatingWindow {
        id: win; visible: true; implicitWidth: 1000; implicitHeight: 900
        color: Theme.background
        FieldStation { id: station; width: 940; active: visible }
        AboutSettings { id: about; width: 940; visible: false }
        property int step: 0
        function check(ok, message) { if (!ok) { console.error("FAIL: "+message);Qt.exit(1); } }
        function texts(item, result) {
            if (item instanceof ReadingText) result.push(item);
            for (const child of item.children || []) texts(child,result);
        }
        Timer {
            running: true; repeat: true; interval: 450
            onTriggered: {
                if (win.step === 0) {
                    Config.set("clock24",false);
                    win.check(Theme.labelFont === "sans-serif", "Missing font fallback");
                    win.check(Theme.reducedMotion, "Reduced Motion enabled");
                } else if (win.step === 1) {
                    const all=[];win.texts(station,all);
                    win.check(all.some(t=>t.text.includes(Branding.content.psalm.text)),"Complete Psalm in Field Station");
                    station.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/field-wide.png"));
                    station.width=360;
                } else if (win.step === 2) {
                    const all=[];win.texts(station,all);
                    all.forEach(t=>win.check(t.width<=360 && t.height>=t.contentHeight-1,"Narrow Field Station text not clipped"));
                    station.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/field-narrow-scaled.png"));
                    station.visible=false;about.visible=true;
                } else if (win.step === 3) {
                    const all=[];win.texts(about,all);
                    Branding.content.john.verses.forEach(v=>win.check(all.some(t=>t.text.includes(v.text)),"Full verse rendered: "+v.reference));
                    const copy=Branding.passage();
                    win.check(copy.includes(Branding.content.john.verses[1].text) && copy.includes("John 3:16–17") && copy.includes("King James Version (KJV)"),"Copy Passage complete with attribution");
                    Quickshell.clipboardText=copy;
                    win.check(Quickshell.clipboardText===copy,"Clipboard receives full passage");
                    about.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/about-wide-scaled.png"));
                    about.width=360;
                } else if (win.step === 4) {
                    const all=[];win.texts(about,all);
                    all.forEach(t=>win.check(t.width<=360 && t.height>=t.contentHeight-1,"Narrow About text not clipped"));
                    about.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/about-narrow-scaled.png"));
                } else { console.log("PASS: identity offline, complete verses, copy, fonts, scaling and Reduced Motion");Qt.quit(); }
                win.step++;
            }
        }
    }
}
''')
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'identity.qml')],env=env,capture_output=True,text=True,timeout=15)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: identity offline' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|FAIL:',output):print(output);raise SystemExit(1)
    saved=json.loads((config/'settings.json').read_text())
    assert saved['unknownExtension']=={'preserved':True} and saved['clock24'] is False
    print('PASS: identity offline, full KJV verses, clipboard, narrow/wide scaling, missing fonts, Reduced Motion and unknown-key persistence')
