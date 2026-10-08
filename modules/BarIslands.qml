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
    readonly property bool centered: Config.barStyle === "center"
    readonly property bool split: Config.barStyle === "split"
    readonly property bool compact: width < 1100 || centered
    readonly property var monitor: Hyprland.monitorFor(output)
    readonly property var battery: UPower.displayDevice
    readonly property int gap: Math.max(8, Config.barSpacing)
    readonly property int sideBudget: Math.max(0, (width - clockPlate.width) / 2 - gap)
    property Region inputRegion: Region {
        Region {
            item: leftPlate
        }
        Region {
            item: rightPlate
        }
        Region {
            x: clockPlate.x
            y: clockPlate.y
            width: root.coreHost ? 0 : clockPlate.width
            height: clockPlate.height
        }
        Region {
            item: centerFrame
        }
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    HudPanel {
        id: centerFrame
        visible: root.centered
        width: visible ? Math.min(root.width, Math.max(leftPlate.width, rightPlate.width) * 2 + clockPlate.width + root.gap * 2 + 12) : 0
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        padding: 0
        fillColor: Qt.alpha(Theme.background, Config.barOpacity)
    }
    Item {
        id: leftPlate
        objectName: "barLeftPlate"
        clip: true
        x: root.centered ? centerFrame.x + 6 : 0
        width: leftRow.implicitWidth > 0 ? Math.min(leftRow.implicitWidth + 20, root.sideBudget) : 0
        height: parent.height
        HudPanel {
            anchors.fill: parent
            visible: !root.centered
            padding: 0
            fillColor: Qt.alpha(Theme.background, Config.barOpacity)
        }
        // Center uses one enclosing frame; groups retain the same controls.
        visible: width > 0
        RowLayout {
            id: leftRow
            anchors.fill: parent
            anchors.margins: 10
            spacing: Config.barSpacing
            BarButton {
                visible: Config.moduleEnabled("identity")
                text: root.compact ? "◈" : "◈ CEDAR"
                iconOnly: root.compact
                hint: "Open dashboard"
                implicitWidth: root.compact ? 36 : 108
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
                hint: "Applications"
                implicitWidth: 32
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
            Row {
                visible: Config.moduleEnabled("workspaces")
                Layout.maximumWidth: Math.max(0, leftPlate.width - (root.compact ? 110 : 190))
                clip: true
                spacing: 2
                Repeater {
                    model: Hyprland.workspaces
                    BarButton {
                        required property var modelData
                        visible: modelData.monitor?.name === root.output.name && modelData.id > 0
                        width: visible ? 32 : 0
                        implicitWidth: 32
                        text: modelData.name
                        hint: "Workspace " + modelData.name
                        checked: root.monitor?.activeWorkspace?.id === modelData.id
                        accent: modelData.urgent ? Theme.amber : Theme.green
                        onClicked: modelData.activate()
                    }
                }
                BarButton {
                    visible: Config.stage >= 3 && Config.saved.canopyEnabled
                    text: "▣"
                    iconOnly: true
                    hint: "Workspace overview (Super+Tab)"
                    accent: Theme.teal
                    anchorTopic: "workspaces"
                    canopyOutput: root.output.name
                    checked: Canopy.shown && Canopy.topic === "workspaces" && !Canopy.peeking
                    onClicked: Canopy.toggleTopic("workspaces", root.output.name)
                }
            }
        }
    }
    Item {
        id: clockPlate
        visible: !root.coreHost
        width: root.coreHost ? CoreService.reserveWidth : fallbackCore.width + 20
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        HudPanel {
            anchors.fill: parent
            visible: !root.centered
            padding: 0
            accent: Theme.green
            fillColor: Qt.alpha(Theme.background, Config.barOpacity)
        }
        BarCoreControls {
            id: fallbackCore
            anchors.centerIn: parent
            height: Math.max(24, parent.height - 16)
            outputName: root.output.name
        }
    }
    Item {
        id: rightPlate
        objectName: "barRightPlate"
        visible: width > 0
        clip: true
        width: rightRow.implicitWidth > 0 ? Math.min(rightRow.implicitWidth + 20, root.sideBudget) : 0
        x: root.centered ? centerFrame.x + centerFrame.width - width - 6 : root.width - width
        height: parent.height
        HudPanel {
            anchors.fill: parent
            visible: !root.centered
            padding: 0
            fillColor: Qt.alpha(Theme.background, Config.barOpacity)
        }
        RowLayout {
            id: rightRow
            anchors.fill: parent
            anchors.margins: 10
            spacing: Config.barSpacing
            Row {
                visible: root.width > 650 && implicitWidth > 0 && Config.moduleEnabled("tray")
                spacing: 4
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
                visible: (root.battery?.isPresent ?? false) && !root.compact && Config.moduleEnabled("battery")
                text: Math.round((root.battery?.percentage ?? 0) * 100) + "%"
                font.pixelSize: Theme.small
                color: Theme.green
            }
            BarButton {
                visible: Config.stage >= 3 && Config.moduleEnabled("notifications")
                text: "󰂚"
                iconOnly: true
                hint: "Notification history"
                implicitWidth: 32
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
