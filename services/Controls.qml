pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({profiles:[],profile:"",nightlight:null,errors:{}})
    property string error: ""
    // Advances when a reply has been parsed (or failed): the moment data is
    // final. `busy` can drop before the reply is parsed, so verify on this.
    property int generation: 0
    // Synchronous: true from a request until its process has exited. A
    // request made while busy is queued by ServiceRequest and runs next.
    readonly property bool busy: worker.busy
    function refresh() { if (!Config.testMode && !busy) worker.send({action:"snapshot"}); }
    function run(request) { if (!Config.testMode) { error=""; worker.send(request); } }
    ServiceRequest {
        id: worker; script: "scripts/control.py"
        onResult: value => { root.data=value; root.generation++; }
        onFailed: value => { root.error=value; root.generation++; }
    }
    Connections { target: ShellState; function onPanelChanged() { if (["control","settings","canopy"].includes(ShellState.panel)) root.refresh(); } }
    Timer { interval: 10000; running: ["control","settings","canopy"].includes(ShellState.panel) && !Config.testMode; repeat: true; onTriggered: root.refresh() }
}
