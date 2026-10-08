import QtQuick
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR Profiles' window: a regular toplevel over the Profiles service. It
// is a presentation; closing it changes no profile.
FloatingWindow {
    id: root
    title: "CEDAR Profiles"
    color: Theme.background
    implicitWidth: 1000
    implicitHeight: 720
    minimumSize: Qt.size(720, 520)
    visible: true
    onVisibleChanged: if (!visible) Profiles.closeApp()
    CedarAtmosphere { anchors.fill: parent; active: false; visible: Config.saved.ambientIntensity > 0; opacity: Config.saved.ambientIntensity * .7 }
    ProfilesPages { anchors.fill: parent; focus: true; onClosed: Profiles.closeApp() }
}
