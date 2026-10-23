import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Cedar.TaskManager
import "Format.js" as F
Material {
    id: root
    property var process: ({})
    property bool settled: false
    readonly property bool canAct: settled && Task.connected && !!process.identity && !process.exited && !process.protected && !Task.actionPending
    signal forceStop(string identity, string name)
    fill: TM.surface; accent: Task.actionFailed ? TM.danger : TM.accent; active: true; grain: true; texture: true
    ScrollView {
        id: scroll; anchors.fill: parent; anchors.margins: 16; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: scroll.availableWidth; spacing: 12
            RowLayout { Layout.fillWidth: true
                TMText { text: "PROCESS / INSPECTOR"; technical: true; color: TM.accent; Layout.fillWidth: true }
                TMButton { text: "×"; onClicked: Task.select(""); Accessible.name: "Close process inspector" }
            }
            RowLayout { Layout.fillWidth: true; spacing: 12
                AppIcon { iconKey: root.process.group || ""; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                TMHeading { Layout.fillWidth: true; text: root.process.name || "Process"; size: 25 }
            }
            TMText { Layout.fillWidth: true; text: root.process.exited ? "Process exited" : "PID "+root.process.pid+"  /  "+F.state(root.process.state); secondary: true }
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(TM.border,.5) }
            GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 20; rowSpacing: 12
                Repeater { model: [{label:"CPU",value:F.percent(root.process.cpu)},{label:"MEMORY",value:F.bytes(root.process.rss)},{label:"GPU MEMORY",value:F.bytes(root.process.gpuMemory)},{label:"THREADS",value:root.process.threads || "—"},{label:"RUNTIME",value:F.runtime(root.process.runtime)},{label:"OWNER",value:root.process.user || "—"}]
                    ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 2
                        TMText { text: parent.modelData.label; technical: true; secondary: true; font.pixelSize: 10*TM.scale }
                        TMText { Layout.fillWidth: true; text: parent.modelData.value; technical: true; font.pixelSize: 14*TM.scale }
                    }
                }
            }
            HistoryGraph { Layout.fillWidth: true; Layout.preferredHeight: 48; samples: root.visible ? Task.history.processCpu || [] : []; maximum: 0; color: TM.cpu }
            TMText { text: "CPU · one logical core = 100%"; secondary: true; font.pixelSize: 11*TM.scale }
            HistoryGraph { Layout.fillWidth: true; Layout.preferredHeight: 35; samples: root.visible ? Task.history.processMemory || [] : []; maximum: 0; color: TM.memory }
            TMText { text: "Resident memory · last 120 samples"; secondary: true; font.pixelSize: 11*TM.scale }
            TMText { Layout.fillWidth: true; visible: text.length>0; text: root.process.protected || ""; color: TM.warning; wrapMode: Text.WordWrap }
            TMText { Layout.fillWidth: true; visible: Task.message.length>0; text: Task.message; color: Task.actionFailed ? TM.danger : TM.accent; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
            Flow { Layout.fillWidth: true; spacing: 6; enabled: root.settled
                TMButton { text: "End process"; checked: true; enabled: root.canAct; onClicked: Task.action(root.process.identity,"term") }
                TMButton { text: "Force stop…"; danger: true; enabled: root.canAct; onClicked: root.forceStop(root.process.identity, root.process.name+" (PID "+root.process.pid+")") }
                TMButton { text: "Suspend"; enabled: root.canAct && root.process.state!=="T"; onClicked: Task.action(root.process.identity,"stop") }
                TMButton { text: "Resume"; enabled: root.canAct && root.process.state==="T"; onClicked: Task.action(root.process.identity,"continue") }
            }
            RowLayout { Layout.fillWidth: true
                SpinBox { id: priority; from: -20; to: 19; value: Number(root.process.nice || 0); editable: true; Layout.preferredWidth: 125; Accessible.name: "Process nice value" }
                TMButton { Layout.fillWidth: true; text: "Set priority"; enabled: root.canAct; onClicked: Task.action(root.process.identity,"nice",priority.value) }
            }
            TMText { Layout.fillWidth: true; text: "Higher nice values lower priority. Linux may deny raising priority."; secondary: true; font.pixelSize: 11*TM.scale; wrapMode: Text.WordWrap }
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(TM.border,.5) }
            Repeater { model: [{label:"EXECUTABLE",value:root.process.exe},{label:"COMMAND LINE",value:root.process.command},{label:"PARENT PID",value:root.process.ppid},{label:"CGROUP",value:root.process.cgroup}]
                ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 4
                    TMText { text: parent.modelData.label; technical: true; color: TM.accent; font.pixelSize: 10*TM.scale }
                    TMText { Layout.fillWidth: true; text: String(parent.modelData.value || "Unavailable"); technical: true; secondary: true; wrapMode: Text.WrapAnywhere }
                }
            }
        }
    }
}
