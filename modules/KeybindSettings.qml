import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "../services"
import "../components"
ColumnLayout {
    id: root
    property bool active: false
    property string query: ""
    property string category: "All"
    property string original: ""
    property string previousCommand: ""
    property string keys: ""
    property bool recording: false
    readonly property bool dirty:keys!=="" || description.text!=="" || command.text!==""
    property bool replaceConfirmed:false
    onKeysChanged:replaceConfirmed=false
    readonly property var conflicts: DesktopSettings.data.bindings.filter(b=> !b.submap && b.keys === keys && b.keys !== original)
    onActiveChanged: { recording = false; if (active) DesktopSettings.refresh(); }
    Connections {
        target: DesktopSettings
        function onApplied(action) {
            if (action === "binding" || action === "remove-binding") {
                root.original=""; root.previousCommand=""; root.keys=""; description.text=""; command.text="";
            }
        }
    }
    spacing: 14
    function record(event) {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { recording = false; return; }
        if ([Qt.Key_Shift,Qt.Key_Control,Qt.Key_Alt,Qt.Key_Meta].includes(event.key)) return;
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
    GlowText { text: "Active shortcuts"; color: Theme.teal; font.pixelSize: 20 }
    GlowText { text: "Live Hyprland bindings. Application shortcuts can be edited below; compositor callbacks and special bindings retain their original Lua definitions."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    GridLayout {
        columns:root.width<570 ? 1:3; Layout.fillWidth:true
        StationField { Layout.fillWidth: true; placeholderText: "Search shortcuts"; onTextChanged: root.query = text.toLowerCase() }
        StationCombo { model: ["All","Applications","Window management","Workspaces","Media","Screenshots","System","CEDAR"]; onActivated: root.category = currentText }
        StationButton { text: "Refresh"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.refresh() }
    }
    ListView {
        Layout.fillWidth: true; Layout.preferredHeight: 280; clip: true; spacing: 8
        ScrollBar.vertical: ScrollBar {}
        model: DesktopSettings.data.bindings.filter(b => (root.category === "All" || b.category === root.category) && (b.keys+" "+b.description+" "+b.arg).toLowerCase().includes(root.query))
        delegate: RowLayout {
            required property var modelData
            width: ListView.view.width; height: 52
            ColumnLayout {
                Layout.fillWidth: true
                GlowText { text: modelData.description || modelData.dispatcher; Layout.fillWidth: true; elide: Text.ElideRight }
                GlowText { text: modelData.keys + (modelData.submap ? " · " + modelData.submap : ""); color: Theme.teal; font.pixelSize: 11 }
            }
            StationButton {
                text: "Edit"; visible: modelData.editable
                onClicked: { root.original=modelData.keys; root.previousCommand=modelData.arg; root.keys=modelData.keys; description.text=modelData.description || "Custom shortcut"; command.text=modelData.arg; command.forceActiveFocus(); }
            }
            StationButton {
                text: "Restore"; visible: DesktopSettings.data.owned.bindings.some(b=>b.keys===modelData.keys)
                enabled: !DesktopSettings.busy
                onClicked: DesktopSettings.apply({action:"remove-binding",keys:modelData.keys})
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
    GlowText { text: root.original ? "EDIT / " + root.original : "ADD A SHORTCUT"; color: Theme.teal }
    GlowText { visible: root.original !== ""; text: "Previously: " + root.previousCommand; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 11 }
    RowLayout {
        StationField { Layout.fillWidth: true; text: root.keys; placeholderText: "SUPER + SHIFT + F"; onCommit: value => root.keys=value.toUpperCase() }
        StationButton {
            text: root.recording ? "Press shortcut… Esc cancels" : "Record keys"
            onClicked: { root.recording = true; forceActiveFocus(); }
            Keys.onPressed: event => { if (root.recording) root.record(event); }
        }
    }
    StationField { id: description; Layout.fillWidth: true; placeholderText: "Description" }
    StationField { id: command; Layout.fillWidth: true; placeholderText: "Command, e.g. qs -c cedar ipc call control toggle" }
    GlowText { visible: root.conflicts.length > 0; text: "Already assigned: " + root.conflicts.map(b=>b.description || b.dispatcher).join(", "); color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    Flow {
        visible:root.conflicts.length>0; Layout.fillWidth:true; spacing:8
        StationButton { text:root.replaceConfirmed ? "Replacement confirmed":"Replace existing shortcut"; enabled:root.conflicts.every(b=>b.editable); checked:root.replaceConfirmed; onClicked:root.replaceConfirmed=true }
        StationButton { text:"Cancel replacement"; onClicked:{root.replaceConfirmed=false;root.keys="";} }
    }
    GlowText { visible:root.conflicts.some(b=>!b.editable); text:"This binding uses a compositor callback or special behavior. Edit its source configuration to replace it."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted; font.pixelSize:Theme.small }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton {
            text: root.replaceConfirmed ? "Apply replacement":"Save shortcut"; enabled: !!root.keys && !!command.text.trim() && (!root.conflicts.length || root.replaceConfirmed) && !DesktopSettings.busy
            onClicked: DesktopSettings.apply({action:"binding",keys:root.keys,original:root.original,previousCommand:root.previousCommand,command:command.text,description:description.text,replace:root.replaceConfirmed ? root.conflicts:[]})
        }
        StationButton { text: "New shortcut"; onClicked: { root.original=""; root.keys=""; root.previousCommand=""; description.text=""; command.text=""; } }
    }
}
