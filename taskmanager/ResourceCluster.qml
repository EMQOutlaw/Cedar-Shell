import QtQuick
import QtQuick.Layouts
import Cedar.TaskManager
import "Format.js" as F
ColumnLayout {
    id: root
    readonly property var cpu: Task.snapshot.cpu || ({})
    readonly property var memory: Task.snapshot.memory || ({})
    readonly property var gpu: (Task.snapshot.gpus || [])[0] || ({})
    spacing: 8
    GridLayout {
        Layout.fillWidth: true; columns: root.width >= 650 * Math.max(1,TM.scale*.85) ? 2 : 1; columnSpacing: 8; rowSpacing: 8
        ResourceCard { Layout.fillWidth: true; title: "01 / CPU"; accent: TM.cpu; value: F.percent(root.cpu.percent); context: F.optional(root.cpu.temperature,"°C")+"  ·  "+F.optional(root.cpu.mhz," MHz"); samples: Task.history.cpu || []; detail: root.cpu.model || "Waiting for processor telemetry"; warning: Number(root.cpu.percent)>90 }
        ResourceCard { Layout.fillWidth: true; title: "02 / Memory"; accent: TM.memory; value: F.percent(root.memory.percent); context: F.bytes(root.memory.available)+" available"; samples: Task.history.memory || []; detail: F.bytes(root.memory.used)+" used / "+F.bytes(root.memory.total); warning: Number(root.memory.percent)>90 }
        ResourceCard { Layout.fillWidth: true; title: "03 / GPU"; accent: TM.gpu; value: F.percent(root.gpu.percent); context: F.optional(root.gpu.temperature,"°C")+"  ·  VRAM "+F.bytes(root.gpu.used); samples: Task.history.gpu0 || []; detail: root.gpu.name || Task.snapshot.gpuStatus || "GPU metrics unavailable · capability discovery pending" }
        ResourceCard { Layout.fillWidth: true; title: "04 / Storage"; accent: TM.storage; value: F.rate(Task.snapshot.diskRead); context: "WRITE  "+F.rate(Task.snapshot.diskWrite); samples: Task.history.diskRead || []; ceiling: 0; detail: "Read throughput · "+(Task.snapshot.disks || []).length+" physical devices" }
    }
    Material {
        Layout.fillWidth: true; implicitHeight: Math.max(62, 52*TM.scale); accent: TM.cpu
        RowLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 18
            ColumnLayout { spacing: 2; Layout.maximumWidth: root.width*.28
                TMText { text: "05 / NETWORK"; technical: true; color: TM.cpu }
                TMText { Layout.fillWidth: true; text: (Task.snapshot.networks || []).filter(n=>n.state==="up").map(n=>n.name).join(" · ") || "All non-loopback interfaces"; secondary: true; font.pixelSize: 11*TM.scale }
            }
            ColumnLayout { spacing: 2
                TMText { text: "↓  "+F.rate(Task.snapshot.download); technical: true }
                TMText { text: "↑  "+F.rate(Task.snapshot.upload); technical: true; secondary: true }
            }
            Item { Layout.fillWidth: true; Layout.fillHeight: true
                HistoryGraph { anchors.fill: parent; samples: root.visible ? Task.history.download || [] : []; secondary: root.visible ? Task.history.upload || [] : []; maximum: 0; color: TM.cpu; secondaryColor: TM.storage }
            }
        }
    }
}
