import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
ColumnLayout {
    spacing: 20
    SettingsCard {
        Layout.fillWidth: true
        GlowText { text: Branding.content.name; font.family: Theme.labelFont; font.pixelSize: 44 * Theme.fontScale; color: Theme.green }
        ReadingText { text: Branding.content.acronym }
        ReadingText { text: Branding.content.tagline }
        ReadingText { text: Branding.content.identity; color: Theme.muted }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "What CEDAR Is"
        ReadingText { text: "CEDAR is a Qt Quick and Quickshell desktop shell for Hyprland. It brings together configurable top bars, the contextual Core, top-opening Canopy panels, Go, Field Station, Settings, audio controls, notifications, OSDs, and a session lock screen. It uses real system services and keeps advanced configuration accessible." }
    }
    SettingsCard {
        objectName: "cedarMeaning"
        Layout.fillWidth: true
        title: "Why CEDAR?"
        ReadingText { text: Branding.content.why }
        ReadingText { text: "The technical acronym is the project’s own creation: " + Branding.content.acronym + "."; color: Theme.muted }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Christian Foundation"
        ReadingText { text: Branding.content.foundation }
        Repeater {
            model: Branding.content.john.verses
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                ReadingText { text: modelData.reference; color: Theme.teal }
                ReadingText { text: "“" + modelData.text + "”" }
            }
        }
        ReadingText { text: Branding.content.john.reference + "\n" + Branding.content.john.translation; color: Theme.muted }
        StationButton { text: "Copy Passage"; onClicked: { Quickshell.clipboardText = Branding.passage(); SettingsInfo.message = "Passage copied with its reference and KJV attribution."; } }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Technical Information"
        Repeater {
            model: [{title:"CEDAR version",value:SettingsInfo.data.version || "Unavailable"}, {title:"Quickshell",value:SettingsInfo.data.versions.quickshell || "Unavailable"}, {title:"Hyprland",value:SettingsInfo.data.versions.hyprland || "Unavailable"}, {title:"Qt",value:SettingsInfo.data.versions.qt || "Unavailable"}, {title:"Installation method",value:SettingsInfo.data.installationMethod || "Unavailable"}, {title:"Configuration",value:Quickshell.shellPath("")}, {title:"Preferences",value:Config.settingsPath}]
            SettingRow { required property var modelData; Layout.fillWidth:true; title:modelData.title; description:modelData.value }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Credits and Licenses"
        ReadingText { text: "Built with Qt, Quickshell, Hyprland, and Linux system services. The Go menu includes MIT-licensed Omarchy menu helpers; the required copyright and license notice is in licenses/Omarchy-MIT.txt. Weather data is provided by Open-Meteo. Fonts are discovered locally and are not bundled." }
        ReadingText { text: "Scripture uses the King James Version (KJV). Scripture attribution is separate from software licensing. Redistribution terms differ by jurisdiction; see docs/LICENSES.md. The inherited project did not declare a license for its original source; no new blanket license is asserted here."; color: Theme.muted }
    }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:"Open configuration"; onClicked:Quickshell.execDetached(["xdg-open",Quickshell.shellPath("")]) }
        StationButton { text:"Copy system information"; onClicked:{Quickshell.clipboardText=SettingsInfo.report();SettingsInfo.message="System information copied.";} }
    }
}
