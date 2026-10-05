pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
Singleton {
    id: root
    readonly property var adapters: backend.item?.adapters || []
    readonly property var adapter: backend.item?.adapter || null
    readonly property var devices: backend.item?.devices || []
    readonly property bool available: backend.status === Loader.Ready
    readonly property bool controlsVisible: !ShellState.locked && (["control","settings"].includes(ShellState.panel) || (Canopy.shown && Canopy.topic === "bluetooth"))
    Loader {
        id:backend;asynchronous:true;active:!Config.testMode
        source:Qt.resolvedUrl("optional/BluetoothBackend.qml")
        onStatusChanged:if(status===Loader.Error)root.error="Bluetooth support is unavailable in this Quickshell build."
    }
    onControlsVisibleChanged: if(!controlsVisible){stopScan();cancelPairing();}
    readonly property bool busy: worker.running
    property string error: ""
    property string prompt: ""
    property string message: ""
    property var request: ({})
    property string activeAction: ""
    property string activePath: ""
    property var scanningAdapter: null
    function scan(value) {
        if (!adapter || ShellState.locked || Config.testMode || (value && !controlsVisible)) return;
        if (value) scanningAdapter=adapter;
        adapter.discovering=value;
        if (value) scanTimer.restart(); else { scanTimer.stop(); scanningAdapter=null; }
    }
    function stopScan() { if (scanningAdapter) scanningAdapter.discovering=false; scanningAdapter=null; scanTimer.stop(); }
    function run(action,path,value) {
        if (busy || Config.testMode || ShellState.locked) return;
        error=""; prompt=""; message="Working…";
        activeAction=action; activePath=path; request={action:action,path:path,value:value}; worker.stdinEnabled=true; worker.running=true;
    }
    function cancelPairing() {
        if (!busy || activeAction !== "pair") return;
        if (["pin","passkey","confirm"].includes(prompt)) reply(false, "");
        const device=devices.find(d=>d.dbusPath===activePath);
        if (device) device.cancelPair();
    }
    function reply(accept,value) { worker.write(JSON.stringify({accept:accept,value:value || ""})+"\n"); prompt=""; }
    Timer { id: scanTimer; interval: 30000; onTriggered: root.stopScan() }
    Process {
        id: worker
        command: ["python3",Quickshell.shellPath("scripts/bluetooth.py")]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.request)+"\n"); root.request=({}); }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const r=JSON.parse(line);
                    if (r.prompt !== undefined) { root.prompt=r.prompt; root.message=r.message; }
                    else { root.prompt=""; root.message=r.ok ? "Complete." : ""; root.error=r.error || ""; }
                } catch (_) { root.error="Invalid Bluetooth response."; }
            }
        }
        onExited: (code,status) => { root.request=({}); root.activePath=""; root.activeAction=""; root.prompt=""; if (code!==0) root.error="Bluetooth helper exited ("+code+")."; }
    }
}
