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
    exclusionMode: ExclusionMode.Ignore
    color: Qt.alpha(Theme.background, 0.60)
    WlrLayershell.namespace: "cedar-wallpaper-grid"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    property var wallpapers: []
    property bool loading: true
    property string error: ""
    readonly property var selected: wallpapers.length ? wallpapers[grid.currentIndex] : null
    function apply() {
        if (!selected || applyProcess.running) return;
        applyProcess.command = ["python3", Quickshell.shellPath("tools/wallpapers/apply.py"), selected.path];
        applyProcess.running = true;
    }
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("tools/wallpapers/library.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.wallpapers = data.items;
                    grid.currentIndex = Math.max(0, data.items.findIndex(item => item.path === data.selected));
                } catch (e) { root.error = "Could not load the CEDAR wallpaper library."; }
                root.loading = false;
                grid.forceActiveFocus();
            }
        }
    }
    Process {
        id: applyProcess
        onExited: (code, status) => {
            if (code === 0) Qt.quit();
            else root.error = "Could not apply this wallpaper. Try another image.";
        }
    }
    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 1240)
        height: Math.min(parent.height - 64, 780)
        radius: 28
        color: Theme.background
        border.color: Theme.border
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 20
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 4
                    Text { text: "Wallpapers"; color: Theme.text; font.pixelSize: 28; font.weight: Font.DemiBold }
                    Text { text: "CEDAR  ·  " + root.wallpapers.length + " images"; color: Theme.muted; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                Text { text: "← ↑ ↓ →  Browse     Enter  Apply     Esc  Close"; color: Theme.muted; font.pixelSize: 13 }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24
                ColumnLayout {
                    Layout.preferredWidth: 540
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: 560
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14
                    RoundedImage {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        pixels: 1100
                        source: root.selected ? root.selected.preview : ""
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.selected ? root.selected.name : root.loading ? "Loading wallpapers…" : "No wallpapers found"
                        color: Theme.text; font.pixelSize: 21; elide: Text.ElideRight
                    }
                    Text { text: applyProcess.running ? "Applying…" : "Press Enter to set this wallpaper"; color: Theme.green; font.pixelSize: 13 }
                }
                GridView {
                    id: grid
                    Layout.preferredWidth: 580
                    Layout.minimumWidth: 240
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: width / 3
                    cellHeight: cellWidth * 0.8 + 26
                    model: root.wallpapers
                    focus: true
                    keyNavigationEnabled: false
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                    Keys.onPressed: event => {
                        let step = 0;
                        if (event.key === Qt.Key_Left) step = -1;
                        else if (event.key === Qt.Key_Right) step = 1;
                        else if (event.key === Qt.Key_Up) step = -3;
                        else if (event.key === Qt.Key_Down) step = 3;
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.apply();
                        else if (event.key === Qt.Key_Escape) Qt.quit();
                        else return;
                        if (step) currentIndex = Math.max(0, Math.min(count - 1, currentIndex + step));
                        event.accepted = true;
                    }
                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 18
                            color: grid.currentIndex === tile.index ? Qt.alpha(Theme.green, 0.22) : Theme.surface
                            border.width: grid.currentIndex === tile.index ? 2 : 0
                            border.color: Theme.green
                            RoundedImage { anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 } height: parent.height - 42; source: tile.modelData.preview }
                            Text {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                                text: tile.modelData.name; color: Theme.text; font.pixelSize: 11; elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { grid.currentIndex = tile.index; grid.forceActiveFocus(); }
                                onDoubleClicked: root.apply()
                            }
                        }
                    }
                    Component.onCompleted: forceActiveFocus()
                }
            }
            Text { visible: root.error.length > 0; text: root.error; color: Theme.ember; font.pixelSize: 14 }
        }
    }
}
