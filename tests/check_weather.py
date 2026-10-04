#!/usr/bin/env python3
"""Isolated QML checks; no location or forecast requests are sent."""
from pathlib import Path
import os,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar weather ') as tmp:
    p=Path(tmp);source=p/'shell';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log'))
    runtime=p/'runtime';runtime.mkdir(mode=0o700)
    (source/'check.qml').write_text('''import QtQuick
import Quickshell
import "."
import "services"
import "modules"
ShellRoot {
    FloatingWindow {
        id:win;visible:true;implicitWidth:440;implicitHeight:700
        WeatherLocationSettings { width:440 }
        property int step:0
        function check(ok,message){if(!ok){console.error("FAIL: "+message);Qt.exit(1);}}
        Timer {
            running:true;repeat:true;interval:180
            onTriggered:{
                if(win.step===0){
                    win.check(!WeatherLocation.automatic && !Weather.configured && Config.localOnly,"Private defaults block automatic location and forecasts");
                    Config.set("localOnly",false);Config.set("weatherEnabled",true);Config.set("weatherAutomatic",true);
                    win.check(WeatherLocation.automatic,"Explicit permissions enable automatic location");
                    WeatherLocation.detected={latitude:10,longitude:20,name:"Detected City",stale:false};
                } else if(win.step===1){
                    win.check(Weather.configured && WeatherLocation.label==="Detected City","Auto coordinates reach existing weather service");
                    WeatherLocation.select({latitude:0,longitude:0,name:"Chosen City"});
                } else if(win.step===2){
                    win.check(Weather.configured && !WeatherLocation.automatic && WeatherLocation.label==="Chosen City","City selection persists and overrides IP, including zero coordinates");
                    WeatherLocation.detected={latitude:30,longitude:40,name:"Late result"};
                    win.check(WeatherLocation.latitude==="0","Late detection never replaces manual city");
                    Config.set("longitude", "");
                } else if(win.step===3){
                    win.check(!Weather.configured && !WeatherLocation.automatic,"Incomplete manual coordinates do not silently use another city");
                    WeatherLocation.useAutomatic();
                } else if(win.step===4){
                    win.check(WeatherLocation.automatic && Weather.configured,"Return to automatic mode");
                    Config.set("weatherAutomatic",false);
                } else if(win.step===5){
                    win.check(!Weather.configured && !WeatherLocation.automatic,"Off stops automatic forecast location");
                    console.log("PASS: automatic weather, city override, late results, zero coordinates and off switch");Qt.quit();
                }
                win.step++;
            }
        }
    }
}
''')
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(p/'config'),'XDG_STATE_HOME':str(p/'state'),'XDG_CACHE_HOME':str(p/'cache')}
    result=subprocess.run(['qs','-p',str(source/'check.qml')],env=env,capture_output=True,text=True,timeout=10)
    out=result.stdout+result.stderr
    if result.returncode or 'PASS: automatic weather' not in out or re.search('FAIL:|TypeError|ReferenceError|Binding loop|Unable to assign',out):print(out);raise SystemExit(1)
    print('PASS: automatic weather, city override, late results, zero coordinates and off switch (no network requests)')
