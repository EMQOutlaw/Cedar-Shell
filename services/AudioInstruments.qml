pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({outputs:[],inputs:[],streams:[],scenes:[],eq:{available:false,bands:[],filters:[],reason:"Checking audio capabilities…"},spectrumAvailable:false})
    property string error: ""
    readonly property bool active: Canopy.shown && !Canopy.peeking && Canopy.topic==="audio"
    readonly property bool busy: request.running
    function run(value){if(Config.testMode || busy)return;error="";request.send(value);}
    function refresh(){run({action:"snapshot"});}
    onActiveChanged: if(active)refresh()
    ServiceRequest { id:request;script:"scripts/audio_instruments.py";onResult:value=>root.data=value;onFailed:message=>{root.error=message;root.data=Object.assign({},root.data,{streams:[],eq:{available:false,bands:[],filters:[],reason:"Audio processing unavailable. " + message}});} }
    Connections { target:Audio;function onStreamsChanged(){if(root.active)refreshDelay.restart();} function onSinkChanged(){if(root.active)refreshDelay.restart();} }
    Timer { id:refreshDelay;interval:150;onTriggered:root.refresh() }
}
