pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import ".."
import "../components/core/ForestPolicy.js" as Policy

Singleton {
    id: root
    property string state: "AWAKE"
    property var echoes: []
    property var trails: []
    property var observations: {try{return JSON.parse(Config.saved.whisperLedger);}catch(_){return {};}}
    property string whisper: ""
    property string whisperType: ""
    property double whisperUntil: 0
    property double lastWhisper: observations._last || 0
    property double now: Date.now()
    property var lastSignal: null
    property string pendingState: ""
    property int settledSamples: 0
    readonly property string phrase: ({QUIET:"THE WOODS ARE QUIET",AWAKE:"THE LIGHT STAYS ON",FLOW:"SIGNALS THROUGH THE TREES",HUNT:"FOCUSED ON THE HUNT",WATCH:"KEEPING WATCH",EMBER:"SOMETHING NEEDS ATTENTION",REST:"THE FOREST SETTLES"})[state]
    readonly property color accent: state === "EMBER" ? (CoreService.rows.some(r=>r.priority===3) ? Theme.ember : Theme.amber) : state === "WATCH" ? Theme.ember : (["FLOW","HUNT"].includes(state) || SystemStats.networkRate>65536) ? Theme.teal : Theme.green
    readonly property int breathDuration: ["QUIET","REST"].includes(state) ? 6000 : state === "WATCH" ? 2600 : 3800
    readonly property real strength: state === "REST" ? .18 : state === "QUIET" ? .28 : Math.min(.65, .35 + Math.max(0,SystemStats.cpu)*.25)
    readonly property bool urgent: CoreService.rows.some(r=>r.type==="warning" || (r.sticky && r.priority>=2))
    readonly property bool watching: CoreService.recording || CoreService.privacy.length>0
    readonly property int meaningful: CoreService.rows.filter(r=>r.persistent && !["warning","microphone","camera"].includes(r.type)).length
    IdleMonitor { id: idle; enabled: !Config.testMode && !ShellState.locked; timeout: 60 }
    IdleMonitor { id: resting; enabled: !Config.testMode && Config.idleLockSeconds>0 && !ShellState.locked; timeout: Math.max(1,Config.idleLockSeconds-30) }
    IdleMonitor { id: quietLong; enabled: !Config.testMode && !ShellState.locked; timeout: 1200 }
    onWatchingChanged:Qt.callLater(root.update)
    onUrgentChanged:Qt.callLater(root.update)
    function update() {
        now=Date.now();
        const next=Policy.state({warning:urgent,watching:watching,resting:resting.isIdle,performance:PowerProfiles.profile===PowerProfile.Performance,activities:meaningful+(SystemStats.networkRate>262144?1:0),idle:idle.isIdle,cpu:SystemStats.cpu});
        if(next!==pendingState){pendingState=next;settledSamples=0;}
        if(["EMBER","WATCH","REST"].includes(next) || ++settledSamples>=3)state=next;
        const current=CoreService.foreground;
        const announced=current && (current.sticky || current.attentionUntil>now || current.id===CoreService.model.heldId) ? current : null;
        if(lastSignal && lastSignal.id!==announced?.id && Config.saved.forestEchoes)
            echoes=Policy.echo(echoes,lastSignal,now);
        lastSignal=announced;
        echoes=echoes.filter(e=>e.until>now);
        if(whisperUntil<=now)whisper="";
        if(ShellState.locked || !Config.saved.forestWhispers){whisper="";return;}
        if(quietLong.isIdle && Audio.sink?.name?.includes("bluez"))observe("devices","Your Bluetooth audio output is still connected.");
        if(quietLong.isIdle)observe("quiet","The system has been quiet for 20 minutes.");
        const battery=UPower.displayDevice;
        if(battery?.isPresent && !UPower.onBattery && battery.percentage>=.9)
            observe("battery","Battery reached 90%.");
    }
    function observe(type,text) {
        if(!Config.saved.forestWhispers || Config.saved.doNotDisturb || ShellState.locked || ShellState.panel!=="" || CoreService.foreground || now-lastWhisper<600000)return;
        if(!Config.saved["whisper"+type[0].toUpperCase()+type.slice(1)] || now-(observations[type]||0)<21600000)return;
        observations=Object.assign({},observations,{[type]:now,_last:now});
        ledger.setText(JSON.stringify(observations));
        whisper=text;whisperType=type;whisperUntil=now+6000;lastWhisper=now;
    }
    function silenceWhisper(){if(whisperType)Config.set("whisper"+whisperType[0].toUpperCase()+whisperType.slice(1),false);whisper="";}
    function record(kind,label,target="") {
        if(!Config.saved.forestTrails || ShellState.locked)return;
        trails=Policy.trail(trails,{key:kind+"/"+target,label:String(label).slice(0,100),kind:kind,target:target},Date.now());
    }
    function clearTrails(){trails=[];}
    function clearPrivateState(){trails=[];whisper="";echoes=[];lastSignal=null;}
    Connections { target:ShellState; function onLockedChanged(){if(ShellState.locked)root.clearPrivateState();} function onPanelChanged(){if(ShellState.panel && ShellState.panel!=="canopy")root.record("surface",ShellState.panel,ShellState.panel);} }
    Connections { target:Hyprland; function onActiveToplevelChanged(){const w=Hyprland.activeToplevel;if(w)root.record("application",w.lastIpcObject?.class || "Application",String(w.address||""));} }
    Connections { target:Config.saved; function onForestTrailsChanged(){if(!Config.saved.forestTrails)root.clearTrails();} function onForestEchoesChanged(){if(!Config.saved.forestEchoes)root.echoes=[];} }
    FileView {
        id: ledger
        path: Config.stateDir + "/whispers.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data=JSON.parse(text());
                if(data && typeof data === "object" && !Array.isArray(data)) {
                    root.observations=data;
                    root.lastWhisper=Number(data._last || 0);
                }
            } catch (_) {}
        }
    }
    Timer { interval:1000; running:(Config.saved.coreEnabled || Canopy.shown) && !ShellState.locked; repeat:true; triggeredOnStart:true; onTriggered:root.update() }
}
