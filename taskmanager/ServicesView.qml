import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ColumnLayout {
    id: root
    property string selectedName: ""
    readonly property var selected: (Task.services || []).find(s=>s.name===selectedName) || ({})
    spacing: 10
    RowLayout { Layout.fillWidth: true
        TMHeading { Layout.fillWidth: true; text: "User services" }
        TMButton { text: "Refresh"; onClicked: Task.refreshServices() }
    }
    TMText { Layout.fillWidth: true; text: Task.serviceStatus; secondary: true; wrapMode: Text.WordWrap }
    Material {
        Layout.fillWidth: true; implicitHeight: selectedName ? details.implicitHeight+28 : 0; visible: implicitHeight>0; clip: true; active: true; grain: true
        Behavior on implicitHeight { enabled: TM.motion && root.visible; NumberAnimation { duration: TM.ms(220); easing.type: Easing.OutCubic } }
        ColumnLayout { id: details; x: 14; y: 14; width: parent.width-28; spacing: 7
            RowLayout { Layout.fillWidth: true
                TMHeading { Layout.fillWidth: true; text: root.selected.name || "Service no longer listed"; size: 20 }
                TMButton { text: "×"; onClicked: root.selectedName=""; Accessible.name: "Close service details" }
            }
            TMText { Layout.fillWidth: true; text: root.selected.description || ""; wrapMode: Text.WordWrap }
            TMText { Layout.fillWidth: true; text: "STATE  "+(root.selected.state || "Unknown"); technical: true; color: root.selected.active==="failed" ? TM.danger : TM.accent }
            TMText { Layout.fillWidth: true; text: "Read-only in Task Manager. Service management is available in Field Station."; secondary: true; wrapMode: Text.WordWrap }
        }
    }
    RowLayout { Layout.fillWidth: true
        TMText { Layout.fillWidth: true; text: "SERVICE / DESCRIPTION"; technical: true; secondary: true }
        TMText { Layout.preferredWidth: 160*TM.scale; text: "STATE / RUNNING"; technical: true; secondary: true }
    }
    ListView {
        id: list; objectName: "serviceTable"; Layout.fillWidth: true; Layout.fillHeight: true; model: Task.services; clip: true; reuseItems: true; cacheBuffer: 100
        ScrollBar.vertical: ScrollBar {}
        delegate: ItemDelegate {
            id: row; required property var modelData; width: list.width; height: Math.max(52,48*TM.scale); highlighted: root.selectedName===modelData.name
            onClicked: root.selectedName=highlighted ? "" : modelData.name
            Accessible.name: modelData.name+", "+modelData.state+", "+modelData.description
            background: Rectangle {
                color: row.highlighted ? Qt.alpha(TM.accent,.1) : row.hovered ? TM.surface : "transparent"; border.color: row.visualFocus ? TM.accent : "transparent"
                Rectangle { width: 2; height: parent.height-16; y: 8; color: row.modelData.active==="failed" ? TM.danger : TM.accent; visible: row.highlighted }
                Rectangle { height: 1; width: parent.width; anchors.bottom: parent.bottom; color: Qt.alpha(TM.border,.22) }
            }
            contentItem: RowLayout { spacing: 12
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    TMText { Layout.fillWidth: true; text: row.modelData.name }
                    TMText { Layout.fillWidth: true; text: row.modelData.description; secondary: true; font.pixelSize: 12*TM.scale }
                }
                TMText { Layout.preferredWidth: 154*TM.scale; text: row.modelData.state; technical: true; color: row.modelData.active==="failed" ? TM.danger : row.modelData.active==="active" ? TM.accent : TM.muted }
            }
        }
        TMText { anchors.centerIn: parent; visible: list.count===0; text: "No services available"; secondary: true }
    }
}
