pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({profiles:[],profile:"",nightlight:null,errors:{}})
    property string error: ""
    readonly property bool busy: worker.running
    function refresh() { if (!busy && !Config.testMode) worker.send({action:"snapshot"}); }
    function run(request) { if (!busy && !Config.testMode) { error=""; worker.send(request); } }
    ServiceRequest {
        id: worker; script: "scripts/control.py"
        onResult: value => root.data=value
        onFailed: value => root.error=value
    }
    Connections { target: ShellState; function onPanelChanged() { if (["control","settings","canopy"].includes(ShellState.panel)) root.refresh(); } }
    Timer { interval: 10000; running: ["control","settings","canopy"].includes(ShellState.panel) && !Config.testMode; repeat: true; onTriggered: root.refresh() }
}
