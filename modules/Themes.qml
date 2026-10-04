import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

Overlay {
    id: root
    panelName: "themes"
    property var names: []
    onVisibleChanged: if (visible && !list.running) list.running = true
    Process {
        id: list
        command: ["omarchy", "theme", "list"]
        stdout: StdioCollector { onStreamFinished: root.names = text.trim().split("\n").filter(n => n.trim() !== "") }
    }
    HudPanel {
        anchors.centerIn: parent
        width: Math.min(600, root.width - 32); height: Math.min(640, root.height - 32)
        ColumnLayout {
            anchors.fill: parent
            RowLayout {
                GlowText { text: "CHOOSE THE NEXT TRAIL"; font.family: Theme.labelFont; font.pixelSize: 24; color: Theme.green; Layout.fillWidth: true }
                HudButton { text: "×"; onClicked: ShellState.close() }
            }
            GlowText { text: "CEDAR rests when another theme is selected."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                model: root.names
                ScrollBar.vertical: ScrollBar {}
                delegate: HudButton {
                    required property string modelData
                    width: ListView.view.width; text: modelData.toLowerCase() === "cedar" ? "CEDAR" : modelData; checked: modelData.toLowerCase() === "cedar"
                    onClicked: { ShellState.close(); Quickshell.execDetached(["omarchy", "theme", "set", modelData]); }
                }
            }
        }
    }
}
