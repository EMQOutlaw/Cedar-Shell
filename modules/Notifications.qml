import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

Scope {
    id: root
    required property var output
    // A single popup stack, on the focused output. History is global.
    PanelWindow {
        id: popups
        screen: root.output
        visible: !ShellState.locked && ShellState.panel === "" && root.output.name === ShellState.preferredOutput() && NoticeStore.popups.length > 0
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + 12; right: 12 }
        implicitWidth: Math.min(400, root.output.width - 24)
        implicitHeight: stack.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: Theme.transparent
        WlrLayershell.namespace: "cedar-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        Column {
            id: stack
            width: parent.width
            spacing: 8
            Repeater {
                model: NoticeStore.popups.slice(-3)
                HudPanel {
                    id: card
                    required property var modelData
                    width: stack.width; implicitHeight: contents.implicitHeight + 40
                    padding: 20; highlighted: true
                    accent: modelData.urgency === 2 ? Theme.ember : Theme.teal
                    ColumnLayout {
                        id: contents
                        width: parent.width
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            GlowText { text: card.modelData.appName || "SIGNAL"; color: Theme.teal; font.family: Theme.labelFont; Layout.fillWidth: true; elide: Text.ElideRight }
                            HudButton { text: "×"; implicitWidth: 30; implicitHeight: 28; onClicked: card.modelData.dismiss() }
                        }
                        GlowText { text: card.modelData.summary; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                        GlowText { text: card.modelData.body; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; color: Theme.muted }
                        Flow {
                            Layout.fillWidth: true; spacing: 4
                            Repeater {
                                model: card.modelData.actions
                                HudButton {
                                    required property var modelData
                                    text: modelData.text; implicitHeight: 30
                                    onClicked: modelData.invoke()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Overlay {
        id: historyPanel
        output: root.output; panelName: "history"
        HudPanel {
            anchors.centerIn: parent
            width: Math.min(720, historyPanel.width - 32); height: Math.min(700, historyPanel.height - 32)
            ColumnLayout {
                anchors.fill: parent
                RowLayout {
                    GlowText { text: "FIELD NOTES / NOTIFICATIONS"; color: Theme.green; font.family: Theme.labelFont; font.pixelSize: 22; Layout.fillWidth: true }
                    HudButton { text: "CLEAR"; onClicked: NoticeStore.clear() }
                    HudButton { text: "×"; onClicked: ShellState.close() }
                }
                GlowText { visible: NoticeStore.history.length === 0; text: "No signals recorded this session."; color: Theme.muted }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
                    model: NoticeStore.history
                    ScrollBar.vertical: ScrollBar {}
                    delegate: HudPanel {
                        required property var modelData
                        width: ListView.view.width; implicitHeight: note.implicitHeight + 40
                        padding: 20
                        Column {
                            id: note; width: parent.width; spacing: 8
                            GlowText { text: (modelData.timestamp ? Config.formatTime(new Date(modelData.timestamp)) : modelData.time) + " / " + modelData.app; color: Theme.teal; width: parent.width; elide: Text.ElideRight }
                            GlowText { text: modelData.summary; color: modelData.critical ? Theme.ember : Theme.text; width: parent.width; wrapMode: Text.Wrap }
                            GlowText { text: modelData.body; color: Theme.muted; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }
}
