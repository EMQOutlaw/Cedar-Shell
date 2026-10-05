import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

Overlay {
    id: root
    panelName: "wallpapers"
    property var wallpapers: []
    property string selectedPath: ""
    onVisibleChanged: if (visible) { refresh.running = true; } else { root.wallpapers = []; }
    Process {
        id: listWallpapers
        command: ["python3", Quickshell.shellPath("scripts/wallpapers.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const data = JSON.parse(text); root.wallpapers = data.items; root.selectedPath = data.selected; }
                catch (_) { root.wallpapers = []; root.selectedPath = ""; }
            }
        }
    }
    Connections { target: SettingsInfo; function onDataChanged() { root.selectedPath = SettingsInfo.data.wallpaper; } }
    Timer {
        id: refresh
        interval: 35
        onTriggered: if (!listWallpapers.running) listWallpapers.running = true
    }
    Loader {
        anchors.centerIn: parent
        width: Math.min(root.width - 36, 1120)
        height: Math.min(root.height - 36, 800)
        active: root.visible
        sourceComponent: wallpaperGrid
    }
    Component {
    id: wallpaperGrid
    HudPanel {
        highlighted: true
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.gap
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    GlowText { text: "CHOOSE YOUR WALLPAPER"; color: Theme.green; font.family: Theme.labelFont; font.pixelSize: 24 }
                    GlowText { text: "CEDAR / Appalachian field station"; color: Theme.muted }
                }
                HudButton { text: "×"; onClicked: ShellState.close() }
            }
            GlowText {
                Layout.fillWidth: true
                text: SettingsInfo.error ? SettingsInfo.error : root.wallpapers.length ? root.wallpapers.length + " images · choose one to set the desktop" : "No wallpapers found in this theme."
                color: Theme.muted
            }
            GridView {
                id: grid
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; cellWidth: width < 540 ? width : width / 2; cellHeight: Math.min(260, height / 2)
                model: root.wallpapers
                ScrollBar.vertical: ScrollBar {}
                delegate: AbstractButton {
                    id: tile
                    required property var modelData
                    required property int index
                    width: grid.cellWidth - 12; height: grid.cellHeight - 12
                    padding: 5; hoverEnabled: true
                    onClicked: {
                        SettingsInfo.run({action:"wallpaper", path:modelData.path});
                        refresh.restart();
                    }
                    background: HudPanel {
                        padding: 5
                        highlighted: tile.hovered || tile.activeFocus || tile.modelData.path === root.selectedPath
                        accent: tile.modelData.path === root.selectedPath ? Theme.green : Theme.teal
                    }
                    contentItem: Item {
                        Image {
                            anchors.fill: parent; source: "file://" + tile.modelData.path
                            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 42; color: Theme.glass
                            GlowText {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                                text: tile.modelData.name; color: tile.modelData.path === root.selectedPath ? Theme.green : Theme.text
                                elide: Text.ElideRight; font.pixelSize: 13
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                HudButton { text: "THEMES"; onClicked: ShellState.toggle("themes") }
                Item { Layout.fillWidth: true }
                HudButton { text: "CLOSE"; onClicked: ShellState.close() }
            }
        }
    }
    }
}
