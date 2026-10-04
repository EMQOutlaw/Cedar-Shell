pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import ".."
Singleton {
    id: root
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
    readonly property bool busy: worker.running
    property string error: ""
    property string prompt: ""
    property string message: ""
    property var request: ({})
    property string activeAction: ""
    property string activePath: ""
    property var scanningAdapter: null
    function scan(value) {
        if (!adapter) return;
        if (value) scanningAdapter=adapter;
        adapter.discovering=value;
        if (value) scanTimer.restart(); else { scanTimer.stop(); scanningAdapter=null; }
    }
    function stopScan() { if (scanningAdapter) scanningAdapter.discovering=false; scanningAdapter=null; scanTimer.stop(); }
    function run(action,path,value) {
        if (busy || Config.testMode) return;
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
    Connections { target: ShellState; function onPanelChanged() { if (!["control","settings"].includes(ShellState.panel)) { root.stopScan(); root.cancelPairing(); } } }
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
