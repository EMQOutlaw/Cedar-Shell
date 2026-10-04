import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    spacing:12
    StationToggle {Layout.fillWidth:true;label:"Session clipboard history";description:"Off by default. Captures text and PNG images from now on, up to 20 items. Password-manager sensitive hints are skipped, but unmarked secrets may still be captured. Nothing is written to disk; locking clears all items, including pins.";checked:Config.saved.clipboardHistory;onToggled:value=>Config.set("clipboardHistory",value)}
    StationButton {text:"Clear all";onClicked:Clipboard.clear()}
    GlowText {visible:Clipboard.error!=="";text:Clipboard.error;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.amber}
    Repeater {
        model:Clipboard.items
        ColumnLayout {
            required property var modelData
            property bool reveal:false
            Layout.fillWidth:true
            GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:modelData.label+" · "+Config.formatTime(new Date(modelData.at))+(modelData.pinned?" · PINNED":"");color:Theme.teal}
            GlowText {visible:parent.reveal && modelData.kind==="text";Layout.fillWidth:true;wrapMode:Text.WordWrap;maximumLineCount:6;elide:Text.ElideRight;text:parent.reveal?modelData.payload:""}
            RowLayout {
                StationButton {text:"Copy again";onClicked:Clipboard.copy(modelData)}
                StationButton {text:parent.parent.reveal?"Hide":"Reveal text";visible:modelData.kind==="text";onClicked:parent.parent.reveal=!parent.parent.reveal}
                StationButton {text:modelData.pinned?"Unpin":"Pin";onClicked:Clipboard.pin(modelData.id)}
                StationButton {text:"Delete";onClicked:Clipboard.remove(modelData.id)}
            }
            Rectangle {Layout.fillWidth:true;implicitHeight:1;color:Theme.border}
        }
    }
    GlowText {visible:Clipboard.items.length===0;text:"No captured items.";color:Theme.muted}
}
