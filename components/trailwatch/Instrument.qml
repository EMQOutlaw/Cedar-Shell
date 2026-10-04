import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../.."

Item {
    id: root
    property string title: ""
    property string index: ""
    property string badge: ""
    property color accent: Theme.teal
    default property alias content: body.data
    implicitHeight: body.implicitHeight + 64
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Qt.alpha(Theme.surface, .88)
            strokeColor: Theme.transparent
            startX: 0
            startY: 0
            PathLine {
                x: root.width
                y: 0
            }
            PathLine {
                x: root.width
                y: root.height - 14
            }
            PathLine {
                x: root.width - 14
                y: root.height
            }
            PathLine {
                x: 0
                y: root.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.border
    }
    Rectangle {
        width: 26
        height: 2
        color: root.accent
    }
    RowLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 18
        }
        spacing: 10
        FieldText {
            text: root.index
            color: root.accent
            font.pixelSize: 11
        }
        FieldText {
            text: root.title
            font.family: Theme.labelFont
            font.bold: true
            font.letterSpacing: 2
            font.pixelSize: 17
            Layout.fillWidth: true
        }
        FieldText {
            text: root.badge
            font.pixelSize: 10
            color: Theme.muted
        }
    }
    ColumnLayout {
        id: body
        anchors {
            top: parent.top
            topMargin: 48
            left: parent.left
            right: parent.right
            margins: 18
        }
        spacing: 10
    }
}
