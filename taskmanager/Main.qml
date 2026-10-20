import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Cedar.TaskManager
ApplicationWindow {
    id: win
    title: "CEDAR Task Manager"
    width: Math.min(Task.preferences.width || 1180, Screen.desktopAvailableWidth || 1280)
    height: Math.min(Task.preferences.height || 820, Screen.desktopAvailableHeight || 900)
    minimumWidth: 520; minimumHeight: 440
    visible: true
    color: Task.style.background
    font.family: Task.style.font || "sans-serif"
    font.pixelSize: 14 * (Task.style.fontScale || 1)
    palette.window: Task.style.background
    palette.base: Task.style.surface
    palette.button: Task.style.elevated
    palette.text: Task.style.text
    palette.buttonText: Task.style.text
    palette.highlight: Task.style.teal
    palette.highlightedText: Task.style.background
    property int page: Task.preferences.page || 0
    property bool exiting: false
    property string confirmationIdentity: ""
    property string confirmationName: ""
    readonly property var cpu: Task.snapshot.cpu || ({})
    readonly property var memory: Task.snapshot.memory || ({})
    readonly property var gpus: Task.snapshot.gpus || []
    readonly property bool hasGpu: gpus.length > 0
    readonly property var selected: Task.selected
    readonly property bool inspector: !!selected.identity
    readonly property bool canAct: Task.connected && inspector && !selected.exited && !selected.protected && !Task.actionPending
    readonly property bool wide: width >= 1060 * Math.max(1, Task.style.fontScale || 1)
    function known(v) { return v !== undefined && v !== null && isFinite(Number(v)); }
    function percent(v) { return known(v) ? Number(v).toFixed(1) + "%" : "Unavailable"; }
    function bytes(v) { if (!known(v)) return "—"; const units=["B","KiB","MiB","GiB","TiB"]; let n=Number(v),i=0; while(n>=1024 && i<4){n/=1024;i++;} return n.toFixed(i ? 1 : 0)+" "+units[i]; }
    function rate(v) { return known(v) ? bytes(v)+"/s" : "Unavailable"; }
    function optional(v,suffix) { return known(v) ? Number(v).toFixed(0)+suffix : "Unavailable"; }
    function history(key) { return Task.history[key] || []; }
    onVisibilityChanged: value => Task.visibility(visible && value !== Window.Minimized)
    onPageChanged: { if(page===3) Task.refreshServices(); if(!Task.style.reducedMotion) pageFade.restart(); }
    onClosing: event => {
        Task.savePreferences(width,height,page);
        if(!exiting && !Task.style.reducedMotion){event.accepted=false;closeAnimation.start();}
    }
    NumberAnimation { id: closeAnimation; target: win; property: "opacity"; to: 0; duration: 110; onFinished: {win.exiting=true;win.close();} }
    Component.onCompleted: { if (!Task.style.reducedMotion) openAnimation.start(); }
    NumberAnimation { id: openAnimation; target: win; property: "opacity"; from: 0; to: 1; duration: 140 }
    NumberAnimation { id: pageFade; target: stack; property: "opacity"; from: 0.7; to: 1; duration: 140 }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Escape"; onActivated: if(confirm.opened)confirm.close();else Task.select("") }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.page=0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.page=1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.page=2 }
    Shortcut { sequence: "Ctrl+4"; onActivated: win.page=3 }
    header: ColumnLayout {
        spacing: 12
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 18
            Rectangle { width: 4; height: 28; radius: 2; color: Task.style.teal }
            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: "CEDAR  |  TASK MANAGER"; color: Task.style.text; font.pixelSize: win.width<650 ? 16:22; font.letterSpacing: 1; elide: Text.ElideRight }
            Rectangle { width: 7; height: 7; radius: 4; color: Task.connected ? Task.style.green : Task.style.amber }
            Text { textFormat: Text.PlainText; visible: win.width>750; text: Task.status; color: Task.style.muted; font.pixelSize: 12 }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 12
            Repeater {
                model: ["Overview","Processes","Performance","Services"]
                TMButton { required property string modelData; required property int index; Layout.fillWidth: true; text: modelData; checked: win.page===index; onClicked: win.page=index }
            }
        }
    }
    footer: Rectangle {
        implicitHeight: footerText.implicitHeight+20; color: Task.style.surface
        Text { textFormat: Text.PlainText; id: footerText; anchors.fill: parent; anchors.margins: 10; color: Task.connected ? Task.style.muted : Task.style.amber; font.pixelSize: 12; wrapMode: Text.WordWrap; text: Task.message || (Task.connected ? Task.gaming+" · CPU 100% = one logical core in Processes · History: 120 samples" : Task.status) }
    }
    StackLayout {
        id: stack
        anchors.fill: parent; anchors.margins: 18
        currentIndex: win.page
        ScrollView {
            id: overview; clip: true; contentWidth: availableWidth
            GridLayout {
                width: overview.availableWidth; columns: width>=850 ? 2:1; columnSpacing: 14; rowSpacing: 14
                ResourceCard { Layout.fillWidth: true; title: "CPU"; value: win.percent(win.cpu.percent); samples: win.history("cpu"); detail: (win.cpu.model||"Processor unavailable")+"\n"+win.optional(win.cpu.temperature,"°C")+" · "+win.optional(win.cpu.mhz," MHz") }
                ResourceCard { Layout.fillWidth: true; title: "Memory"; value: win.percent(win.memory.percent); samples: win.history("memory"); detail: win.bytes(win.memory.used)+" / "+win.bytes(win.memory.total)+" · Used = total − available" }
                Repeater {
                    model: win.hasGpu ? win.gpus : [{name:"GPU unavailable",percent:null}]
                    ResourceCard { required property var modelData; required property int index; Layout.fillWidth: true; title: modelData.name; value: win.percent(modelData.percent); samples: win.history("gpu"+index); detail: win.hasGpu ? "VRAM "+win.bytes(modelData.used)+" / "+win.bytes(modelData.total)+" · "+win.optional(modelData.temperature,"°C")+" · "+win.optional(modelData.power," W") : Task.snapshot.gpuStatus || "Waiting for GPU capabilities" }
                }
                ResourceCard { Layout.fillWidth: true; title: "Storage activity"; value: win.rate(Task.snapshot.diskRead); ceiling: 0; samples: win.history("diskRead"); detail: "Read · Write "+win.rate(Task.snapshot.diskWrite)+"\nPhysical devices; partitions and stacked devices excluded" }
                ResourceCard { Layout.fillWidth: true; title: "Network"; value: win.rate(Task.snapshot.download); ceiling: 0; samples: win.history("download"); detail: "Download · Upload "+win.rate(Task.snapshot.upload)+"\nAll interfaces except loopback" }
                Text { textFormat: Text.PlainText; Layout.fillWidth: true; Layout.columnSpan: parent.columns; text: (Task.snapshot.errors||[]).join("\n"); color: Task.style.amber; wrapMode: Text.WordWrap; visible: text.length>0 }
            }
        }
        ColumnLayout {
            id: processesPage; spacing: 10
            RowLayout {
                Layout.fillWidth: true
                TextField { id: search; objectName: "processSearch"; Layout.fillWidth: true; placeholderText: "Search name, application or PID"; selectByMouse: true; onTextChanged: searchDelay.restart() }
                ComboBox { id: state; model: ["All states","R","S","D","T","Z","I"]; onActivated: searchDelay.restart(); Accessible.name: "Filter process state" }
            }
            RowLayout {
                Layout.fillWidth: true
                CheckBox { id: own; text: "My processes"; onToggled: searchDelay.restart() }
                CheckBox { id: grouped; text: "Group apps"; onToggled: searchDelay.restart() }
                Item { Layout.fillWidth: true }
                Text { textFormat: Text.PlainText; text: Task.processCount+" visible"; color: Task.style.muted; font.pixelSize: 12 }
            }
            Timer { id: searchDelay; interval: 160; onTriggered: Task.filter(search.text,state.currentIndex?state.currentText:"",own.checked,grouped.checked) }
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 14
                ColumnLayout {
                    visible: !win.inspector || win.wide
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 4
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; spacing: 4
                        Repeater {
                            model: [{label:"Process",key:"name"},{label:"PID",key:"pid"},{label:"CPU",key:"cpu"},{label:"Memory",key:"rss"},{label:"State",key:"state"}].concat(win.hasGpu?[{label:"GPU",key:"gpuMemory"}]:[])
                            TMButton { required property var modelData; Layout.fillWidth: modelData.key==="name"; Layout.preferredWidth: ({name:160,pid:54,cpu:64,rss:80,state:46,gpuMemory:75})[modelData.key]; Layout.minimumWidth: modelData.key==="name"?60:Layout.preferredWidth; Layout.maximumWidth: modelData.key==="name"?Infinity:Layout.preferredWidth; implicitWidth: 0; text: modelData.label; onClicked: Task.sort(modelData.key); Accessible.name: "Sort by "+modelData.label }
                        }
                    }
                    ListView {
                        id: table; objectName: "processTable"; Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; reuseItems: true; model: Task.processes; spacing: 1; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        section.property: grouped.checked ? "appGroup" : ""
                        section.delegate: Rectangle { required property string section; width: table.width; height: 32; color: Task.style.elevated; Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; x: 10; text: parent.section; color: Task.style.teal; elide: Text.ElideRight; width: parent.width-20 } }
                        delegate: ItemDelegate {
                            id: row
                            required property string identity
                            required property string processName
                            required property int pid
                            required property var cpu
                            required property double rss
                            required property var gpuMemory
                            required property string processState
                            required property string owner
                            width: table.width; height: 48; highlighted: win.selected.identity===identity
                            onClicked: Task.select(identity)
                            background: Rectangle { color: row.highlighted ? Task.style.elevated : row.hovered ? Task.style.surface : "transparent"; radius: 5 }
                            contentItem: RowLayout {
                                spacing: 4
                                ColumnLayout { Layout.fillWidth: true; Layout.preferredWidth: 160; spacing: 1
                                    Text { Layout.fillWidth: true; text: row.processName; textFormat: Text.PlainText; elide: Text.ElideRight; color: Task.style.text }
                                    Text { Layout.fillWidth: true; text: row.owner; textFormat: Text.PlainText; elide: Text.ElideRight; color: Task.style.muted; font.pixelSize: 10 }
                                }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: 54; text: row.pid; color: Task.style.muted; font.family: Task.style.mono; font.pixelSize: 11 }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: 64; text: win.known(row.cpu)?Number(row.cpu).toFixed(1)+"%":"—"; color: Task.style.teal; font.family: Task.style.mono; font.pixelSize: 11 }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: 80; text: win.bytes(row.rss); color: Task.style.text; font.family: Task.style.mono; font.pixelSize: 11 }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: 46; text: row.processState; color: Task.style.muted; font.pixelSize: 11 }
                                Text { textFormat: Text.PlainText; visible: win.hasGpu; Layout.preferredWidth: 75; text: win.bytes(row.gpuMemory); color: Task.style.muted; font.pixelSize: 11 }
                            }
                        }
                        Text { textFormat: Text.PlainText; anchors.centerIn: parent; visible: table.count===0; text: Task.connected ? "No matching processes" : "Waiting for collector"; color: Task.style.muted }
                    }
                }
                Rectangle {
                    id: inspectorPanel; objectName: "processInspector"; visible: win.inspector
                    Layout.fillWidth: !win.wide; Layout.preferredWidth: win.wide ? 340 : -1; Layout.fillHeight: true
                    color: Task.style.surface; radius: Task.style.radius; border.color: Task.style.border
                    opacity: visible ? 1 : 0
                    Behavior on opacity { enabled: !Task.style.reducedMotion; NumberAnimation { duration: 150 } }
                    ScrollView {
                        id: inspectorScroll; anchors.fill: parent; anchors.margins: 14; contentWidth: availableWidth; clip: true
                        ColumnLayout {
                            width: inspectorScroll.availableWidth; spacing: 10
                            RowLayout { Layout.fillWidth: true
                                Text { textFormat: Text.PlainText; text: "▣"; color: Task.style.teal; font.pixelSize: 24 }
                                Text { Layout.fillWidth: true; text: win.selected.name||"Process"; textFormat: Text.PlainText; color: Task.style.text; font.pixelSize: 22; elide: Text.ElideRight }
                                TMButton { text: "×"; implicitWidth: 36; onClicked: Task.select(""); Accessible.name: "Close process inspector" }
                            }
                            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: win.selected.exited ? "Process exited" : "PID "+win.selected.pid+" · "+win.selected.user+" · "+win.selected.state; color: Task.style.muted; wrapMode: Text.WrapAnywhere }
                            Text { Layout.fillWidth: true; text: win.selected.exe||"Executable unavailable"; textFormat: Text.PlainText; color: Task.style.text; wrapMode: Text.WrapAnywhere; font.pixelSize: 12 }
                            Text { Layout.fillWidth: true; text: win.selected.command||"Command line inaccessible"; textFormat: Text.PlainText; color: Task.style.muted; wrapMode: Text.WrapAnywhere; font.pixelSize: 11 }
                            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: "CPU "+win.percent(win.selected.cpu)+" · RAM "+win.bytes(win.selected.rss)+"\nParent PID "+win.selected.ppid+" · Threads "+win.selected.threads+"\nRuntime "+win.optional(win.selected.runtime," s")+" · Nice "+win.selected.nice; color: Task.style.text; wrapMode: Text.WordWrap }
                            HistoryGraph { Layout.fillWidth: true; Layout.preferredHeight: 75; samples: win.history("processCpu"); maximum: 0; color: Task.style.teal }
                            Text { textFormat: Text.PlainText; text: "CPU · scale follows selected process"; color: Task.style.muted; font.pixelSize: 11 }
                            HistoryGraph { Layout.fillWidth: true; Layout.preferredHeight: 55; samples: win.history("processMemory"); maximum: 0; color: Task.style.green }
                            Text { textFormat: Text.PlainText; text: "Resident memory history"; color: Task.style.muted; font.pixelSize: 11 }
                            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: win.selected.protected||""; color: Task.style.amber; wrapMode: Text.WordWrap; visible: text.length>0 }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                TMButton { text: "End Process"; enabled: win.canAct; onClicked: Task.action(win.selected.identity,"term") }
                                TMButton { text: "Force Stop"; enabled: win.canAct; danger: true; onClicked: {win.confirmationIdentity=win.selected.identity;win.confirmationName=win.selected.name+" (PID "+win.selected.pid+")";confirm.open();} }
                                TMButton { text: "Suspend"; enabled: win.canAct; onClicked: Task.action(win.selected.identity,"stop") }
                                TMButton { text: "Resume"; enabled: win.canAct; onClicked: Task.action(win.selected.identity,"continue") }
                            }
                            RowLayout { Layout.fillWidth: true
                                SpinBox { id: priority; from: -20; to: 19; value: Number(win.selected.nice||0); editable: true; Accessible.name: "Nice value" }
                                TMButton { Layout.fillWidth: true; text: "Set priority"; enabled: win.canAct; onClicked: Task.action(win.selected.identity,"nice",priority.value) }
                            }
                            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: "Higher nice values lower priority. Raising priority may be denied by Linux."; color: Task.style.muted; font.pixelSize: 11; wrapMode: Text.WordWrap }
                            Text { Layout.fillWidth: true; text: "Cgroup\n"+(win.selected.cgroup||"Unavailable"); textFormat: Text.PlainText; color: Task.style.muted; font.pixelSize: 11; wrapMode: Text.WrapAnywhere }
                        }
                    }
                }
            }
        }
        ScrollView {
            id: performance; clip: true; contentWidth: availableWidth
            ColumnLayout {
                width: performance.availableWidth; spacing: 14
                ResourceCard { Layout.fillWidth: true; Layout.preferredHeight: 240; title: "Total CPU"; value: win.percent(win.cpu.percent); samples: win.history("cpu"); detail: (win.cpu.logical||0)+" logical CPUs · Load averages "+(win.cpu.load||[]).map(n=>Number(n).toFixed(2)).join(" / ") }
                GridLayout {
                    Layout.fillWidth: true; columns: Math.max(2,Math.floor(width/130)); columnSpacing: 8; rowSpacing: 8
                    Repeater { model: win.cpu.cores||[]
                        Rectangle { required property var modelData; Layout.fillWidth: true; implicitHeight: 52; radius: 6; color: Task.style.surface
                            Text { textFormat: Text.PlainText; anchors.fill: parent; anchors.margins: 8; text: modelData.name+"\n"+win.percent(modelData.percent); color: Task.style.text; font.pixelSize: 12 }
                            Rectangle { anchors.bottom: parent.bottom; height: 2; width: parent.width*Math.max(0,Number(parent.modelData.percent||0))/100; color: Task.style.teal; Behavior on width { enabled: !Task.style.reducedMotion; NumberAnimation { duration: 180 } } }
                        }
                    }
                }
                ResourceCard { Layout.fillWidth: true; title: "RAM"; value: win.bytes(win.memory.used)+" / "+win.bytes(win.memory.total); samples: win.history("memory"); detail: "Available "+win.bytes(win.memory.available)+" · Cache "+win.bytes(win.memory.cache)+" · Buffers "+win.bytes(win.memory.buffers) }
                ResourceCard { Layout.fillWidth: true; title: "Swap"; value: win.bytes(win.memory.swapUsed)+" / "+win.bytes(win.memory.swapTotal); samples: win.history("swap"); detail: "No swap is shown as unavailable utilization" }
                Repeater { model: win.gpus
                    ColumnLayout { required property var modelData; required property int index; Layout.fillWidth: true
                        ResourceCard { Layout.fillWidth: true; title: modelData.name; value: win.percent(modelData.percent); samples: win.history("gpu"+index); detail: win.optional(modelData.clock," MHz")+" · "+win.optional(modelData.temperature,"°C")+" · "+win.optional(modelData.power," W") }
                        ResourceCard { Layout.fillWidth: true; title: "VRAM"; value: win.bytes(modelData.used)+" / "+win.bytes(modelData.total); samples: win.history("vram"+index); ceiling: Number(modelData.total||0) }
                    }
                }
                ResourceCard { Layout.fillWidth: true; title: "Disk read"; value: win.rate(Task.snapshot.diskRead); samples: win.history("diskRead"); ceiling: 0 }
                ResourceCard { Layout.fillWidth: true; title: "Disk write"; value: win.rate(Task.snapshot.diskWrite); samples: win.history("diskWrite"); ceiling: 0 }
                Repeater { model: Task.snapshot.disks||[]; Text { textFormat: Text.PlainText; required property var modelData; Layout.fillWidth: true; text: modelData.name+" · Read "+win.rate(modelData.read)+" · Write "+win.rate(modelData.write); color: Task.style.text; wrapMode: Text.WordWrap } }
                Repeater { model: Task.snapshot.mounts||[]; Text { textFormat: Text.PlainText; required property var modelData; Layout.fillWidth: true; text: modelData.path+" ("+modelData.filesystem+") · Used "+win.bytes(modelData.used)+" / "+win.bytes(modelData.total)+" · Available "+win.bytes(modelData.available); color: Task.style.muted; wrapMode: Text.WrapAnywhere } }
                ResourceCard { Layout.fillWidth: true; title: "Download"; value: win.rate(Task.snapshot.download); samples: win.history("download"); ceiling: 0 }
                ResourceCard { Layout.fillWidth: true; title: "Upload"; value: win.rate(Task.snapshot.upload); samples: win.history("upload"); ceiling: 0 }
                Repeater { model: Task.snapshot.networks||[]; Text { textFormat: Text.PlainText; required property var modelData; Layout.fillWidth: true; text: modelData.name+" · "+modelData.state+" · ↓ "+win.rate(modelData.download)+" ↑ "+win.rate(modelData.upload)+"\nTransferred: "+win.bytes(modelData.received)+" received / "+win.bytes(modelData.sent)+" sent"; color: Task.style.text; wrapMode: Text.WordWrap } }
            }
        }
        ColumnLayout {
            RowLayout { Layout.fillWidth: true
                Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: Task.serviceStatus; color: Task.style.muted; wrapMode: Text.WordWrap }
                TMButton { text: "Refresh"; onClicked: Task.refreshServices() }
            }
            Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: "User services only. Management remains in CEDAR Station; no privilege elevation."; color: Task.style.muted; wrapMode: Text.WordWrap }
            ListView { id: serviceList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; reuseItems: true; model: Task.services; spacing: 8; ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle { required property var modelData; width: serviceList.width; height: serviceText.implicitHeight+24; radius: 8; color: Task.style.surface
                    Text { id: serviceText; x: 12; y: 12; width: parent.width-24; text: parent.modelData.name+" · "+parent.modelData.state+"\n"+parent.modelData.description; textFormat: Text.PlainText; color: Task.style.text; wrapMode: Text.WordWrap }
                }
            }
        }
    }
    Dialog {
        id: confirm; title: "Force Stop process?"; modal: true; anchors.centerIn: parent; width: Math.min(win.width-40,450)
        standardButtons: Dialog.Cancel | Dialog.Yes
        contentItem: Text { text: win.confirmationName+"\n\nUnsaved work may be lost. Send SIGKILL to this exact process?"; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Task.style.text }
        onAccepted: Task.action(win.confirmationIdentity,"kill",0,true)
    }
    Timer { interval: 28000; running: Task.testing; onTriggered: Task.finishTest(false,"UI test deadline; samples="+Task.samples) }
    Timer {
        id: selfTest; interval: 350; repeat: true; running: Task.testing
        property int step: 0
        property int waits: 0
        property bool restartChecked: false
        property int resumeAt: 0
        onTriggered: {
            if(Task.samples<2){if(++waits>50)Task.finishTest(false,"Live collector did not update");return;}
            if(!restartChecked){restartChecked=true;resumeAt=Task.samples+2;if(Task.restartForTest())return;}
            if(Task.samples<resumeAt)return;
            if(step===0){if(!Task.exerciseModel()){Task.finishTest(false,"Process batch/filter/sort/identity");return;}win.page=1;}
            else if(step===1){if(!Task.firstIdentity())return;Task.select(Task.firstIdentity());}
            else if(step===2){if(!inspectorPanel.visible){Task.finishTest(false,"Inspector did not open");return;}Task.select("");win.page=2;}
            else if(step===3){win.width=520;win.height=440;win.page=3;}
            else if(step===4){win.page=1;search.text="no-process-matches-this";}
            else if(step===5){if(Task.processCount!==0){Task.finishTest(false,"Search debounce");return;}search.text="";}
            else if(step===6){win.width=1180;win.height=820;win.page=0;}
            else if(step===7){Task.finishTest(Task.capture(win),"Standalone views, live telemetry, 6000 process rows, search, sort, inspector and screenshot");stop();}
            step++;
        }
    }
}
