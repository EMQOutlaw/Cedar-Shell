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
    readonly property bool busy: worker.running
    property double lastRead: 0
    function refresh(force=false) { if (!busy && !Config.testMode && (force || Date.now()-lastRead>15000)) { lastRead=Date.now(); worker.send({action:"snapshot"}); } }
    function run(request) { if (!busy && !Config.testMode) { error=""; message="Working…"; action=request.action; worker.send(request); } }
    function report() { return "CEDAR "+data.version+"\n"+data.os+"\nKernel "+data.kernel+"\n"+Object.keys(data.versions).map(k=>k+": "+data.versions[k]).join("\n")+"\n"+data.services.map(s=>s.name+": "+s.status).join("\n"); }
    Timer { id:afterRestart; interval:500; onTriggered:root.refresh(true) }
    ServiceRequest {
        id: worker; script:"scripts/settings_info.py"
        onResult: result => { root.error=""; if (result.hostname || result.themes) root.data=Object.assign({},root.data,result); root.message=result.message || ""; if (result.logs!==undefined) root.logs=result.logs; if(root.action==="restart"){root.action="snapshot";afterRestart.restart();} }
        onFailed: value=>{root.error=value; root.message="";}
    }
}
