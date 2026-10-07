import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR Shield's window: a regular toplevel (Hyprland tiles or floats it),
// opaque surfaces in three depths, a restrained sidebar that turns into a
// tab strip when narrow, and the pages. The window remembers its size. It
// is a presentation over the Shield service: closing it changes nothing.
FloatingWindow {
    id: root
    title: "CEDAR Shield"
    color: Theme.background
    implicitWidth: Shield.windowSize.width
    implicitHeight: Shield.windowSize.height
    minimumSize: Qt.size(720, 520)
    visible: true
    onVisibleChanged: if (!visible) Shield.closeApp()
    onWidthChanged: remember.restart()
    onHeightChanged: remember.restart()
    Timer { id: remember; interval: 600; onTriggered: Shield.rememberWindow(root.width, root.height) }

    ShieldPages {
        anchors.fill: parent
        focus: true
        onClosed: Shield.closeApp()
    }
}
