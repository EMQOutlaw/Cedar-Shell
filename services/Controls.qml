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
    // Only the controls that display power/night-light state need polling.
    // Settings is a separate window; ShellState.panel does not own its lifetime.
    // Transactions and Trailwatch retain their explicit on-demand refreshes.
    readonly property bool observed: !ShellState.locked && !Config.testMode && (
        ShellState.panel === "control" ||
        (Canopy.shown && Canopy.topic === "quick") ||
        (SettingsService.open && ["power", "profiles"].includes(SettingsService.page)))
    Timer { interval: 10000; running: root.observed; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
