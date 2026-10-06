import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property string highlightKey: ""
    readonly property var choices: [{name: "", label: "Follow main display"}].concat(Quickshell.screens.map(s => ({name: s.name, label: s.name})))
    readonly property var shortcuts: (DesktopSettings.data.bindings || []).filter(b => /ipc call core toggle$/.test(b.arg || ""))
    spacing: 16

    SettingsSection {
        emphasis: true; accent: Theme.green
        heading: "A little awareness. Exactly when it matters."
        caption: "Core lives at the center of the bar: a quiet clock at rest, live controls and signals when something happens."
        badge: Config.saved.coreEnabled ? "On" : "Off"; badgeColor: Config.saved.coreEnabled ? Theme.green : Theme.muted
        SettingsFields { page: "core"; groups: ["Core"]; cards: false; highlightKey: root.highlightKey; Layout.fillWidth: true }
        SettingRow {
            objectName: "coreMonitor"; Layout.fillWidth: true; enabled: Config.saved.coreEnabled
            title: "Core display"; description: "Only one display hosts Core. A disconnected choice falls back to an available output."
            StationCombo {
                Layout.fillWidth: true; model: root.choices; textRole: "label"; Accessible.name: "Core display"
                currentIndex: Math.max(0, root.choices.findIndex(c => c.name === Config.saved.coreMonitor))
                onActivated: Config.set("coreMonitor", root.choices[currentIndex].name)
            }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Keyboard"
            description: root.shortcuts.length ? "Toggle Core with this shortcut. In Core: Tab moves between controls, arrows between signals, Enter activates, Escape collapses." : "No shortcut toggles Core yet; add one in Keybinds. In Core: Tab, arrows, Enter and Escape."
            Repeater { model: root.shortcuts; Keycap { required property var modelData; keys: modelData.keys; accent: Theme.green } }
            StatusPill { visible: !root.shortcuts.length; text: "Not assigned"; tone: Theme.muted }
        }
    }

    SettingsFields {
        page: "core"; Layout.fillWidth: true; highlightKey: root.highlightKey
        exclude: ["Core"]
        captions: ({
            "Activities": "What Core may show. Each source is real system state; nothing is simulated.",
            "Warnings": "Thresholds for temperature and storage signals. Each warning clears below its threshold.",
            "Canopy": "Panels that descend beneath the bar, and the compact preview on hover.",
            "Forest": "Ambient behavior that follows real activity.",
            "Whisper types": "Quiet observations, at least ten minutes apart and six hours per type.",
            "Instruments": "Extra live readings that run only while their panel is open.",
            "Privacy": "Opt-in histories. Both are session-only and cleared when the screen locks."
        })
    }

    SettingsSection {
        heading: "Where signals come from"
        caption: "Recording comes from active gpu-screen-recorder processes. Saved screenshots use explicit capture notifications or the Core event API. Timers belong to CEDAR. Updates are checked only on request. Download and plugin progress need an explicit publisher; no global progress is guessed."
        GlowText {
            visible: CoreService.probe.error !== ""
            text: CoreService.probe.error
            color: Theme.amber
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.small
        }
    }
}
