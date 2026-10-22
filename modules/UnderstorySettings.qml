import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings › Bar › Understory: the rail that grows from the bar's left end.
// No shortcut ships with it; one is assigned here, through the same desktop
// backend as Keybinds, which reads Hyprland live and refuses conflicts.
ColumnLayout {
    id: root
    property bool active: false
    readonly property string command: "qs -c cedar ipc call understory toggle"
    readonly property var bindings: DesktopSettings.data.bindings || []
    readonly property var shortcuts: bindings.filter(b => /ipc call understory toggle$/.test(b.arg || ""))
    readonly property var conflicts: bindings.filter(b => !b.submap && b.keys === keys)
    property string keys: ""
    property bool recording: false
    onActiveChanged: { recording = false; keys = ""; if (active) DesktopSettings.refresh(); }
    Connections {
        target: DesktopSettings
        function onApplied(action) { if (action === "binding" || action === "remove-binding") { root.keys = ""; root.recording = false; } }
    }
    function record(event) {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { recording = false; return; }
        if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].includes(event.key)) return;
        const names = {}; names[Qt.Key_Return] = "RETURN"; names[Qt.Key_Enter] = "KP_ENTER"; names[Qt.Key_Space] = "SPACE";
        names[Qt.Key_Tab] = "TAB"; names[Qt.Key_Backspace] = "BACKSPACE"; names[Qt.Key_Delete] = "DELETE";
        names[Qt.Key_Left] = "LEFT"; names[Qt.Key_Right] = "RIGHT"; names[Qt.Key_Up] = "UP"; names[Qt.Key_Down] = "DOWN";
        const key = names[event.key] || (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35 ? "F" + (event.key - Qt.Key_F1 + 1) : event.key >= 48 && event.key <= 90 ? String.fromCharCode(event.key) : "");
        if (!key) return;
        const mods = [];
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier) mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
        keys = mods.concat([key]).join(" + "); recording = false;
    }
    spacing: 16

    SettingsSection {
        emphasis: true; accent: Theme.green
        heading: "Close to the ground."
        caption: "The Understory grows from the bar's left end: the hour and the session, the links, the levels, what is on the air, the station's stance and the power profile, with CEDAR's own instruments down the edge. Every reading is the same service the bar and the Core pill read."
        badge: Understory.shown ? "Open" : "Closed"; badgeColor: Understory.shown ? Theme.green : Theme.muted
        SettingRow {
            Layout.fillWidth: true; title: "Opening it"
            description: "Click CEDAR's mark at the left of the bar, or run qs -c cedar ipc call understory toggle. Escape or a click elsewhere closes it."
            StrataButton { text: Understory.shown ? "Close" : "Open now"; enabled: !ShellState.locked; onClicked: Understory.toggle() }
        }
        SettingRow {
            objectName: "understoryShortcut"
            Layout.fillWidth: true; title: "Keyboard shortcut"
            description: root.shortcuts.length ? "Toggles the Understory. Saved through CEDAR's own Hyprland bindings; Restore removes it." : "None assigned. Record one below; CEDAR reads Hyprland live and refuses a shortcut that is already taken."
            Repeater {
                model: root.shortcuts
                RowLayout {
                    required property var modelData
                    spacing: 6
                    Keycap { keys: modelData.keys; accent: Theme.green }
                    StationButton { text: "Restore"; hint: "Remove this shortcut and return to your configuration"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({ action: "remove-binding", keys: modelData.keys }) }
                }
            }
            StatusPill { visible: !root.shortcuts.length; text: "Not assigned"; tone: Theme.muted }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 56; radius: 10
            color: root.recording ? Qt.alpha(Theme.green, .06) : Theme.surface
            border.width: root.recording ? 2 : 1; border.color: root.recording ? Theme.green : Qt.alpha(Theme.teal, .18)
            Keycap { anchors.centerIn: parent; visible: root.keys !== "" && !root.recording; keys: root.keys; accent: root.conflicts.length ? Theme.amber : Theme.green; scale: 1.2 }
            GlowText { anchors.centerIn: parent; visible: root.keys === "" || root.recording; text: root.recording ? "Press the shortcut now  ·  Esc cancels" : "No keys yet"; color: root.recording ? Theme.green : Theme.muted; font.pixelSize: Theme.small }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            StationButton {
                text: root.recording ? "Listening…" : "●  Record keys"; checked: root.recording; accent: Theme.green
                enabled: !DesktopSettings.busy
                onClicked: { root.recording = true; forceActiveFocus(); }
                Keys.onPressed: event => { if (root.recording) root.record(event); }
            }
            StationField { Layout.fillWidth: true; text: root.keys; placeholderText: "or type, e.g. SUPER + O"; Accessible.name: "Understory shortcut keys"; onCommit: value => root.keys = value.toUpperCase() }
            StationButton {
                text: "Save"; accent: Theme.green; checked: enabled
                enabled: !!root.keys && !root.conflicts.length && !DesktopSettings.busy
                onClicked: DesktopSettings.apply({ action: "binding", keys: root.keys, original: "", previousCommand: "", command: root.command, description: "Toggle the Understory", replace: [] })
            }
        }
        GlowText { visible: root.conflicts.length > 0; text: "Already assigned to " + root.conflicts.map(b => b.description || b.dispatcher).join(", ") + ". Choose other keys, or replace it from Keybinds."; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
        GlowText { visible: DesktopSettings.error !== ""; text: DesktopSettings.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    }
}
