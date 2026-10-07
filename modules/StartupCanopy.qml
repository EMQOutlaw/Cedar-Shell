import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Startup: what starts with the session, as a Canopy topic. Rows are the
// standard autostart entries (yours and the system's) with the state of the
// unit that ran each one, a switch, run now and remove. Type an app name to
// add it from the catalog, or any command to run it at login. Hyprland's own
// autostart.lua lines show read-only; that file stays the user's to edit.
ColumnLayout {
    id: root
    property bool active: false
    property var entries: []
    property var hyprland: ({ present: false, path: "~/.config/hypr/autostart.lua", commands: [] })
    property string error: ""
    property string message: ""
    property string query: ""
    property int selected: 0
    // After an arrow key the keyboard is on the rows: Space, Enter and Delete
    // act on the selected one. Typing returns the keys to the field.
    property bool browsing: false
    property var pending: null
    readonly property bool busy: startup.running
    readonly property int enabledCount: entries.filter(e => e.enabled).length
    readonly property int runningCount: entries.filter(e => e.state === "running" || e.state === "active").length
    spacing: 12
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }

    // Catalog apps that match the query and are not already startup entries.
    readonly property var appMatches: {
        const q = root.query.trim().toLowerCase();
        if (!q)
            return [];
        const present = root.entries.map(e => e.id);
        const scored = [];
        for (const a of (DefaultApps.data.apps || [])) {
            if (!a || a.visible === false || !a.id || present.includes(a.id))
                continue;
            const label = String(a.label || "").toLowerCase();
            const text = label + " " + String(a.id).toLowerCase() + " " + String(a.description || "").toLowerCase();
            if (!text.includes(q))
                continue;
            scored.push({ app: a, tier: label === q ? 0 : label.startsWith(q) ? 1 : label.includes(q) ? 2 : 3 });
        }
        scored.sort((x, y) => x.tier - y.tier || String(x.app.label).localeCompare(String(y.app.label)));
        return scored.slice(0, 6).map(s => s.app);
    }
    function iconSource(name) { return Config.imageSource(Quickshell.iconPath(name || "application-x-executable", true)); }
    function sourceLabel(entry) { return entry.source === "system" ? "System" : entry.kind === "command" ? "Command" : "Yours"; }
    function stateLabel(entry) {
        if (!entry.enabled)
            return entry.reason === "other-desktop" ? "Not this desktop" : entry.reason === "missing" ? "Not installed" : "Off";
        return ({ running: "Running", active: "Active", starting: "Starting", exited: "Ran", failed: "Failed", inactive: "Waiting", unknown: "Next login" })[entry.state] || "Next login";
    }
    function stateTone(entry) {
        if (!entry.enabled)
            return entry.reason ? Theme.muted : Theme.amber;
        return entry.state === "running" || entry.state === "active" ? Theme.green : entry.state === "failed" ? Theme.ember : Theme.muted;
    }

    // One request at a time; an action asked for during a refresh waits its turn.
    function request(payload) {
        if (Config.testMode || ShellState.locked)
            return;
        root.error = "";
        if (startup.running) {
            root.pending = payload;
            return;
        }
        startup.send(payload);
    }
    function refresh() {
        if (!root.active || Config.testMode || startup.running)
            return;
        startup.send({ action: "list" });
    }
    function drain() {
        if (root.pending) {
            const next = root.pending;
            root.pending = null;
            startup.send(next);
        }
    }
    function toggle(entry) { if (entry) request({ action: "set_enabled", id: entry.id, enabled: !entry.enabled }); }
    function run(entry) {
        if (!entry)
            return;
        request({ action: entry.state === "running" || entry.state === "active" ? "stop" : "run", id: entry.id });
    }
    function remove(entry) { if (entry && entry.removable) request({ action: "remove", id: entry.id }); }
    function addApp(app) {
        if (!app)
            return;
        request({ action: "add_app", id: app.id });
        field.text = "";
    }
    function addCommand() {
        const command = root.query.trim();
        if (!command)
            return;
        request({ action: "add_command", command: command });
        field.text = "";
    }
    function submit() {
        if (root.query.trim()) {
            if (root.appMatches.length)
                root.addApp(root.appMatches[0]);
            else
                root.addCommand();
        } else if (root.browsing) {
            root.run(root.entries[root.selected]);
        }
    }
    function move(delta) {
        root.browsing = true;
        if (!root.entries.length)
            return;
        root.selected = Math.max(0, Math.min(root.entries.length - 1, root.selected + delta));
    }
    onActiveChanged: {
        if (active) {
            field.text = "";
            root.query = "";
            root.selected = 0;
            root.browsing = false;
            root.message = "";
            refresh();
            Qt.callLater(() => field.forceActiveFocus());
        }
    }
    onEntriesChanged: root.selected = Math.max(0, Math.min(root.entries.length - 1, root.selected))
    ServiceRequest {
        id: startup
        script: "scripts/startup_apps.py"
        onResult: data => {
            root.entries = Array.isArray(data.entries) ? data.entries : [];
            if (data.hyprland)
                root.hyprland = data.hyprland;
            if (data.message)
                root.message = data.message;
            root.drain();
        }
        onFailed: text => { root.error = text; root.drain(); }
    }
    // Unit states move while the panel is open; a slow poll keeps the pills honest.
    Timer { interval: 5000; running: root.active && !Config.testMode; repeat: true; onTriggered: root.refresh() }

    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        SectionMark { text: "STARTUP" }
        Item { Layout.fillWidth: true }
        StatusPill { visible: root.runningCount > 0; text: root.runningCount + " running"; tone: Theme.green }
        StatusPill { text: root.busy && !root.entries.length ? "Reading" : root.enabledCount + " on · " + (root.entries.length - root.enabledCount) + " off"; tone: Theme.teal }
    }

    // Add: the field takes an app name or a command; chips below offer the matches.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.beat(1)
        transform: Translate { y: 6 * (1 - root.beat(1)) }
        StationField {
            id: field
            objectName: "startupAdd"
            Layout.fillWidth: true
            placeholderText: "App name, or a command to run at login"
            Accessible.name: "Add a startup app or command"
            onTextChanged: { root.query = text; root.browsing = false; }
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Down: root.move(1); break;
                case Qt.Key_Up: root.move(-1); break;
                case Qt.Key_Tab: root.move(1); break;
                case Qt.Key_Backtab: root.move(-1); break;
                case Qt.Key_Return: case Qt.Key_Enter: root.submit(); break;
                case Qt.Key_Space:
                    if (text || !root.browsing)
                        return;
                    root.toggle(root.entries[root.selected]);
                    break;
                case Qt.Key_Delete:
                    if (text || !root.browsing)
                        return;
                    root.remove(root.entries[root.selected]);
                    break;
                case Qt.Key_Escape:
                    if (text) text = "";
                    else if (root.browsing) root.browsing = false;
                    else Canopy.close();
                    break;
                default: return;
                }
                event.accepted = true;
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 2
            Rectangle { width: parent.width; height: 1; y: 1; color: Qt.alpha(Theme.teal, .12) }
            Rectangle {
                width: parent.width * (root.query ? 1 : .55 * root.beat(1, .6))
                height: root.query ? 2 : 1
                color: root.query ? (root.appMatches.length ? Theme.green : Theme.amber) : Theme.teal
                opacity: root.query ? .85 : .5
                Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
        }
        Flow {
            visible: root.query.trim() !== ""
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.appMatches
                StationButton {
                    id: chip
                    required property var modelData
                    required property int index
                    implicitHeight: 32
                    text: modelData.label
                    hint: "Start " + modelData.label + " with the session"
                    accent: index === 0 ? Theme.green : Theme.teal
                    onClicked: root.addApp(modelData)
                    contentItem: Row {
                        spacing: 8
                        Image { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit; asynchronous: true; source: root.iconSource(chip.modelData.icon) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.text; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.text }
                    }
                }
            }
            StationButton {
                implicitHeight: 32
                text: "Run “" + root.query.trim() + "” at login"
                hint: root.appMatches.length ? "Add the text as a command instead of the matched app" : "Enter adds this command"
                accent: root.appMatches.length ? Theme.teal : Theme.green
                onClicked: root.addCommand()
            }
        }
    }

    GlowText { visible: root.error !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.error; color: Theme.amber }
    GlowText { visible: root.error === "" && root.message !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.message; color: Theme.teal; font.pixelSize: Theme.small }

    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(2)
        SectionMark { text: "WITH THE SESSION"; size: 9; tone: Theme.muted }
        Item { Layout.fillWidth: true }
        Text { text: root.hyprland.present ? "autostart entries · ~/.config/autostart" : "autostart entries"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted; elide: Text.ElideRight; Layout.maximumWidth: 260 }
    }

    // One row per entry: icon, name and command, source, state, and its controls.
    component StartupRow: Item {
        id: row
        property var entry: ({})
        property int index: 0
        readonly property bool current: root.browsing && index === root.selected
        readonly property bool live: entry.state === "running" || entry.state === "active"
        readonly property real sweep: root.beat(3 + Math.min(index, 10) * .6, .35)
        Layout.fillWidth: true
        implicitHeight: 54
        opacity: sweep * (entry.enabled ? 1 : .72)
        transform: Translate { x: 12 * (1 - row.sweep) }
        Accessible.role: Accessible.ListItem
        Accessible.name: (entry.name || "") + ", " + root.stateLabel(entry)
        ChamferFrame {
            anchors.fill: parent
            cut: 7
            fill: row.current ? Qt.alpha(Theme.green, .07) : hover.containsMouse ? Qt.alpha(Theme.teal, .05) : Qt.alpha(Theme.background, .5)
            stroke: row.current ? Qt.alpha(Theme.green, .55) : entry.state === "failed" && entry.enabled ? Qt.alpha(Theme.ember, .4) : hover.containsMouse ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .13)
            line: row.live || row.current
            lineColor: row.live ? Theme.green : Theme.teal
            lineFraction: .5 * row.sweep
            lineOpacity: row.live ? .6 : .35
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: { root.browsing = true; root.selected = row.index; }
            onClicked: { root.browsing = true; root.selected = row.index; }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 10
            spacing: 10
            Image {
                width: 22; height: 22
                Layout.preferredWidth: 22; Layout.preferredHeight: 22
                sourceSize.width: 44; sourceSize.height: 44
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: root.iconSource(row.entry.icon)
                opacity: row.entry.enabled ? 1 : .6
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: row.entry.name || row.entry.id || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.dataFont
                    font.pixelSize: 12
                    color: row.current ? Theme.green : row.entry.enabled ? Theme.text : Theme.muted
                }
                Text {
                    Layout.fillWidth: true
                    text: root.sourceLabel(row.entry) + (row.entry.overrides ? " · overrides system" : "") + (row.entry.exec ? " · " + row.entry.exec : row.entry.comment ? " · " + row.entry.comment : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    font.family: Theme.dataFont
                    font.pixelSize: 9
                    font.letterSpacing: .5
                    color: Theme.muted
                }
            }
            StatusPill { text: root.stateLabel(row.entry); tone: root.stateTone(row.entry) }
            StationButton {
                implicitWidth: 44; implicitHeight: 30
                text: row.entry.enabled ? "On" : "Off"
                hint: row.entry.enabled ? "Stop starting " + row.entry.name + " with the session" : "Start " + row.entry.name + " with the session"
                accent: row.entry.enabled ? Theme.green : Theme.amber
                checked: row.entry.enabled
                enabled: !root.busy
                onClicked: root.toggle(row.entry)
            }
            StationButton {
                implicitWidth: 52; implicitHeight: 30
                visible: row.entry.enabled
                text: row.live ? "Stop" : "Run"
                hint: row.live ? "Stop " + row.entry.name + " now" : "Run " + row.entry.name + " now"
                accent: row.live ? Theme.amber : Theme.teal
                enabled: !root.busy
                onClicked: root.run(row.entry)
            }
            StationButton {
                implicitWidth: 30; implicitHeight: 30; iconOnly: true
                visible: row.entry.removable
                text: "×"
                hint: row.entry.overrides ? "Remove your override of " + row.entry.name : "Remove " + row.entry.name + " from startup"
                accent: Theme.ember
                enabled: !root.busy
                onClicked: root.remove(row.entry)
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.entries
            StartupRow { required property var modelData; required property int index; entry: modelData }
        }
    }
    GlowText {
        visible: root.entries.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Config.testMode ? "Startup entries are read from the session." : root.busy ? "Reading startup entries…" : root.error ? "" : "Nothing starts with the session yet. Type an app name or a command above."
        color: Theme.muted
    }

    // Hyprland's own autostart lines, read-only: that Lua file is the user's.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: root.hyprland.commands && root.hyprland.commands.length > 0
        opacity: root.beat(4)
        RowLayout {
            Layout.fillWidth: true
            SectionMark { text: "HYPRLAND AUTOSTART"; size: 9; tone: Theme.muted }
            Item { Layout.fillWidth: true }
            Text { text: "read-only · " + root.hyprland.path; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted }
        }
        Repeater {
            model: root.hyprland.commands || []
            Item {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 34
                ChamferFrame { anchors.fill: parent; cut: 6; fill: Qt.alpha(Theme.background, .4); stroke: Qt.alpha(Theme.teal, .1) }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                    Text { Layout.fillWidth: true; text: modelData.command; textFormat: Text.PlainText; elide: Text.ElideMiddle; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.text }
                    Text { text: modelData.kind === "launch_on_start" ? "uwsm app" : "exec"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "↑↓ select · Space on/off · Enter run · Del remove · type to add"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: Theme.dataFont
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Theme.muted
        opacity: root.beat(5)
    }
}
