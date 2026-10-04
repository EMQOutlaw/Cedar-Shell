import QtQuick
import QtQuick.Controls
import Quickshell
import ".."
import "../components"
import "../services"

// Omarchy-style Go menu in CEDAR glass: Apps, Learn, Trigger, Style, Setup,
// Install, Remove, Update, System and CEDAR's own panels. Typing searches the
// whole tree; Backspace on an empty search goes up one level.
Overlay {
    id: root
    panelName: "menu"
    readonly property int rowHeight: 44
    readonly property int detailRowHeight: 56
    readonly property int rowSpacing: 3
    readonly property int headerHeight: 40
    readonly property int cardWidth: Math.min(root.width - 48, Go.dmenuActive && Go.dmenuWidth ? Math.max(460, Math.round(Go.dmenuWidth * 1.15)) : 540)
    readonly property int maxListHeight: Math.min(Math.round(root.height * 0.66), Go.dmenuActive && Go.dmenuMaxHeight ? Math.round(Go.dmenuMaxHeight * 1.15) : 100000)
    readonly property int listHeight: Go.mode === "input" ? 0 : Math.min(maxListHeight, Math.max(rowHeight, list.contentHeight))
    function rowHeightFor(row) { return (Go.filterText || Go.dmenuActive) && row.detail ? detailRowHeight : rowHeight; }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    HudPanel {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(24, Math.round(root.height * 0.14))
        width: root.cardWidth
        height: Theme.padding * 2 + root.headerHeight + 8 + root.listHeight + 26
        highlighted: true
        padding: Theme.padding
        MouseArea { anchors.fill: parent; onClicked: {} }
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                const text = Go.filterText;
                if (event.key === Qt.Key_Escape) { if (text) Go.setFilter(""); else Go.cancel(); }
                else if (event.key === Qt.Key_U && event.modifiers === Qt.ControlModifier) Go.setFilter("");
                else if (event.key === Qt.Key_Backspace && text) Go.setFilter(event.modifiers & Qt.ControlModifier ? text.replace(/\s+$/, "").replace(/\S+$/, "") : text.slice(0, -1));
                else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !text) Go.goBack();
                else if (event.key === Qt.Key_Up) Go.select(-1);
                else if (event.key === Qt.Key_Down) Go.select(1);
                else if (event.key === Qt.Key_PageUp) Go.select(-6);
                else if (event.key === Qt.Key_PageDown) Go.select(6);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) Go.activateIndex(Go.selectedIndex);
                else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                         && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) Go.setFilter(text + event.text);
                else return;
                event.accepted = true;
            }
            Column {
                anchors.fill: parent
                spacing: 8
                Item {
                    width: parent.width; height: root.headerHeight
                    Column {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        GlowText {
                            width: parent.width
                            text: Go.filterText || (Go.title + (Go.mode === "input" ? "" : "…"))
                            color: Go.filterText ? Theme.text : Theme.green
                            opacity: Go.filterText ? 1 : 0.85
                            font.family: Theme.labelFont; font.pixelSize: 24; font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        GlowText {
                            width: parent.width
                            visible: text !== ""
                            text: Go.dmenuActive ? "CEDAR / PROMPT" : (Go.breadcrumb ? "GO › " + Go.breadcrumb.toUpperCase() : "GO / OMARCHY MENU")
                            color: Theme.teal; font.pixelSize: 11; elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 22; color: Theme.amber; visible: Go.mode === "input"
                        SequentialAnimation on opacity { running: root.visible && Go.mode === "input" && !Theme.reducedMotion; loops: Animation.Infinite
                            OpacityAnimator { to: 0.2; duration: 500 } OpacityAnimator { to: 1; duration: 500 } }
                    }
                }
                ListView {
                    id: list
                    width: parent.width; height: root.listHeight
                    clip: true; spacing: root.rowSpacing
                    boundsBehavior: Flickable.StopAtBounds
                    model: Go.rows
                    currentIndex: Go.selectedIndex
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: Theme.reducedMotion ? 0 : Theme.fast
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    section.property: "section"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        required property string section
                        width: ListView.view.width; height: section === "drilldown" ? 16 : 0
                        Rectangle { anchors.centerIn: parent; width: parent.width - 8; height: 1; color: Theme.border; visible: parent.section === "drilldown" }
                    }
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: index === Go.selectedIndex
                        readonly property bool isApp: modelData.kind === "app"
                        readonly property bool isMenu: modelData.kind === "menu" || modelData.kind === "link"
                        readonly property bool hasIcon: isApp || modelData.icon.length > 0
                        readonly property bool showDetail: (Go.filterText || Go.dmenuActive) && modelData.detail.length > 0
                        readonly property string appIconSource: isApp ? Quickshell.iconPath(modelData.appIcon || "application-x-executable", true) : ""
                        width: ListView.view.width
                        height: root.rowHeightFor(modelData)
                        Rectangle {
                            anchors.fill: parent
                            color: row.current ? Theme.elevated : (hover.containsMouse ? Qt.alpha(Theme.elevated, 0.5) : Theme.transparent)
                            border.color: row.current ? Theme.green : Theme.transparent
                            border.width: 1
                        }
                        Rectangle { visible: row.current; width: 3; height: parent.height - 14; anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter; color: Theme.green }
                        GlowText {
                            id: glyph
                            visible: row.hasIcon && !row.isApp
                            text: row.modelData.icon
                            color: row.current ? Theme.green : Theme.teal
                            font.family: row.modelData.iconFont || Theme.dataFont
                            font.pixelSize: 19
                            width: 34; horizontalAlignment: Text.AlignHCenter
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Image {
                            visible: row.isApp && row.appIconSource !== ""
                            source: Config.imageSource(row.appIconSource)
                            width: 22; height: 22
                            sourceSize.width: 44; sourceSize.height: 44
                            fillMode: Image.PreserveAspectFit; asynchronous: true
                            anchors.left: parent.left; anchors.leftMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 54
                            anchors.right: trail.left; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            GlowText {
                                width: parent.width
                                text: row.modelData.label
                                color: row.current ? Theme.white : Theme.text
                                font.pixelSize: 16; font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            GlowText {
                                width: parent.width; visible: row.showDetail
                                text: row.modelData.detail
                                color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight
                            }
                        }
                        GlowText {
                            id: trail
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.isMenu ? "›" : ""
                            width: row.isMenu ? 12 : 0
                            color: row.current ? Theme.green : Theme.muted; font.pixelSize: 20
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onPositionChanged: Go.selectedIndex = row.index
                            onClicked: { Go.selectedIndex = row.index; Go.activateIndex(row.index); }
                        }
                    }
                    Column {
                        anchors.centerIn: parent; spacing: 6
                        visible: Go.rows.length === 0 && Go.mode !== "input"
                        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: "󰈉"; color: Theme.teal; font.pixelSize: 30 }
                        GlowText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Go.filterText ? "No trail named “" + Go.filterText + "”" : (Go.rowsLoaded ? "Nothing here yet" : "Reading the trail map…")
                            color: Theme.muted
                        }
                    }
                }
                GlowText {
                    width: parent.width
                    text: Go.mode === "input" ? "Type, then ENTER   /   ESC cancel"
                        : Go.dmenuActive ? "Type to filter   /   ENTER choose   /   ESC cancel"
                        : (Go.filterText ? "ENTER open   /   ESC clear search" : (Go.activeMenu === "root" ? "Type to search apps and commands   /   ESC close" : "BACKSPACE back   /   ENTER open   /   ESC close"))
                    color: Theme.muted; font.pixelSize: 11; elide: Text.ElideRight
                }
            }
        }
    }
}
