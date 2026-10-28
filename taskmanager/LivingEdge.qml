import QtQuick
// A local filament, inherited from DropFrame's leading edge. No idle animation.
Rectangle {
    id: root
    property color accent: TM.accent
    property bool active: false
    property real signalStrength: 0
    property bool signalOn: false
    onSignalOnChanged: if(signalOn && TM.effects && visible) flash.restart()
    NumberAnimation { id: flash; target: root; property: "signalStrength"; from: 1; to: 0; duration: TM.ms(650); easing.type: Easing.OutCubic }
    color: "transparent"
    height: 1
    opacity: Math.min(1, (active ? .8 : .15)+signalStrength*.7)
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.alpha(root.accent, .08) }
        GradientStop { position: .35; color: root.accent }
        GradientStop { position: 1; color: Qt.alpha(root.accent, .08) }
    }
    Behavior on opacity { enabled: TM.motion && root.visible; NumberAnimation { duration: TM.ms(220) } }
}
