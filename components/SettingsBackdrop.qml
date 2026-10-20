import QtQuick
import Quickshell
import ".."
Item {
    id: root
    property real strength: .25
    clip: true
    Image {
        anchors.fill: parent
        source: Quickshell.shellPath("backgrounds/strata-forest.png")
        sourceSize.width: Math.min(1600, Math.max(1, root.width))
        asynchronous: true; fillMode: Image.PreserveAspectCrop
        opacity: root.strength
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.background, .12) }
            GradientStop { position: 1; color: Qt.alpha(Theme.background, .94) }
        }
    }
}
