// Standalone, non-locking preview: qs -p ~/Work/cedar-shell/trailwatch-preview.qml
import QtQuick
import Quickshell
import "modules"

ShellRoot {
    QtObject {
        id: auth
        property bool busy: false
        property string status: "Preview only"
        signal clearInputs
    }
    FloatingWindow {
        visible: true
        implicitWidth: 1600
        implicitHeight: 1000
        title: "CEDAR Trailwatch · Visual preview"
        TrailwatchView {
            anchors.fill: parent
            auth: auth
            active: true
            preview: true
            onSubmitted: value => auth.clearInputs()
        }
    }
}
