import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

Item {
    id: root
    required property var output
    readonly property bool coreHost: CoreService.enabled && CoreService.hostName === output.name
    readonly property real centerWidth: root.coreHost ? CoreService.reserveWidth : fallbackCore.width
    readonly property var monitor: Hyprland.monitorFor(output)
    readonly property var battery: UPower.displayDevice
    BarCoreControls {
        id: fallbackCore
        visible: !root.coreHost
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(24, parent.height - 8)
        outputName: root.output.name
    }
    Item {
        anchors.fill: parent
        RowLayout {
            id: leftControls
            objectName: "barLeftControls"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, (parent.width - root.centerWidth) / 2 - 8)
            spacing: Config.barSpacing
            clip: true
            BarButton {
                visible: Config.moduleEnabled("identity")
                // The wordmark: spaced capitals in the interface face, no glyph.
                text: "CEDAR"
                fontFamily: Theme.labelFont
                fontSize: Theme.small + 2
                letterSpacing: 3
                hint: "Open dashboard"
                anchorTopic: "station"
                checked: Canopy.shown && Canopy.topic === "station" && !Canopy.peeking
                onClicked: {
                    if (Config.stage < 2)
                        return;
                    if (Config.saved.canopyEnabled)
                        Canopy.toggleTopic("station", root.output.name);
                    else
                        ShellState.toggle("hud");
                }
            }
            BarButton {
                visible: Config.stage >= 3 && Config.moduleEnabled("go")
                text: "󰀻"
                iconOnly: true
                quiet: true
                hint: "Applications"
                accent: Theme.teal
                anchorTopic: "go"
                checked: Canopy.shown && Canopy.topic === "go" && !Canopy.peeking
                onClicked: {
                    if (Config.saved.canopyEnabled)
                        Canopy.toggleTopic("go", root.output.name);
                    else
                        Go.toggle("root");
                }
            }
            // A thin divider sets the workspace row apart from the wordmark.
            Rectangle {
                visible: Config.moduleEnabled("workspaces")
                Layout.alignment: Qt.AlignVCenter
                width: 1; height: 14
                color: Qt.alpha(Theme.border, .9)
            }
            Row {
                id: workspaceRow
                visible: Config.moduleEnabled("workspaces")
                spacing: 1
                // The active mark glides between workspaces instead of jumping.
                property real markX: 0
                property real markWidth: 14
                Rectangle {
                    id: workspaceMark
                    x: workspaceRow.markX; y: parent.height - 3; width: workspaceRow.markWidth; height: 2; radius: 1
                    color: Theme.green; opacity: .95
                    Behavior on x { enabled: VisualQuality.effects; NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow); easing.type: Easing.OutBack } }
                }
                Repeater {
                    model: Hyprland.workspaces
                    BarButton {
                        id: wsButton
                        required property var modelData
                        visible: modelData.monitor?.name === root.output.name && modelData.id > 0
                        width: visible ? 30 : 0
                        implicitWidth: 30
                        // Numbered workspaces read as a count: 01, 02, 03. Named ones keep their names.
                        text: /^\d+$/.test(modelData.name) ? modelData.name.padStart(2, "0") : modelData.name
                        hint: "Workspace " + modelData.name
                        checked: root.monitor?.activeWorkspace?.id === modelData.id
                        glide: true
                        quiet: true
                        accent: modelData.urgent ? Theme.amber : Theme.green
                        onClicked: modelData.activate()
                        function place() { if (checked && visible) { workspaceRow.markX = x + (width - workspaceRow.markWidth) / 2; } }
                        onCheckedChanged: place()
                        onXChanged: place()
                        Component.onCompleted: place()
                    }
                }
                // The overview grows out of the workspace region: this is its origin.
                BarButton {
                    visible: Config.stage >= 3 && Config.saved.canopyEnabled
                    text: "▣"
                    iconOnly: true
                    quiet: true
                    hint: "Workspace overview (Super+Tab)"
                    accent: Theme.teal
                    anchorTopic: "workspaces"
                    canopyOutput: root.output.name
                    checked: Canopy.shown && Canopy.topic === "workspaces" && !Canopy.peeking
                    onClicked: Canopy.toggleTopic("workspaces", root.output.name)
                }
            }
            Rectangle {
                visible: Config.moduleEnabled("activeWindow") || Config.saved.barWhispers
                Layout.alignment: Qt.AlignVCenter
                width: 1; height: 14
                color: Qt.alpha(Theme.border, .9)
            }
            // Whispers: the window title, a contextual line as things happen, a curated line otherwise.
            CedarWhispers {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                height: implicitHeight
                windowTitle: Config.moduleEnabled("activeWindow") ? (Hyprland.activeToplevel?.title || "") : ""
                fontSize: Theme.small
                color: Qt.alpha(Theme.muted, .8)
            }
        }
        RowLayout {
            id: rightControls
            objectName: "barRightControls"
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, (parent.width - root.centerWidth) / 2 - 8)
            spacing: Config.barSpacing
            clip: true
            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            // Canopy Pulse: real audio levels while something plays, opt-in.
            CanopyPulse {
                visible: Config.saved.barPulse && VisualQuality.effects && Motion.active && !!(Media.player && Media.player.isPlaying)
                Layout.alignment: Qt.AlignVCenter
                tone: Theme.teal
            }
            Row {
                visible: root.width > 650 && implicitWidth > 0 && Config.moduleEnabled("tray")
                spacing: Config.barSpacing
                Repeater {
                    model: SystemTray.items
                    Item {
                        id: trayItem
                        required property var modelData
                        width: modelData.status === Status.Passive ? 0 : 32
                        height: Math.max(24, Config.barHeight - 16)
                        visible: width > 0
                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: trayMouse.containsMouse ? Qt.alpha(Theme.text, 0.07) : Theme.transparent
                        }
                        Image {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: Config.imageSource(trayItem.modelData.icon)
                        }
                        MouseArea {
                            id: trayMouse
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton)
                                    trayItem.modelData.secondaryActivate();
                                else if (mouse.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                                    if (trayItem.modelData.hasMenu)
                                        trayMenu.open();
                                } else
                                    trayItem.modelData.activate();
                            }
                            onWheel: event => trayItem.modelData.scroll(event.angleDelta.y, false)
                        }
                        QsMenuAnchor {
                            id: trayMenu
                            menu: trayItem.modelData.menu
                            anchor.item: trayItem
                            anchor.edges: Edges.Bottom
                            anchor.gravity: Edges.Bottom
                        }
                    }
                }
            }

            GlowText {
                visible: (root.battery?.isPresent ?? false) && Config.moduleEnabled("battery")
                text: "BAT " + Math.round((root.battery?.percentage ?? 0) * 100) + "%"
                color: root.battery?.percentage < 0.2 ? Theme.amber : Theme.green
                font.pixelSize: Theme.small
            }
            BarButton {
                visible: Config.stage >= 3 && Config.moduleEnabled("notifications")
                text: "󰂚"
                iconOnly: true
                quiet: true
                hint: "Notification history"
                canopyOutput: root.output.name
                canopyTopic: "notifications"
                checked: Canopy.shown && Canopy.topic === "notifications" && !Canopy.peeking
                onClicked: {
                    if (!Config.saved.canopyEnabled)
                        ShellState.toggle("history");
                    else if (checked)
                        Canopy.close();
                    else
                        Canopy.open("notifications", root.output.name);
                }
            }
        }
    }
}
