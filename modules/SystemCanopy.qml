import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property bool active:false
    property var gpus:[]
    property string error:""
    spacing:12
    GlowText {text:Forest.state+" · "+Forest.phrase;color:Forest.accent;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    ActivityTrace {Layout.fillWidth:true;active:root.active;value:SystemStats.cpu}
    Repeater {
        model:[{name:"CPU",value:SystemStats.cpu<0?"Unavailable":Math.round(SystemStats.cpu*100)+"%"},{name:"Memory",value:SystemStats.memoryLabel},{name:"Temperature",value:SystemStats.temperature<0?"Unavailable":SystemStats.temperature+"°C"},{name:"Storage",value:SystemStats.disk<0?"Unavailable":Math.round(SystemStats.disk*100)+"% used"},{name:"Uptime",value:SystemStats.uptime},{name:"Network",value:Network.label}]
        SettingRow {required property var modelData;Layout.fillWidth:true;title:modelData.name;description:modelData.value}
    }
    SettingsHeading {text:"Performance instrument"}
    Repeater {model:root.gpus;SettingRow {required property var modelData;Layout.fillWidth:true;title:modelData.name;description:"GPU "+(modelData.load??"—")+"% · "+(modelData.temperature??"—")+"°C\nVRAM "+(modelData.used??"—")+" / "+(modelData.total??"—")+" MiB"} }
    GlowText {visible:!root.gpus.length;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:root.error || "GPU telemetry is unavailable for this device.";color:Theme.muted}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"FPS and 1% lows need a game-side telemetry provider. They are not inferred from monitor refresh or GPU load.";color:Theme.muted}
    StationButton {text:"Open System Health";onClicked:{ShellState.settingsPage="system";ShellState.open("settings");}}
    function refresh(){if(root.active && !Config.testMode && !reader.running)reader.send({});}
    onActiveChanged:if(active)refresh()
    Component.onCompleted:refresh()
    ServiceRequest {id:reader;script:"scripts/performance.py";onResult:value=>{root.gpus=value.gpus;root.error="";};onFailed:value=>{root.gpus=[];root.error=value;}}
    Timer {interval:5000;running:root.active;repeat:true;onTriggered:root.refresh()}
}
