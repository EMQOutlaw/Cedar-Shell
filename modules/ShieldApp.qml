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

    // Quiet filaments at the window's foot, drawn once; the spores never move
    // here because a toplevel that animates re-renders every window on every
    // output. Ambient intensity 0 removes it entirely.
    CedarAtmosphere {
        anchors.fill: parent
        active: false
        visible: Config.saved.ambientIntensity > 0
        opacity: Config.saved.ambientIntensity * .7
    }
    ShieldPages {
        anchors.fill: parent
        focus: true
        onClosed: Shield.closeApp()
    }
}
