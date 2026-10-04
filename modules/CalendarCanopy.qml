import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id:root
    property int offset:0
    readonly property var month:new Date(clock.date.getFullYear(),clock.date.getMonth()+offset,1)
    readonly property int days:new Date(month.getFullYear(),month.getMonth()+1,0).getDate()
    spacing:12
    SystemClock {id:clock;precision:SystemClock.Minutes}
    GlowText {text:Config.formatTime(clock.date);font.pixelSize:38;color:Theme.green}
    GlowText {text:Config.formatDate(clock.date,true);color:Theme.muted}
    RowLayout {
        StationButton {text:"‹";hint:"Previous month";onClicked:root.offset--}
        GlowText {Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;text:Qt.formatDateTime(root.month,"MMMM yyyy");font.pixelSize:22}
        StationButton {text:"›";hint:"Next month";onClicked:root.offset++}
        StationButton {text:"Today";onClicked:root.offset=0}
    }
    GridLayout {
        Layout.fillWidth:true;columns:7;rowSpacing:5;columnSpacing:5
        Repeater {model:["S","M","T","W","T","F","S"];GlowText {required property string modelData;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;text:modelData;color:Theme.muted}}
        Repeater {
            model:42
            Rectangle {
                required property int index
                readonly property int day:index-root.month.getDay()+1
                readonly property bool today:root.offset===0 && day===clock.date.getDate()
                Layout.fillWidth:true;implicitHeight:32;radius:6;color:today?Qt.alpha(Theme.green,.15):Theme.transparent
                GlowText {anchors.centerIn:parent;text:parent.day>0 && parent.day<=root.days?String(parent.day):"";color:parent.today?Theme.green:Theme.text}
            }
        }
    }
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"Calendar accounts are not connected.";color:Theme.muted}
    SettingsHeading {text:"Timer"}
    RowLayout {
        Layout.fillWidth:true
        StationField {id:minutes;Layout.fillWidth:true;placeholderText:"Minutes (1–1440)";validator:IntValidator {bottom:1;top:1440}}
        StationButton {text:"Start";enabled:minutes.acceptableInput;onClicked:CoreService.timer.start(Number(minutes.text)*60,"Timer")}
    }
    GlowText {text:CoreService.timer.active?Media.elapsed(CoreService.timer.remaining)+(CoreService.timer.paused?" · paused":""):CoreService.timer.completed?"Timer complete":"No active timer";color:Theme.teal}
    RowLayout {
        StationButton {text:CoreService.timer.paused?"Resume":"Pause";enabled:CoreService.timer.active;onClicked:CoreService.timer.toggle()}
        StationButton {text:CoreService.timer.completed?"Dismiss":"Cancel";enabled:CoreService.timer.active || CoreService.timer.completed;onClicked:CoreService.timer.cancel()}
    }
}
