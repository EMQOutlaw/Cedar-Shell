pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property int step: 0
    property bool launcher: true
    property bool trailwatch: false
    property var plan: null
    property var loginPlan: null
    property var status: ({stage:"not inspected"})
    property string error: ""
    property string operation: ""
    readonly property bool busy: request.running
    onLauncherChanged: plan=null
    onTrailwatchChanged: plan=null
    function run(action, approved=false) {
        if (busy || ShellState.locked || Config.testMode) return;
        error="";operation=action;
        request.send({action:action,approved:approved,launcher:launcher,trailwatch:trailwatch,digest:plan?.digest || "",loginDigest:loginPlan?.digest || ""});
    }
    ServiceRequest {
        id:request;script:"scripts/setup.py";arguments:["--request"];timeoutMs:240000
        onResult: value => { if(root.operation==="plan")root.plan=value;else if(root.operation==="activation-plan")root.loginPlan=value;else root.status=value; }
        onFailed: message => {root.error=message;if(root.operation==="plan" || root.operation==="try")root.plan=null;}
    }
}
