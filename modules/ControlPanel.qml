import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

Rectangle {
    id: root
    property bool active: false
    property string tab: "quick"
    readonly property var player: Media.player
    color: Qt.alpha(Theme.background, Config.panelOpacity)
    radius: Config.panelRadius
    border.color: Qt.alpha(Theme.teal, .18)
    CedarAtmosphere {
        anchors.fill: parent
        active: root.active && Config.saved.ambientIntensity > 0
        opacity: Config.saved.ambientIntensity
    }
    MouseArea {
        anchors.fill: parent
    }
    onActiveChanged: if (active)
        Controls.refresh()
    Item {
        anchors.fill: parent
        anchors.margins: 28
        Item {
            id: heading
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 54
            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                GlowText {
                    text: "CEDAR"
                    font.family: Theme.labelFont
                    font.pixelSize: 26
                    font.letterSpacing: 4
                }
                GlowText {
                    text: "QUICK CONTROLS"
                    color: Theme.teal
                    font.pixelSize: 11
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                StationButton {
                    text: "Settings"
                    onClicked: ShellState.toggle("settings")
                }
                StationButton {
                    text: "×"
                    onClicked: ShellState.close()
                }
            }
        }
        Row {
            id: tabs
            anchors.top: heading.bottom
            anchors.topMargin: 12
            spacing: 8
            Repeater {
                model: [
                    {
                        id: "quick",
                        label: "Quick controls"
                    },
                    {
                        id: "network",
                        label: "Connections"
                    },
                    {
                        id: "bluetooth",
                        label: "Bluetooth"
                    }
                ]
                StationButton {
                    required property var modelData
                    text: modelData.label
                    checked: root.tab === modelData.id
                    onClicked: root.tab = modelData.id
                }
            }
        }
        ScrollView {
            id: scroll
            anchors.top: tabs.bottom
            anchors.topMargin: 20
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: scroll.availableWidth
                spacing: 20
                QuickControls {
                    Layout.fillWidth: true
                    visible: root.tab === "quick"
                    active: root.active && visible
                }
                ConnectionSettings {
                    Layout.fillWidth: true
                    visible: root.tab === "network"
                    active: root.active && visible
                }
                BluetoothSettings {
                    Layout.fillWidth: true
                    visible: root.tab === "bluetooth"
                }
            }
        }
    }
}
