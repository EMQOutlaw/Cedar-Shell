import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    spacing: 16
    readonly property bool wide: width > 980
    Rectangle {
        Layout.fillWidth: true; implicitHeight: hero.implicitHeight + 40; radius: Theme.cardRadius
        gradient: Gradient { GradientStop { position: 0; color: Qt.alpha(Theme.green, .09) } GradientStop { position: 1; color: Qt.alpha(Theme.teal, .02) } }
        border.color: Qt.alpha(Theme.green, .22)
        ColumnLayout {
            id: hero
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20; spacing: 4
            GlowText { text: Branding.content.name; font.family: Theme.labelFont; font.pixelSize: 40 * Theme.fontScale; font.letterSpacing: 4; color: Theme.green }
            ReadingText { text: Branding.content.acronym; color: Theme.teal }
            ReadingText { text: Branding.content.tagline }
            ReadingText { text: Branding.content.identity; color: Theme.muted }
        }
    }
    // Sections pair two-wide on a large window and stack on a small one; every
    // word of the text is kept — only the geometry consolidates.
    GridLayout {
        Layout.fillWidth: true
        columns: root.wide ? 2 : 1
        columnSpacing: 16; rowSpacing: 16
        component ACell: SettingsSection {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: 0
        }
        ACell {
            heading: "What CEDAR Is"
            ReadingText { text: "CEDAR is a Qt Quick and Quickshell desktop shell for Hyprland. It brings together configurable top bars, the contextual Core, top-opening Canopy panels, Go, Field Station, Settings, audio controls, notifications, OSDs, and a session lock screen. It uses real system services and keeps advanced configuration accessible." }
        }
        ACell {
            heading: "Technical Information"
            Repeater {
                model: [{title:"CEDAR version",value:SettingsInfo.data.version || "Unavailable"}, {title:"Quickshell",value:SettingsInfo.data.versions?.quickshell || "Unavailable"}, {title:"Hyprland",value:SettingsInfo.data.versions?.hyprland || "Unavailable"}, {title:"Qt",value:SettingsInfo.data.versions?.qt || "Unavailable"}, {title:"Installation method",value:SettingsInfo.data.installationMethod || "Unavailable"}, {title:"Configuration",value:Quickshell.shellPath("")}, {title:"Preferences",value:Config.settingsPath}]
                SettingRow { required property var modelData; Layout.fillWidth:true; title:modelData.title; description:modelData.value }
            }
            StationButton { text:"Open configuration folder"; onClicked:Quickshell.execDetached(["xdg-open",Quickshell.shellPath("")]) }
        }
        ACell {
            objectName: "cedarMeaning"
            heading: "Why CEDAR?"
            ReadingText { text: Branding.content.why }
            ReadingText { text: "The technical acronym is the project’s own creation: " + Branding.content.acronym + "."; color: Theme.muted }
        }
        ACell {
            heading: "Credits and Licenses"
            ReadingText { text: "Built with Qt, Quickshell, Hyprland, and Linux system services. The Applications menu includes MIT-licensed Omarchy menu helpers; the required copyright and license notice is in licenses/Omarchy-MIT.txt. Weather data is provided by Open-Meteo. Fonts are discovered locally and are not bundled." }
            ReadingText { text: "Scripture uses the King James Version (KJV). Scripture attribution is separate from software licensing. Redistribution terms differ by jurisdiction; see docs/LICENSES.md. The inherited project did not declare a license for its original source; no new blanket license is asserted here."; color: Theme.muted }
        }
        SettingsSection {
            heading: "Christian Foundation"; accent: Theme.green
            Layout.fillWidth: true; Layout.columnSpan: root.wide ? 2 : 1; Layout.minimumWidth: 0
            ReadingText { text: Branding.content.foundation }
            Repeater {
                model: Branding.content.john.verses
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 6
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.green, .14) }
                    ReadingText { text: modelData.reference; color: Theme.teal }
                    ReadingText { text: "“" + modelData.text + "”" }
                }
            }
            ReadingText { text: Branding.content.john.reference + "\n" + Branding.content.john.translation; color: Theme.muted }
            StationButton { text: "Copy Passage"; onClicked: { Quickshell.clipboardText = Branding.passage(); SettingsInfo.message = "Passage copied with its reference and KJV attribution."; } }
        }
    }
}
