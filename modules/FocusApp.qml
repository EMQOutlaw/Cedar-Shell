import QtQuick
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR Focus' window: a regular toplevel over the Focus service. Closing it
// changes nothing; the session carries on.
FloatingWindow {
    id: root
    title: "CEDAR Focus"
    color: Theme.background
    implicitWidth: 900
    implicitHeight: 760
    minimumSize: Qt.size(720, 520)
    visible: true
    onVisibleChanged: if (!visible) Focus.closeApp()
    CedarAtmosphere { anchors.fill: parent; active: false; visible: Config.saved.ambientIntensity > 0; opacity: Config.saved.ambientIntensity * .7 }
    FocusPages { anchors.fill: parent; focus: true; onClosed: Focus.closeApp() }
}
