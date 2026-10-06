import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema

ColumnLayout {
    id: root
    property bool active: false
    property string highlightKey: ""
    function spec(key) { return Schema.fields.find(f => f.key === key); }
    spacing: 16
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: root.active }

    Rectangle {
        Layout.fillWidth: true; implicitHeight: hero.implicitHeight + 40; radius: Theme.cardRadius
        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Qt.alpha(Theme.green, .08) } GradientStop { position: 1; color: Qt.alpha(Theme.teal, .02) } }
        border.color: Qt.alpha(Theme.green, .22)
        ColumnLayout {
            id: hero
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20; spacing: 2
            GlowText { text: "EVERY CEDAR CLOCK"; color: Theme.teal; font.pixelSize: 10; font.letterSpacing: 1.8 }
            GlowText { text: Config.formatTime(clock.date); font.family: Theme.labelFont; font.pixelSize: Math.round(56 * Theme.fontScale); color: Theme.green }
            GlowText { Layout.fillWidth: true; text: Config.formatDate(clock.date); color: Theme.text; wrapMode: Text.WordWrap }
            GlowText { text: "Bar, Field Station, Core, Canopy and Trailwatch all follow this format."; color: Theme.muted; font.pixelSize: Theme.small; Layout.topMargin: 6; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    SettingsSection {
        objectName: "clock24"
        heading: "Clock"
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: [{value:false, title:"12 hour", sample:"h:mm AP"}, {value:true, title:"24 hour", sample:"HH:mm"}]
                StationButton {
                    id: choice
                    required property var modelData
                    readonly property bool inUse: Config.clock24 === modelData.value
                    Layout.fillWidth: true; implicitHeight: 72; checked: inUse
                    Accessible.name: modelData.title + " clock" + (inUse ? ", in use" : "")
                    onClicked: Config.set("clock24", modelData.value)
                    background: Rectangle { radius: 10; color: choice.inUse ? Qt.alpha(Theme.green, .07) : Theme.background; border.width: choice.inUse || choice.visualFocus ? 2 : 1; border.color: choice.inUse || choice.visualFocus ? Theme.green : choice.hovered ? Qt.alpha(Theme.teal, .45) : Qt.alpha(Theme.teal, .14) }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text { text: Qt.formatTime(clock.date, choice.modelData.sample); font.family: Theme.labelFont; font.pixelSize: Math.round(24 * Theme.fontScale); color: choice.inUse ? Theme.green : Theme.text }
                        Text { text: choice.modelData.title.toUpperCase(); font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
                    }
                }
            }
        }
    }

    SettingsSection {
        objectName: "dateStyle"
        heading: "Date"
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 1 : 3; columnSpacing: 10; rowSpacing: 10
            Repeater {
                model: [{value:"month-first", title:"Month first", sample:"MMM d, yyyy"}, {value:"day-first", title:"Day first", sample:"d MMM yyyy"}, {value:"iso", title:"Year first · ISO", sample:"yyyy-MM-dd"}]
                StationButton {
                    id: style
                    required property var modelData
                    readonly property bool inUse: Config.dateStyle === modelData.value
                    Layout.fillWidth: true; implicitHeight: 72; checked: inUse
                    Accessible.name: modelData.title + " date format" + (inUse ? ", in use" : "")
                    onClicked: Config.set("dateStyle", modelData.value)
                    background: Rectangle { radius: 10; color: style.inUse ? Qt.alpha(Theme.green, .07) : Theme.background; border.width: style.inUse || style.visualFocus ? 2 : 1; border.color: style.inUse || style.visualFocus ? Theme.green : style.hovered ? Qt.alpha(Theme.teal, .45) : Qt.alpha(Theme.teal, .14) }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text { text: Qt.formatDate(clock.date, style.modelData.sample); font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); color: style.inUse ? Theme.green : Theme.text }
                        Text { text: style.modelData.title.toUpperCase(); font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
                    }
                }
            }
        }
        SettingControl { Layout.fillWidth: true; spec: root.spec("showWeekday"); highlightKey: root.highlightKey }
        SettingControl { Layout.fillWidth: true; spec: root.spec("barShowDate"); highlightKey: root.highlightKey }
    }
}
