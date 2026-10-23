import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Cedar.TaskManager
import "Format.js" as F
ColumnLayout {
    id: root
    property int resource: 0
    onResourceChanged: Qt.callLater(() => detailedGraph.resetScale())
    readonly property var cpu: Task.snapshot.cpu || ({})
    readonly property var mem: Task.snapshot.memory || ({})
    readonly property var gpu: (Task.snapshot.gpus || [])[0] || ({})
    readonly property var labels: ["CPU","Memory","GPU","Storage","Network"]
    readonly property var accents: [TM.cpu,TM.memory,TM.gpu,TM.storage,TM.cpu]
    readonly property var keys: ["cpu","memory","gpu0","diskRead","download"]
    readonly property var values: [F.percent(cpu.percent),F.percent(mem.percent),F.percent(gpu.percent),F.rate(Task.snapshot.diskRead),F.rate(Task.snapshot.download)]
    readonly property var details: [cpu.model || "Processor",F.bytes(mem.used)+" used / "+F.bytes(mem.total),gpu.name || Task.snapshot.gpuStatus || "GPU metrics unavailable","Physical device read throughput","Aggregate download · non-loopback interfaces"]
    spacing: 12
    Flow { Layout.fillWidth: true; spacing: 6
        Repeater { model: root.labels
            TMButton { required property string modelData; required property int index; text: modelData; checked: root.resource===index; onClicked: root.resource=index }
        }
    }
    ScrollView {
        id: scroll; Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: scroll.availableWidth; spacing: 12
            Material {
                Layout.fillWidth: true; implicitHeight: Math.max(250,Math.min(360,root.height*.49)); accent: root.accents[root.resource]; active: true; grain: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 18; spacing: 8
                    RowLayout { Layout.fillWidth: true
                        ColumnLayout { Layout.fillWidth: true; spacing: 2
                            TMHeading { text: root.labels[root.resource]+" / history"; size: 23; Layout.fillWidth: true }
                            TMText { text: root.details[root.resource]; secondary: true; Layout.fillWidth: true }
                        }
                        TMText { text: root.values[root.resource]; technical: true; font.pixelSize: (root.width<650 ? 23 : 32)*TM.scale }
                    }
                    HistoryGraph { id: detailedGraph; Layout.fillWidth: true; Layout.fillHeight: true; samples: root.visible ? Task.history[root.keys[root.resource]] || [] : []; maximum: root.resource<3 ? 100 : 0; color: root.accents[root.resource] }
                    RowLayout { Layout.fillWidth: true
                        TMText { text: root.resource<3 ? "0–100%" : "0–"+F.rate(detailedGraph.upperBound)+" · held peak"; secondary: true; technical: true }
                        Item { Layout.fillWidth: true }
                        TMText { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: "120-sample window · "+((Task.snapshot.sampleIntervalMs || 1000)/1000)+" s cadence"; technical: true; secondary: true }
                    }
                }
            }
            Loader { Layout.fillWidth: true; sourceComponent: [cpuDetails,memoryDetails,gpuDetails,storageDetails,networkDetails][root.resource] }
        }
    }
    component Fact: ColumnLayout {
        property string label: ""
        property string value: ""
        spacing: 3
        TMText { text: parent.label; technical: true; secondary: true }
        TMText { Layout.fillWidth: true; text: parent.value; font.pixelSize: 19*TM.scale; wrapMode: Text.WordWrap }
    }
    Component {
        id: cpuDetails
        ColumnLayout { spacing: 14
            Flow { Layout.fillWidth: true; spacing: 26
                Fact { width: 150*TM.scale; label: "FREQUENCY"; value: F.optional(root.cpu.mhz," MHz") }
                Fact { width: 120*TM.scale; label: "TEMPERATURE"; value: F.optional(root.cpu.temperature,"°C") }
                Fact { width: 230*TM.scale; label: "LOAD / 1 · 5 · 15 MIN"; value: (root.cpu.load || []).map(n=>Number(n).toFixed(2)).join(" / ") }
            }
            TMText { text: "LOGICAL CORES"; technical: true; color: TM.accent }
            GridLayout { Layout.fillWidth: true; columns: Math.max(2,Math.floor(width/(135*TM.scale))); columnSpacing: 6; rowSpacing: 6
                Repeater { model: root.cpu.cores || []
                    Rectangle { required property var modelData; Layout.fillWidth: true; implicitHeight: 48*TM.scale; color: TM.surface; radius: 3
                        TMText { x: 10; y: 6; text: parent.modelData.name; secondary: true; technical: true }
                        TMText { anchors.right: parent.right; anchors.rightMargin: 10; y: 6; text: F.percent(parent.modelData.percent); technical: true }
                        Rectangle { x: 10; y: parent.height-10; height: 2; width: (parent.width-20)*Math.max(0,Number(parent.modelData.percent || 0))/100; color: TM.cpu }
                    }
                }
            }
        }
    }
    Component {
        id: memoryDetails
        ColumnLayout { spacing: 14
            Flow { Layout.fillWidth: true; spacing: 26
                Fact { width: 170*TM.scale; label: "AVAILABLE"; value: F.bytes(root.mem.available) }
                Fact { width: 170*TM.scale; label: "CACHE"; value: F.bytes(root.mem.cache) }
                Fact { width: 170*TM.scale; label: "BUFFERS"; value: F.bytes(root.mem.buffers) }
            }
            ResourceCard { Layout.fillWidth: true; title: "Swap"; value: F.bytes(root.mem.swapUsed)+" / "+F.bytes(root.mem.swapTotal); detail: Number(root.mem.swapTotal)===0 ? "No swap configured" : "Swap usage history"; samples: Task.history.swap || []; accent: TM.memory }
            TMText { Layout.fillWidth: true; text: "Used = total − available. Cache and buffers are reported separately; they are not added to used memory."; secondary: true; wrapMode: Text.WordWrap }
        }
    }
    Component {
        id: gpuDetails
        ColumnLayout { spacing: 12
            TMText { Layout.fillWidth: true; visible: !(Task.snapshot.gpus || []).length; text: Task.snapshot.gpuStatus || "GPU metrics are unavailable from the current provider. This does not imply that no GPU is installed."; wrapMode: Text.WordWrap; secondary: true }
            Repeater { model: Task.snapshot.gpus || []
                ColumnLayout { required property var modelData; required property int index; Layout.fillWidth: true; spacing: 10
                    ResourceCard { visible: parent.index>0; Layout.fillWidth: true; title: parent.modelData.name; value: F.percent(parent.modelData.percent); detail: "GPU utilization"; samples: Task.history["gpu"+parent.index] || []; accent: TM.gpu }
                    ResourceCard { Layout.fillWidth: true; title: parent.modelData.name; value: F.bytes(parent.modelData.used)+" / "+F.bytes(parent.modelData.total); detail: "VRAM · "+F.optional(parent.modelData.clock," MHz")+" · "+F.optional(parent.modelData.power," W")+" · "+F.optional(parent.modelData.temperature,"°C"); samples: Task.history["vram"+parent.index] || []; ceiling: Number(parent.modelData.total || 0); accent: TM.gpu }
                }
            }
        }
    }
    Component {
        id: storageDetails
        ColumnLayout { spacing: 12
            ResourceCard { Layout.fillWidth: true; title: "Write throughput"; value: F.rate(Task.snapshot.diskWrite); samples: Task.history.diskWrite || []; ceiling: 0; accent: TM.storage; detail: "Physical leaf devices · partitions and stacked devices excluded" }
            Repeater { model: Task.snapshot.disks || []
                TMText { required property var modelData; Layout.fillWidth: true; text: modelData.name+"   ↓ "+F.rate(modelData.read)+"   ↑ "+F.rate(modelData.write); technical: true; wrapMode: Text.WordWrap }
            }
            Repeater { model: Task.snapshot.mounts || []
                TMText { required property var modelData; Layout.fillWidth: true; text: modelData.path+" · "+modelData.filesystem+"\n"+F.bytes(modelData.used)+" used / "+F.bytes(modelData.total)+" · "+F.bytes(modelData.available)+" available"; secondary: true; wrapMode: Text.WrapAnywhere }
            }
        }
    }
    Component {
        id: networkDetails
        ColumnLayout { spacing: 12
            ResourceCard { Layout.fillWidth: true; title: "Upload throughput"; value: F.rate(Task.snapshot.upload); samples: Task.history.upload || []; ceiling: 0; accent: TM.storage; detail: "All non-loopback interfaces" }
            Repeater { model: Task.snapshot.networks || []
                Material { required property var modelData; Layout.fillWidth: true; implicitHeight: info.implicitHeight+24
                    TMText { id: info; x: 12; y: 12; width: parent.width-24; text: parent.modelData.name+" / "+parent.modelData.state+"   ↓ "+F.rate(parent.modelData.download)+"   ↑ "+F.rate(parent.modelData.upload)+"\nTransferred: "+F.bytes(parent.modelData.received)+" received / "+F.bytes(parent.modelData.sent)+" sent"; wrapMode: Text.WordWrap }
                }
            }
        }
    }
}
