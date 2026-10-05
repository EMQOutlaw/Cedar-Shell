#!/usr/bin/env python3
"""Exercise the production lock composition with fake PAM and lock transports.

Only native window/lock/idle/PAM boundaries are replaced in a temporary copy.
The actual nested delegate, controller binding, terminal and submission handlers
are used. Nothing calls PAM, creates a Wayland lock or suspends the machine.
Use --source FILE to verify a historical LockScreen regression.
"""
from pathlib import Path
import argparse,os,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path);args=parser.parse_args()
with tempfile.TemporaryDirectory(prefix='cedar-lock-wiring-') as tmp:
    base=Path(tmp);source=base/'shell'
    shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log','*.png'))
    (base/'runtime').mkdir(mode=0o700)
    qml=(args.source or ROOT/'modules/LockScreen.qml').read_text()
    controller=re.search(r'LockAuth\s*\{\s*id:\s*(\w+)',qml).group(1)
    qml=qml.replace('import Quickshell.Wayland\n','')
    qml=qml.replace('PamContext {','FakePam {').replace('IdleMonitor {','FakeIdle {')
    qml=qml.replace('PanelWindow {','FloatingWindow {').replace('WlSessionLock {','FakeLock {').replace('WlSessionLockSurface {','Rectangle {')
    qml='\n'.join(line for line in qml.splitlines() if 'WlrLayershell.' not in line and 'exclusionMode:' not in line)
    qml=qml.replace(' && !Config.testMode','').replace('!Config.testMode && ','')
    qml=qml.replace('Quickshell.execDetached(["systemctl", "suspend"]);','throw new Error("Unexpected suspend in wiring test");')
    qml=qml.replace('id: root','id: root\n    property alias testPam: pam\n    property alias testLock: lock\n    property alias testController: '+controller,1)
    (source/'modules/LockScreen.qml').write_text(qml)
    (source/'modules/FakeIdle.qml').write_text('import QtQuick\nQtObject { property bool enabled:false; property int timeout:0; property bool respectInhibitors:false; property bool isIdle:false }')
    (source/'modules/FakePam.qml').write_text('''import QtQuick
QtObject {
    property string config:""
    property string configDirectory:""
    property bool active:false
    property bool responseRequired:false
    property bool responseVisible:false
    property string message:""
    property int starts:0
    property int responses:0
    property bool correctResponse:false
    signal completed(int result)
    signal error(int error)
    signal pamMessage()
    function start(){starts++;active=true;return true;}
    function abort(){active=false;responseRequired=false;}
    function respond(value){responses++;correctResponse=value==="test-response";responseRequired=false;}
    function prompt(){message="Password:";responseRequired=true;pamMessage();}
    function finish(result){active=false;responseRequired=false;completed(result);}
}
''')
    (source/'modules/FakeLock.qml').write_text('''import QtQuick
Item {
    id:host
    default property Component surface
    property bool locked:false
    readonly property bool secure:locked
    function view(index){return loaders.objectAt(index).item.children[0];}
    property Instantiator loaders: Instantiator {
        model:host.locked ? 2:0
        delegate:Loader {sourceComponent:host.surface;width:1366;height:768}
    }
}
''')
    for name in ('FakePam','FakeIdle','FakeLock'):
        with (source/'modules/qmldir').open('a') as f:f.write('\n'+name+' 1.0 '+name+'.qml\n')
    (source/'preview.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Services.Pam
import "."
import "modules"
ShellRoot {
    id:test
    LockScreen {id:screen}
    function check(ok,label){if(!ok){console.error("FAIL: "+label);Qt.exit(1);throw new Error(label);}}
    Timer {
        interval:200;running:true
        onTriggered:{ShellState.lock(false);testRun.start();}
    }
    Timer {
        id:testRun;interval:200
        onTriggered:{
            const first=screen.testLock.view(0),second=screen.testLock.view(1),pam=screen.testPam,auth=screen.testController;
            test.check(first.auth===auth && second.auth===auth,"Both dynamic surfaces receive the production controller");
            test.check(first.terminal.auth===auth && second.terminal.auth===auth,"Controller reaches both password terminals");
            test.check(auth.enabled,"Controller enabled by lock state");
            second.terminal.field.text="discarded-on-other-monitor";
            first.terminal.field.text="test-response";
            first.terminal.field.accepted();
            test.check(pam.starts===1 && pam.responses===0 && auth.hasPending,"Enter starts PAM and queues password");
            test.check(first.terminal.field.text==="" && second.terminal.field.text==="","Submission clears both monitors");
            test.check(!first.terminal.field.enabled && !second.terminal.field.enabled,"Both fields disabled while checking");
            pam.prompt();
            test.check(pam.responses===1 && pam.correctResponse && auth.pendingResponse==="","Prompt receives password exactly once");
            pam.finish(PamResult.Failed);
            test.check(ShellState.locked && screen.testLock.locked,"Failure keeps session locked");
            test.check(ShellState.securedUnlocks===0,"Failed authentication never validates locker adoption");
            test.check(first.terminal.field.enabled && second.terminal.field.enabled,"Failure allows retry on either monitor");
            test.check(auth.status.includes("not accepted"),"Useful failure message reaches shared controller");
            second.terminal.field.text="test-response";
            second.terminal.submit();pam.prompt();
            test.check(pam.starts===2 && pam.responses===2 && pam.correctResponse,"Other monitor can retry successfully");
            pam.finish(PamResult.Success);
            test.check(!ShellState.locked && !screen.testLock.locked,"Only successful authentication releases lock");
            test.check(ShellState.securedUnlocks===1,"A secure lock plus successful PAM records one validation");
            test.check(auth.pendingResponse==="" && !auth.enabled,"Unlock clears and disables controller");
            console.log("PASS: production lock wiring, two dynamic surfaces, Enter, failure and retry");Qt.quit();
        }
    }
}
''')
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(base/'runtime'),'XDG_CONFIG_HOME':str(base/'config')}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=15)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: production lock wiring' not in output or re.search(r'FAIL:|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign',output):
        print(output);raise SystemExit(1)
    print('PASS: production lock wiring, two dynamic surfaces, Enter, failed authentication and retry; no real PAM or session lock')
