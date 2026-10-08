import QtQuick
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR Station's window: a regular toplevel over the Station service.
FloatingWindow {
    id: root
    title: "CEDAR Station"
    color: Theme.background
    implicitWidth: 1120
    implicitHeight: 760
    minimumSize: Qt.size(720, 520)
    visible: true
    onVisibleChanged: if (!visible) Station.closeApp()
    CedarAtmosphere { anchors.fill: parent; active: false; visible: Config.saved.ambientIntensity > 0; opacity: Config.saved.ambientIntensity * .7 }
    StationPages { anchors.fill: parent; focus: true; onClosed: Station.closeApp() }
}
