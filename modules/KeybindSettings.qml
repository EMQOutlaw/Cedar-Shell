import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "../services"
import "../components"
ColumnLayout {
    id: root
    property bool active: false
    property string highlightKey: ""
    property string query: ""
    property string category: "All"
    property string original: ""
    property string previousCommand: ""
    property string keys: ""
    property bool recording: false
    readonly property bool dirty:keys!=="" || description.text!=="" || command.text!==""
    property bool replaceConfirmed:false
    onKeysChanged:replaceConfirmed=false
    readonly property var bindings: DesktopSettings.data.bindings || []
    readonly property var owned: DesktopSettings.data.owned?.bindings || []
    readonly property var conflicts: bindings.filter(b=> !b.submap && b.keys === keys && b.keys !== original)
    readonly property var categories: ["Applications","Window management","Workspaces","Media","Screenshots","System","CEDAR"]
    readonly property var filtered: bindings.filter(b => (root.category === "All" || b.category === root.category) && (b.keys+" "+(b.description || "")+" "+(b.arg || "")+" "+(b.dispatcher || "")).toLowerCase().includes(root.query))
    readonly property var groups: categories.map(c => ({name:c, rows:filtered.filter(b => b.category === c)})).filter(g => g.rows.length)
    function isOwned(b) { return owned.some(o => o.keys === b.keys); }
    function edit(b) {
        original=b.keys; previousCommand=b.arg || ""; keys=b.keys; description.text=b.description || "Custom shortcut"; command.text=b.arg || "";
        reveal(editor); command.forceActiveFocus();
    }
    function clearEditor() { original=""; previousCommand=""; keys=""; description.text=""; command.text=""; recording=false; }
    function reveal(item) {
        let flick = root.parent;
        while (flick && flick.contentY === undefined) flick = flick.parent;
        if (!flick) return;
        flick.contentY = Math.max(0, Math.min(item.mapToItem(flick.contentItem, 0, 0).y - 12, flick.contentHeight - flick.height));
    }
    onActiveChanged: { recording = false; if (active) DesktopSettings.refresh(); }
    Connections {
        target: DesktopSettings
        function onApplied(action) { if (action === "binding" || action === "remove-binding") root.clearEditor(); }
    }
    spacing: 16
    function record(event) {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { recording = false; return; }
        if ([Qt.Key_Shift,Qt.Key_Control,Qt.Key_Alt,Qt.Key_Meta,Qt.Key_Super_L,Qt.Key_Super_R].includes(event.key)) return;
        const names = {}; names[Qt.Key_Return]="RETURN"; names[Qt.Key_Enter]="KP_ENTER"; names[Qt.Key_Space]="SPACE";
        names[Qt.Key_Tab]="TAB"; names[Qt.Key_Backspace]="BACKSPACE"; names[Qt.Key_Delete]="DELETE";
        names[Qt.Key_Left]="LEFT"; names[Qt.Key_Right]="RIGHT"; names[Qt.Key_Up]="UP"; names[Qt.Key_Down]="DOWN";
        let key = names[event.key] || (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35 ? "F"+(event.key-Qt.Key_F1+1) : event.key >= 48 && event.key <= 90 ? String.fromCharCode(event.key) : "");
        if (!key) return;
        const mods = [];
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier) mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
        keys = mods.concat([key]).join(" + "); recording = false;
    }
    // One live binding, laid out as keycaps · meaning · command.
    component BindingRow: Item {
        id: row
        required property var modelData
        readonly property bool mine: root.isOwned(modelData)
        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight + 16
        Rectangle { anchors.fill: parent; radius: 7; color: hover.hovered || root.original === row.modelData.keys ? Qt.alpha(Theme.teal, .05) : Theme.transparent; border.width: root.original === row.modelData.keys ? 1 : 0; border.color: Qt.alpha(Theme.green, .45) }
        HoverHandler { id: hover }
        GridLayout {
            id: grid
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10; anchors.rightMargin: 6
            columns: root.width < 600 ? 1 : 3; columnSpacing: 16; rowSpacing: 6
            Keycap { Layout.preferredWidth: root.width < 600 ? -1 : 210; keys: row.modelData.keys; accent: row.mine ? Theme.green : Theme.teal }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    spacing: 8; Layout.fillWidth: true
                    GlowText { text: row.modelData.description || row.modelData.dispatcher; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.small + 1 }
                    GlowText { visible: row.mine; text: "YOURS"; color: Theme.green; font.pixelSize: 9; font.letterSpacing: 1.2 }
                    GlowText { visible: !row.modelData.editable; text: row.modelData.submap ? "SUBMAP · " + row.modelData.submap.toUpperCase() : "COMPOSITOR"; color: Theme.muted; font.pixelSize: 9; font.letterSpacing: 1.2 }
                }
                GlowText { visible: text !== ""; text: (row.modelData.dispatcher === "exec" ? "" : row.modelData.dispatcher + "  ") + (row.modelData.arg || ""); color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
            }
            RowLayout {
                spacing: 4
                StationButton { text: "Edit"; visible: row.modelData.editable; enabled: !DesktopSettings.busy; onClicked: root.edit(row.modelData) }
                StationButton { text: "Restore"; visible: row.mine; hint: "Remove CEDAR’s version and return to your configuration’s shortcut"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"remove-binding",keys:row.modelData.keys}) }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 12
        Rectangle { width: 8; height: 8; radius: 4; color: root.bindings.length ? Theme.green : Theme.amber }
        GlowText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
            text: DesktopSettings.busy && !root.bindings.length ? "Reading Hyprland…" : root.bindings.length + " shortcuts read live from Hyprland  ·  " + root.owned.length + " added in CEDAR"
        }
        StationButton { text: "Refresh"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.refresh() }
    }

    // Your binds
    SettingsSection {
        objectName: "customBinds"; accent: Theme.green
        heading: "Your shortcuts"; badge: root.owned.length ? root.owned.length + " added" : ""; badgeColor: Theme.green
        caption: "Added or changed here. Your own override file still loads after them, and Restore returns the original binding."
        Repeater {
            model: root.bindings.filter(b => root.isOwned(b))
            BindingRow {}
        }
        GlowText { visible: !root.owned.length; text: "None yet. Record one below — CEDAR checks for conflicts before saving."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        GlowText {
            readonly property var missing: root.owned.filter(o => !root.bindings.some(b => b.keys === o.keys))
            visible: missing.length > 0 && root.bindings.length > 0
            text: "Saved but not active: " + missing.map(o => o.keys).join(", ") + ". A later override in your configuration may be replacing them."
            color: Theme.amber; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
    }

    // Everything
    ColumnLayout {
        Layout.fillWidth: true; spacing: 10
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 1 : 2; columnSpacing: 10
            StationField { Layout.fillWidth: true; placeholderText: "Search keys, actions or commands"; Accessible.name: "Search shortcuts"; onTextChanged: root.query = text.toLowerCase() }
            GlowText { text: root.filtered.length + " shown"; color: Theme.muted; font.pixelSize: Theme.small }
        }
        ChoiceChips {
            Layout.fillWidth: true; accessibleLabel: "Category"
            options: [{value:"All", label:"All  " + root.bindings.length}].concat(root.categories.map(c => ({value:c, label:c + "  " + root.bindings.filter(b => b.category === c).length})).filter(o => !o.label.endsWith("  0")))
            current: root.category; onChosen: value => root.category = value
        }
        Repeater {
            model: root.groups
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 10; spacing: 10
                    GlowText { text: modelData.name.toUpperCase(); color: Theme.teal; font.pixelSize: 10; font.letterSpacing: 1.6 }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.teal, .14) }
                    GlowText { text: String(modelData.rows.length); color: Theme.muted; font.pixelSize: 10 }
                }
                Repeater { model: modelData.rows; BindingRow {} }
            }
        }
        GlowText { visible: root.bindings.length > 0 && !root.filtered.length; text: "No shortcuts match “" + root.query + "”."; color: Theme.muted; Layout.fillWidth: true }
    }

    // Editor
    SettingsSection {
        id: editor
        objectName: "editor"
        heading: root.original ? "Edit shortcut" : "Add a shortcut"
        caption: "Record the keys, describe what it does, and give the command to run. CEDAR checks for conflicts before saving."
        GlowText { visible: root.original !== ""; text: "Previously: " + root.previousCommand; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 11 }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 64; radius: 10
            color: root.recording ? Qt.alpha(Theme.green, .06) : Theme.surface
            border.width: root.recording ? 2 : 1; border.color: root.recording ? Theme.green : Qt.alpha(Theme.teal, .18)
            Keycap { anchors.centerIn: parent; visible: root.keys !== "" && !root.recording; keys: root.keys; accent: root.conflicts.length ? Theme.amber : Theme.green; scale: 1.25 }
            GlowText { anchors.centerIn: parent; visible: root.keys === "" || root.recording; text: root.recording ? "Press the shortcut now  ·  Esc cancels" : "No keys yet"; color: root.recording ? Theme.green : Theme.muted; font.pixelSize: Theme.small }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            StationButton {
                text: root.recording ? "Listening…" : "●  Record keys"; checked: root.recording; accent: Theme.green
                onClicked: { root.recording = true; forceActiveFocus(); }
                Keys.onPressed: event => { if (root.recording) root.record(event); }
            }
            StationField { Layout.fillWidth: true; text: root.keys; placeholderText: "or type, e.g. SUPER + SHIFT + F"; Accessible.name: "Shortcut keys"; onCommit: value => root.keys=value.toUpperCase() }
        }
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 1 : 2; columnSpacing: 8; rowSpacing: 8
            StationField { id: description; Layout.fillWidth: true; placeholderText: "What it does, e.g. Open files"; Accessible.name: "Shortcut description" }
            StationField { id: command; Layout.fillWidth: true; placeholderText: "Command, e.g. nautilus"; Accessible.name: "Shortcut command" }
        }
        GlowText { visible: root.conflicts.length > 0; text: "Already assigned to " + root.conflicts.map(b=>b.description || b.dispatcher).join(", ") + "."; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Flow {
            visible:root.conflicts.length>0; Layout.fillWidth:true; spacing:8
            StationButton { text:root.replaceConfirmed ? "Replacement confirmed":"Replace existing shortcut"; accent: Theme.amber; enabled:root.conflicts.every(b=>b.editable); checked:root.replaceConfirmed; onClicked:root.replaceConfirmed=true }
            StationButton { text:"Choose other keys"; onClicked:{root.replaceConfirmed=false;root.keys="";} }
        }
        GlowText { visible:root.conflicts.some(b=>!b.editable); text:"That shortcut uses a compositor callback or special behavior. Change it in its source configuration instead."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted; font.pixelSize:Theme.small }
        Flow {
            Layout.fillWidth:true; spacing:8
            StationButton {
                text: root.replaceConfirmed ? "Apply replacement":"Save shortcut"; accent: Theme.green; checked: enabled
                enabled: !!root.keys && !!command.text.trim() && (!root.conflicts.length || root.replaceConfirmed) && !DesktopSettings.busy
                onClicked: DesktopSettings.apply({action:"binding",keys:root.keys,original:root.original,previousCommand:root.previousCommand,command:command.text,description:description.text,replace:root.replaceConfirmed ? root.conflicts:[]})
            }
            StationButton { text: "Clear"; enabled: root.dirty; onClicked: root.clearEditor() }
        }
    }
}
