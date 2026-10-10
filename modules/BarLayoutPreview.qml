import QtQuick
import ".."
import "../components"

// Tiny layout diagrams use CEDAR's palette; no imported theme assets.
Item {
    id: root
    property string style: "cedar"
    Rectangle { anchors.fill: parent; color: Theme.surface; radius: 4 }
    Item {
        visible: root.style === "cedar"
        width: parent.width
        y: 7; height: 28
        StrataBarFrame { anchors.fill: parent; centerWidth: parent.width * .24 }
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Rectangle { width: 12; height: 3; color: Theme.strataText; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: 3
                Rectangle { required property int index; width: 5; height: 5; color: index === 1 ? Theme.strataAccent : Theme.strataGrain }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 7; height: 7; radius: 3.5
            color: Theme.transparent
            border.color: Theme.strataAccent
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Repeater { model: 3; Rectangle { width: 3; height: 3; color: Theme.strataMuted; anchors.verticalCenter: parent.verticalCenter } }
            Rectangle { width: 12; height: 3; color: Theme.strataText; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 5; height: 5; color: Theme.strataGrain }
        }
    }
    Repeater {
        model: root.style === "cedar" ? []
             : root.style === "islands" ? [[0.04, 0.29], [0.41, 0.18], [0.67, 0.29]]
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
