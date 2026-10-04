import QtQuick
import ".."

// Tiny layout diagrams use CEDAR's palette; no imported theme assets.
Item {
    id: root
    property string style: "cedar"
    Rectangle { anchors.fill: parent; color: Theme.surface; radius: 4 }
    Repeater {
        model: root.style === "islands" ? [[0.04, 0.29], [0.41, 0.18], [0.67, 0.29]]
             : root.style === "split" ? [[0.04, 0.35], [0.61, 0.35]]
             : root.style === "center" ? [[0.18, 0.64]]
             : root.style === "floating" ? [[0.05, 0.9]] : [[0, 1]]
        Rectangle {
            required property var modelData
            x: root.width * modelData[0]
            width: root.width * modelData[1]
            y: 12; height: 18
            color: Theme.background
            border.color: Config.barStyle === root.style ? Theme.green : Theme.border
            radius: root.style === "floating" ? 7 : 2
            Rectangle { x: 5; y: 7; width: Math.max(3, parent.width * 0.22); height: 3; color: Theme.green }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; y: 7; width: Math.max(3, parent.width * 0.16); height: 3; color: Theme.teal }
        }
    }
}
