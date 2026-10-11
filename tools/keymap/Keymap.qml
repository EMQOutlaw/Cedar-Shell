import "../.."
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
PanelWindow {
    id: root
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.alpha(Theme.background, 0.67)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "cedar-keymap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    property var bindings: []
    property string error: ""
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("tools/keymap/bindings.py")]
        stdout: StdioCollector { onStreamFinished: {
            try { root.bindings = JSON.parse(text); }
            catch(e) { root.error = "Could not read the active shortcuts."; }
        } }
    }
    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 1050)
        height: Math.min(parent.height - 64, 840)
        color: Theme.background; radius: 26; border.color: Theme.border
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 28; spacing: 16
            RowLayout {
                Layout.fillWidth: true
                Text { text: "CEDAR Keymap"; color: Theme.text; font.pixelSize: 28; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { text: "Esc to close"; color: Theme.muted; font.pixelSize: 14 }
            }
            TextField {
                id: search
                Layout.fillWidth: true
                placeholderText: "Search shortcuts — wallpaper, volume, workspace…"
                color: Theme.text; placeholderTextColor: Theme.muted; font.pixelSize: 16
                padding: 14
                background: Rectangle { color: Theme.surface; radius: 12; border.color: Theme.teal }
                Component.onCompleted: forceActiveFocus()
                Keys.onEscapePressed: Qt.quit()
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
            }
            Text { text: root.error || list.count + " active shortcuts"; color: Theme.muted; font.pixelSize: 13 }
            ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; spacing: 5
                model: root.bindings.filter(b => (b.keys + " " + b.description).toLowerCase().includes(search.text.toLowerCase()))
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width - 14; height: Math.max(50, description.implicitHeight + 20)
                    radius: 10; color: index % 2 ? Theme.surface : Theme.elevated
                    Text {
                        id: description
                        anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.52 - 24
                        text: modelData.description; color: Theme.text; font.pixelSize: 15; wrapMode: Text.WordWrap
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.48 - 16
                        text: modelData.keys; color: Theme.green; font.pixelSize: 14; horizontalAlignment: Text.AlignRight; wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
