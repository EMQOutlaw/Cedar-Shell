import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    spacing:12
    RowLayout {StationButton {text:"Clear history";onClicked:NoticeStore.clear()} StationButton {text:Config.saved.doNotDisturb?"DND on":"DND off";checked:Config.saved.doNotDisturb;onClicked:Config.set("doNotDisturb",!Config.saved.doNotDisturb)} }
    GlowText {visible:NoticeStore.history.length===0;text:"No notifications in this session.";color:Theme.muted}
    Repeater {
        model:NoticeStore.history.slice(0,60)
        ColumnLayout {
            required property var modelData
            readonly property var liveNotice:NoticeStore.live.find(n=>n.id===modelData.id) || null
            Layout.fillWidth:true
            GlowText {Layout.fillWidth:true;text:modelData.app+" · "+(modelData.timestamp?Config.formatTime(new Date(modelData.timestamp)):modelData.time);color:Theme.teal;elide:Text.ElideRight}
            GlowText {Layout.fillWidth:true;text:modelData.summary;wrapMode:Text.WordWrap;color:modelData.critical?Theme.ember:Theme.text}
            GlowText {Layout.fillWidth:true;text:modelData.body;wrapMode:Text.WordWrap;maximumLineCount:6;elide:Text.ElideRight;color:Theme.muted}
            Flow {
                Layout.fillWidth:true;spacing:6
                Repeater {model:parent.parent.liveNotice?.actions || [];StationButton {required property var modelData;text:modelData.text;onClicked:modelData.invoke()}}
                StationButton {text:parent.parent.liveNotice?"Dismiss":"Remove";onClicked:{NoticeStore.dismiss(modelData.id);NoticeStore.history=NoticeStore.history.filter(n=>n.id!==modelData.id);}}
            }
            Rectangle {Layout.fillWidth:true;implicitHeight:1;color:Theme.border}
        }
    }
}
