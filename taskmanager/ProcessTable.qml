import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Format.js" as F
ColumnLayout {
    id: root
    property bool grouped: false
    property string sortKey: "cpu"
    property bool descending: true
    signal selectedRow(real y)
    spacing: 0
    readonly property real cpuWidth: 66*TM.scale
    readonly property real memWidth: 91*TM.scale
    readonly property real gpuWidth: width>620*TM.scale ? 85*TM.scale : 0
    readonly property real stateWidth: width>430*TM.scale ? 83*TM.scale : 42*TM.scale
    function move(delta) { table.currentIndex=Math.max(0, Math.min(table.count-1,table.currentIndex+delta)); table.positionViewAtIndex(table.currentIndex,ListView.Contain); if(table.currentItem) { Task.select(table.currentItem.identity); root.selectedRow(table.currentItem.y-table.contentY+header.height+20); } }
    RowLayout {
        id: header; Layout.fillWidth: true; spacing: 0
        Repeater {
            model: [{label:"APPLICATION",key:"name",w:0},{label:"CPU",key:"cpu",w:root.cpuWidth},{label:"MEMORY",key:"rss",w:root.memWidth},{label:"GPU MEM",key:"gpuMemory",w:root.gpuWidth},{label:"STATE",key:"state",w:root.stateWidth}]
            TMButton {
                required property var modelData
                visible: modelData.key!=="gpuMemory" || root.gpuWidth>0
                Layout.fillWidth: modelData.key==="name"; Layout.preferredWidth: modelData.w; Layout.minimumWidth: modelData.w
                implicitWidth: 0; implicitHeight: 30*TM.scale
                alignment: modelData.key==="name" ? Text.AlignLeft : Text.AlignHCenter
                text: modelData.label+(root.sortKey===modelData.key ? (root.descending ? " ↓" : " ↑") : "")
                font.family: TM.mono; font.pixelSize: 10*TM.scale
                background: Rectangle { color: parent.hovered ? TM.elevated : "transparent"; border.color: parent.visualFocus ? TM.accent : "transparent" }
                onClicked: { root.descending=root.sortKey===modelData.key?!root.descending:!["name","state"].includes(modelData.key);root.sortKey=modelData.key;Task.sort(modelData.key); }
                Accessible.name: "Sort by "+modelData.label
            }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(TM.border,.5) }
    ListView {
        id: table; objectName: "processTable"; Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; reuseItems: true; cacheBuffer: 96; model: Task.processes; boundsBehavior: Flickable.StopAtBounds
        focus: true; keyNavigationEnabled: false
        Keys.onDownPressed: root.move(1)
        Keys.onUpPressed: root.move(-1)
        Keys.onReturnPressed: if(currentItem) Task.select(currentItem.identity)
        ScrollBar.vertical: ScrollBar {}
        section.property: root.grouped ? "appGroup" : ""
        section.delegate: Rectangle { required property string section; width: table.width; height: 27*TM.scale; color: TM.elevated; TMText { anchors.fill: parent; anchors.leftMargin: 12; text: parent.section; color: TM.accent; verticalAlignment: Text.AlignVCenter; technical: true } }
        delegate: ItemDelegate {
            id: row; objectName: "processRow"
            required property int index
            required property string identity
            required property string processName
            required property string appGroup
            required property int pid
            required property var cpu
            required property double rss
            required property var gpuMemory
            required property string processState
            required property string owner
            width: table.width; height: Math.max(42,38*TM.scale); padding: 0
            function updateAnchor() { if(highlighted)root.selectedRow(y-table.contentY+header.height+height/2); }
            onYChanged: updateAnchor()
            Connections { target: table; function onContentYChanged(){ row.updateAnchor(); } }
            highlighted: Task.selected.identity===identity
            onHighlightedChanged: if(highlighted) Qt.callLater(updateAnchor)
            onClicked: { table.currentIndex=index;table.forceActiveFocus();Task.select(identity);root.selectedRow(y-table.contentY+header.height+height/2); }
            Keys.onDownPressed: root.move(1)
            Keys.onUpPressed: root.move(-1)
            background: Rectangle {
                color: row.highlighted ? Qt.alpha(TM.accent,.10) : row.hovered ? Qt.alpha(TM.accent,.045) : "transparent"
                border.color: row.visualFocus || table.activeFocus && table.currentIndex===row.index ? Qt.alpha(TM.accent,.8) : "transparent"
                Rectangle { x: 0; width: 2; height: parent.height-12; y: 6; color: TM.accent; visible: row.highlighted }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(TM.border,.18) }
            }
            contentItem: RowLayout {
                spacing: 0
                RowLayout { Layout.fillWidth: true; spacing: 10; Layout.leftMargin: 10; Layout.rightMargin: 8
                    AppIcon { iconKey: row.appGroup; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                        TMText { Layout.fillWidth: true; text: row.processName; font.pixelSize: 14*TM.scale }
                        TMText { Layout.fillWidth: true; text: row.pid+"  ·  "+row.owner; technical: true; secondary: true; font.pixelSize: 9*TM.scale }
                    }
                }
                TMText { Layout.preferredWidth: root.cpuWidth; text: F.percent(row.cpu); technical: true; color: Number(row.cpu)>90 ? TM.warning : TM.text; horizontalAlignment: Text.AlignHCenter }
                TMText { Layout.preferredWidth: root.memWidth; text: F.bytes(row.rss); technical: true; horizontalAlignment: Text.AlignHCenter }
                TMText { visible: root.gpuWidth>0; Layout.preferredWidth: root.gpuWidth; text: F.bytes(row.gpuMemory); technical: true; secondary: true; horizontalAlignment: Text.AlignHCenter }
                TMText { Layout.preferredWidth: root.stateWidth; text: root.stateWidth>60 ? F.state(row.processState) : row.processState; secondary: true; font.pixelSize: 11*TM.scale; horizontalAlignment: Text.AlignHCenter }
            }
            Accessible.name: processName+", PID "+pid+", CPU "+F.percent(cpu)+", memory "+F.bytes(rss)+", "+F.state(processState)
        }
        TMText { anchors.centerIn: parent; visible: table.count===0; text: Task.connected ? "No matching processes" : "Waiting for collector"; secondary: true }
    }
}
