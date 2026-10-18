import QtQuick
import ".."

// A small printed setting in the paper header (paper type, size) that changes
// when clicked. It looks like print until hovered; flash() briefly explains a
// refused change.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Item {
    id: root

    property string text: ""
    property string action: ""
    property string shortcut: ""
    // While exporting, hover outlines and tooltips stay off the image.
    property bool quiet: false
    property string notice: ""
    property QtObject theme
    signal activated()

    function flash(message) {
        notice = message
        noticeTimer.restart()
    }

    width: label.implicitWidth + 12
    height: 22

    Accessible.role: Accessible.Button
    Accessible.name: text + ". " + action + (shortcut === "" ? "" : " (" + shortcut + ")")
    Accessible.onPressAction: root.activated()

    // One-shot: the notice fades after the OSD's dwell.
    Timer {
        id: noticeTimer

        interval: Theme.osdDuration
        onTriggered: root.notice = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: mouse.pressed ? Qt.alpha(root.theme.ink, .1) : Theme.transparent
        border.width: 1
        border.color: mouse.containsMouse && !root.quiet ? root.theme.printInk : Theme.transparent
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: mouse.containsMouse && !root.quiet ? root.theme.ink : root.theme.printInk
        font.family: Theme.dataFont
        font.pixelSize: 9
        font.letterSpacing: 1.2
        textFormat: Text.PlainText
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    // Right-aligned: these labels sit at the paper's right edge, so the tooltip
    // opens over the paper rather than out toward the toolbar.
    NotesTooltip {
        x: root.width - width
        theme: root.theme
        text: root.notice || root.action
        shortcut: root.notice === "" ? root.shortcut : ""
        side: "bottom"
        hovered: mouse.containsMouse && !root.quiet
        force: root.notice !== "" && !root.quiet
        alert: root.notice !== ""
    }
}
