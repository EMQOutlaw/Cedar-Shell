import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property string highlightKey: ""
    property string shortcut: "SUPER + ALT + C"
    readonly property var choices: [
        {
            name: "",
            label: "Follow main display"
        }
    ].concat(Quickshell.screens.map(s => ({
                name: s.name,
                label: s.name
            })))
    readonly property var bindings: DesktopSettings.data.bindings.filter(b => b.arg === "qs -c cedar ipc call core toggle")
    spacing: 12
    SettingsCard {
        Layout.fillWidth: true
        GlowText {
            text: "CEDAR CORE"
            color: Theme.green
            font.family: Theme.labelFont
            font.pixelSize: 28
        }
        GlowText {
            text: "A little awareness. Exactly when it matters."
            color: Theme.muted
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        StationButton {
            text: "Open Core"
            enabled: CoreService.enabled
            onClicked: CoreService.expand()
        }
    }
    SettingRow {
        Layout.fillWidth: true
        title: "Core display"
        description: "Only one display hosts Core. A disconnected preference falls back to an available output."
        StationCombo {
            Layout.fillWidth: true
            model: root.choices
            textRole: "label"
            currentIndex: Math.max(0, root.choices.findIndex(c => c.name === Config.saved.coreMonitor))
            onActivated: Config.set("coreMonitor", root.choices[currentIndex].name)
        }
    }
    SettingsHeading {
        text: "Keyboard access"
    }
    GlowText {
        text: root.bindings.length ? "Current shortcut: " + root.bindings.map(b => b.keys).join(", ") : "Open Go and search for CEDAR Core, or assign a dedicated shortcut below. Super+Space keeps its existing action."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        StationField {
            Layout.fillWidth: true
            text: root.shortcut
            placeholderText: "SUPER + ALT + C"
            Accessible.name: "Core shortcut"
            onCommit: value => root.shortcut = value.toUpperCase()
        }
        StationButton {
            text: "Assign shortcut"
            enabled: !DesktopSettings.busy && root.shortcut !== ""
            onClicked: DesktopSettings.apply({
                action: "binding",
                keys: root.shortcut,
                command: "qs -c cedar ipc call core toggle",
                description: "CEDAR Core"
            })
        }
    }
    GlowText {
        visible: DesktopSettings.error !== "" || DesktopSettings.message !== ""
        text: DesktopSettings.error || DesktopSettings.message
        color: DesktopSettings.error ? Theme.amber : Theme.teal
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
    GlowText {
        text: "Assignment reads the live bindings and refuses conflicts. In Core, use Tab for controls, arrows for activities, Enter to activate, and Escape to collapse."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
    SettingsFields {
        Layout.fillWidth: true
        page: "core"
        highlightKey: root.highlightKey
    }
    StationButton { text:"Open Canopy";enabled:Config.saved.canopyEnabled;onClicked:Canopy.context() }
    SettingsHeading {
        text: "Connected sources"
    }
    GlowText {
        text: "Recording comes from active gpu-screen-recorder processes. Saved screenshots come from Omarchy’s notifications. Timers belong to CEDAR. Updates are checked only on request. Download and plugin progress require an explicit publisher; no global progress is guessed."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
    GlowText {
        visible: CoreService.probe.error !== ""
        text: CoreService.probe.error
        color: Theme.amber
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
}
