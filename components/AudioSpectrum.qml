import QtQuick
import Quickshell
import Quickshell.Io
import ".."
Rectangle {
    id:root
    property bool active:false
    property var levels:[]
    property string error:""
    implicitHeight:76
    color:Theme.transparent
    Process {
        id:worker
        command:["python3",Quickshell.shellPath("scripts/spectrum.py")]
        running:root.active && root.visible && !Theme.reducedMotion && !Config.testMode
        stdout:SplitParser { onRead:data=>{const values=data.trim().split(";").filter(s=>s!=="").map(Number);if(values.length===24 && values.every(v=>Number.isFinite(v)))root.levels=values.map(v=>Math.max(0,Math.min(1,v/100)));} }
        stderr:StdioCollector {onStreamFinished:if(text.trim())root.error=text.trim().slice(0,160)}
    }
    Row {
        anchors.fill:parent;spacing:3
        Repeater {
            model:24
            Rectangle {
                required property int index
                width:(root.width-69)/24; height:Math.max(1,(root.levels[index]||0)*(root.height-18));y:root.height-height
                radius:2;color:Qt.alpha(Theme.teal,.55)
                Behavior on height { enabled:root.active && !Theme.reducedMotion;NumberAnimation {duration:40;easing.type:Easing.Linear} }
                Behavior on y { enabled:root.active && !Theme.reducedMotion;NumberAnimation {duration:40;easing.type:Easing.Linear} }
            }
        }
    }
    GlowText {visible:root.error!=="";text:root.error;color:Theme.muted;width:parent.width;wrapMode:Text.WordWrap;font.pixelSize:10}
}
