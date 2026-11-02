pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({hostname:"…",kernel:"…",os:"…",version:"Unavailable",versions:{},services:[],theme:"CEDAR",wallpaper:"",themes:[],wallpapers:[]})
    property string error: ""
    property string message: ""
    property string logs: ""
    property string action:"snapshot"
    property var themePreview: null
    readonly property bool busy: worker.busy
    property double lastRead: 0
    // Weekly GitHub update check (owner request): the shell re-checks when the
    // last verified check is older than seven days (or missing), and alerts
    // through the Core when an update is available. Never installs; the check
    // is the same verified action the Updates page runs by hand.
    readonly property double week: 7 * 24 * 3600
    readonly property double startedAt: Date.now()
    property string alertedVersion: ""
    function refresh(force=false) { if (!busy && !Config.testMode && (force || Date.now()-lastRead>15000)) { lastRead=Date.now(); action="snapshot"; worker.send({action:"snapshot"}); } }
    function run(request) { if (!busy && !Config.testMode) { error=""; message="Working…"; action=request.action; worker.send(request); } }
    // Decision points live in onResult (after a real snapshot), so a restart
    // can never network-check before the persisted check date is loaded.
    function dueWeeklyCheck() {
        const status = data.updateStatus;
        if (!status || status.state === "unknown" || !status.checkedAt) return true;
        return Date.now()/1000 - status.checkedAt > week;
    }
    function report() { return "CEDAR "+data.version+"\n"+data.os+"\nKernel "+data.kernel+"\n"+Object.keys(data.versions).map(k=>k+": "+data.versions[k]).join("\n")+"\n"+data.services.map(s=>s.name+": "+s.status).join("\n"); }
    Timer { id:afterRestart; interval:500; onTriggered:root.refresh(true) }
    // Five minutes after startup, and hourly afterwards, take a snapshot. The
    // snapshot result decides: if the last verified check is missing or older
    // than a week it runs the network check; if an update is available and not
    // yet announced (or the last announcement is a day old) it re-announces.
    Timer { id:armWeekly; interval:300000; running:!Config.testMode; onTriggered:root.refresh(true) }
    Timer { interval:3600000; running:!Config.testMode; repeat:true; onTriggered:root.refresh(true) }
    ServiceRequest {
        id: worker; script:"scripts/settings_info.py"; timeoutMs:180000
        onResult: result => { root.error=""; if (result.hostname || result.themes || result.updateStatus) root.data=Object.assign({},root.data,result); if(result.themePreview)root.themePreview=result.themePreview; if(root.action==="theme-apply" || root.action==="theme-restore")root.themePreview=null; root.message=result.message || ""; if (result.logs!==undefined) root.logs=result.logs; if(root.action==="restart"){root.action="snapshot";afterRestart.restart();}
            // Responses are identified by SHAPE (a snapshot carries hostname;
            // a check carries updateStatus alone), not by the retained action
            // string. A real snapshot arms the weekly cadence and queues the
            // network check via ServiceRequest's send-during-result path.
            if (result.hostname) {
                // Automatic checks need: five minutes since shell start (the
                // startup-protection gate), an hour since the last attempt
                // (a failed check's cooldown anchor is persisted attemptedAt),
                // and a due weekly cadence. The Updates page's manual check
                // bypasses all of this — it is explicit.
                const status = result.updateStatus || {};
                const cooldownOk = !status.attemptedAt || Date.now()/1000 - status.attemptedAt > 3600;
                if (Date.now() - root.startedAt > 300000 && cooldownOk && root.dueWeeklyCheck()) worker.send({action:"update-check"});
                announceIfDue(result.updateStatus);
                return;
            }
            announceIfDue(result.updateStatus);
        }
        // An unapplied update re-announces at most once per shell session
        // while it stays available (quiet mode defers without consuming
        // anything); the Updates page still owns the actual upgrade.
        function announceIfDue(update) {
            if (!update || update.state !== "available" || !update.version) return;
            if (update.version === root.alertedVersion) return;
            if (Config.saved.doNotDisturb || Focus.active) return;
            const delivered = CoreService.publish({ id: "update-available", type: "integration", title: "CEDAR update available", subtitle: "Version " + update.version + " is on the " + (update.channel || "stable") + " channel.",
                                  persistent: false, sticky: false, priority: "normal", announce: true, timeout: 8000,
                                  actions: [{ id: "open", label: "Open Updates" }] });
            if (delivered) root.alertedVersion = update.version;
        }
        onFailed: value=>{root.error=value; root.message="";}
    }
}
