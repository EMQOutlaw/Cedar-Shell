import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components/core/StrataGeometry.js" as Strata
Item {
    id: root
    property bool overview: true
    property bool searchOpen: false
    property alias searchField: search
    property var retained: ({})
    property real rowAnchor: 60
    readonly property bool inspecting: !!Task.selected.identity
    readonly property bool wide: width >= 1020 * Math.max(1,TM.scale*.9)
    signal forceStop(string identity, string name)
    function openSearch() { searchOpen=true;searchFocus.restart(); }
    Timer { id: searchFocus; interval: TM.ms(120)+1; onTriggered: search.forceActiveFocus() }
    function dismiss() { if(inspecting) Task.select(""); else if(searchOpen) {search.text="";searchOpen=false;} }
    Connections { target: Task; function onChanged() { if(Task.selected.identity) root.retained=Task.selected; } }
    ScrollView {
        id: viewport; anchors.fill: parent; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: viewport.availableWidth
            height: Math.max(implicitHeight, viewport.availableHeight)
            spacing: 10
            ResourceCluster { visible: root.overview; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                TMHeading { text: root.overview ? "Processes" : "Applications & processes"; size: 21; Layout.fillWidth: true }
                TMText { text: Task.processCount+" visible"; technical: true; secondary: true; visible: root.width>620 }
                TMButton { text: root.searchOpen ? "Close search" : "Search"; checked: root.searchOpen; onClicked: {if(root.searchOpen){search.text="";root.searchOpen=false;}else root.openSearch();} }
                TMButton { id: filterButton; text: "Filter"; checked: own.checked || grouped.checked || state.currentIndex>0; onClicked: filterMenu.open() }
                Popup { id: filterMenu; parent: filterButton; y: filterButton.height+4; x: Math.min(0,root.width-filterButton.mapToItem(root,0,0).x-width); width: 240; padding: 14
                    background: Rectangle { color: TM.surface; border.color: TM.border; radius: 6 }
                    contentItem: ColumnLayout {
                        CheckBox { id: own; text: "My processes"; onToggled: searchDelay.restart() }
                        CheckBox { id: grouped; text: "Group applications"; onToggled: searchDelay.restart() }
                        ComboBox { id: state; Layout.fillWidth: true; model: ["All states","R","S","D","T","Z","I"]; onActivated: searchDelay.restart(); Accessible.name: "Filter process state" }
                    }
                }
            }
            Item {
                Layout.fillWidth: true; implicitHeight: root.searchOpen ? 36*TM.scale : 0
                visible: implicitHeight>0; clip: true
                Behavior on implicitHeight { enabled: TM.motion; NumberAnimation { duration: TM.ms(180); easing.type: Easing.OutCubic } }
                TextField {
                id: search; objectName: "processSearch"; anchors.left: parent.left; anchors.right: parent.right
                height: 36*TM.scale
                placeholderText: "Search application, process or PID…"; selectByMouse: true
                color: TM.text; placeholderTextColor: TM.muted; font.family: TM.font; font.pixelSize: 14*TM.scale
                background: Rectangle { radius: 4; color: Qt.alpha(TM.accent,.04); border.color: search.activeFocus ? TM.accent : TM.border }
                onTextChanged: searchDelay.restart()
                Keys.onEscapePressed: { text="";root.searchOpen=false; }
                Accessible.name: "Search processes"
                }
            }
            Timer { id: searchDelay; interval: 160; onTriggered: Task.filter(search.text,state.currentIndex?state.currentText:"",own.checked,grouped.checked) }
            Item {
                id: workspace; Layout.fillWidth: true; Layout.fillHeight: true
                Layout.minimumHeight: root.inspecting && root.wide ? 370 : 210
                property real reveal: root.inspecting ? 1 : 0
                Behavior on reveal { enabled: TM.motion && root.visible; NumberAnimation { id: morph; duration: TM.ms(root.inspecting ? 320 : 200); easing.type: Easing.OutCubic } }
                readonly property real wantedWidth: Strata.panelWidth(width, 350*TM.scale, 0)
                readonly property real paneWidth: root.wide ? wantedWidth*reveal : width
                ProcessTable {
                    id: table; x: 0; y: 0
                    width: workspace.width-(root.wide ? workspace.paneWidth+(workspace.reveal*10) : 0)
                    height: workspace.height
                    grouped: grouped.checked
                    onSelectedRow: y => root.rowAnchor=Math.max(30,Math.min(height-5,y))
                }
                // Tie line remains attached to the selected row while the frame unfolds.
                LivingEdge { x: table.width-20; y: root.rowAnchor; width: 30; visible: root.wide && workspace.reveal>0; opacity: workspace.reveal; active: true }
                Item {
                    objectName: "processInspector"; id: inspectorPanel
                    parent: root.wide ? workspace : root
                    z: 5
                    x: root.wide ? workspace.width-width : 0; y: root.wide ? 0 : root.height-height
                    width: root.wide ? workspace.paneWidth : root.width; height: root.wide ? workspace.height : Strata.panelHeight(root.height, Math.min(540,root.height*.82), 0)*workspace.reveal; visible: workspace.reveal>0; clip: true
                    ProcessInspector {
                        width: root.wide ? workspace.wantedWidth : parent.width; height: root.wide ? parent.height : Strata.panelHeight(root.height, Math.min(540,root.height*.82), 0)
                        process: root.retained; settled: root.inspecting && workspace.reveal>.995
                        opacity: Math.max(0,(workspace.reveal-.35)/.65)
                        onForceStop: (identity,name) => root.forceStop(identity,name)
                    }
                }
            }
            TMText { Layout.fillWidth: true; text: (Task.snapshot.errors || []).join(" · "); visible: text.length>0; color: TM.warning; wrapMode: Text.WordWrap }
        }
    }
}
