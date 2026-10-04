import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../components"

PanelWindow {
    id: root
    required property var output
    property string selectedWallpaper: ""
    screen: output
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.background
    WlrLayershell.namespace: "cedar-background"
    WlrLayershell.layer: WlrLayer.Background
    mask: Region {}
    Process {
        id: readWallpaper
        command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
        stdout: StdioCollector { onStreamFinished: root.selectedWallpaper = text.trim() }
    }
    Timer {
        interval: 1500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!readWallpaper.running) readWallpaper.running = true
    }
    Image {
        anchors.fill: parent
        source: root.selectedWallpaper ? "file://" + root.selectedWallpaper : Quickshell.shellPath("themes/backgrounds/field-station.png")
        fillMode: Config.saved.wallpaperMode === "fit" ? Image.PreserveAspectFit : Config.saved.wallpaperMode === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }
    Column {
        visible: Config.saved.desktopSignature
        anchors { right: parent.right; bottom: parent.bottom; margins: 52 }
        spacing: 8
        GlowText { text: "F O X F I R E"; font.family: Theme.labelFont; font.pixelSize: 38; color: Theme.green; opacity: 0.5 }
        GlowText { text: "A COLD, LIVING LIGHT IN THE DARK WOODS"; font.pixelSize: 10; color: Theme.muted }
    }
}
