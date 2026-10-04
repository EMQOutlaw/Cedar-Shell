import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "../components"
ColumnLayout {
    id: root
    property bool active: false
    property var draft: []
    property int selected: 0
    property bool dirty: false
    property var base:[]
    property bool externalChange:false
    property int seconds: 0
    readonly property var outputs: Quickshell.screens.filter(s => s.name).map(s => s.name)
    readonly property var mainChoices: [{label:"Follow focused display", name:""}].concat(outputs.map(name=>({label:name,name:name}))).concat(Config.saved.mainDisplay && !outputs.includes(Config.saved.mainDisplay) ? [{label:Config.saved.mainDisplay + " (disconnected)",name:Config.saved.mainDisplay}] : [])
    readonly property var current: draft[selected] || null
    function load() {
        base=JSON.parse(JSON.stringify(DesktopSettings.data.monitors));externalChange=false;
        draft = DesktopSettings.data.monitors.filter(m => !m.disabled).map(m => ({name:m.name, description:m.description,
            mode:m.width+"x"+m.height+"@"+Number(m.refreshRate).toFixed(2), modes:m.availableModes || [],
            x:m.x,y:m.y,scale:m.scale,transform:m.transform || 0,width:m.width,height:m.height,vrrAvailable:"vrr" in m,vrrActive:m.vrr===true,vrrPolicy:DesktopSettings.data.owned.monitors?.find(o=>o.name===m.name)?.vrrPolicy ?? -2}));
        selected = Math.min(selected, Math.max(0,draft.length-1)); dirty = false;
    }
    function logicalWidth(m) { return (m.transform % 2 ? m.height : m.width) / m.scale; }
    function logicalHeight(m) { return (m.transform % 2 ? m.width : m.height) / m.scale; }
    function change(key,value) {
        if (!current) return;
        if (["x","y","scale"].includes(key) && (!isFinite(value) || (key === "scale" && (value < 0.5 || value > 4)))) {
            DesktopSettings.error = "Enter a valid number; display scale must be between 0.5 and 4."; return;
        } const items = draft.slice(); items[selected] = Object.assign({}, current, {[key]:value}); draft = items; dirty = true; }
    onActiveChanged: if (active) DesktopSettings.refresh()
    Connections { target: DesktopSettings; function onRefreshed() { if(!root.dirty || DesktopSettings.pending)root.load();else root.externalChange=true; }
        function onApplied(action) {if(action==="displays")root.dirty=false;} }
    Timer { interval: 250; repeat: true; running: DesktopSettings.pending !== null; triggeredOnStart: true; onTriggered: root.seconds = Math.max(0, Math.ceil(DesktopSettings.pending.deadline-Date.now()/1000)) }
    Component.onCompleted:load()
    spacing: 14
    GlowText { visible:root.externalChange; text:"The active display configuration refreshed. Your draft is retained; reload it if the displays changed."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    StationButton { visible:root.externalChange; text:"Discard draft and reload"; onClicked:root.load() }
    GlowText { text: "Drag a display to arrange it, then test the layout. Confirm within 20 seconds to keep the change."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted }
    GlowText { objectName:"mainDisplay"; text: "Main display"; color: Theme.teal; Layout.topMargin: 6 }
    GlowText { text: "CEDAR panels, notifications, and volume controls open on this screen. If it disconnects, CEDAR follows the focused display."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    RowLayout {
        Layout.fillWidth: true
        StationCombo {
            Layout.fillWidth: true; model: root.mainChoices; textRole: "label"
            currentIndex: root.mainChoices.findIndex(m=>m.name===Config.saved.mainDisplay)
            onActivated: Config.set("mainDisplay", root.mainChoices[currentIndex].name)
        }
        StationButton {
            text: DesktopSettings.busy && DesktopSettings.operation === "primary" ? "Applying…" : "Apply system default"
            enabled: root.outputs.includes(Config.saved.mainDisplay) && !DesktopSettings.busy && DesktopSettings.pending === null
            onClicked: DesktopSettings.apply({action:"primary",output:Config.saved.mainDisplay})
        }
    }
    GlowText {
        visible: DesktopSettings.operation === "primary" && (DesktopSettings.busy || DesktopSettings.error !== "" || DesktopSettings.message !== "")
        text: DesktopSettings.busy ? "Applying the main display…" : DesktopSettings.error || DesktopSettings.message
        color: DesktopSettings.error ? Theme.amber : Theme.green
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11
    }
    GlowText {
        text: "System default: " + (DesktopSettings.data.owned.mainDisplay || "not set by CEDAR") + ". Apply also sets the startup cursor and the main screen for X11 games. Native apps follow the focused screen."
        color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11
    }
    Rectangle {
        id: map
        objectName:"arrangement"
        enabled: !DesktopSettings.busy && DesktopSettings.pending === null
        Layout.fillWidth: true; implicitHeight: 210
        radius: 10; color: Theme.surface; border.color: Qt.alpha(Theme.teal,.18)
        readonly property real minX: Math.min(0, ...root.draft.map(m => m.x))
        readonly property real minY: Math.min(0, ...root.draft.map(m => m.y))
        readonly property real factor: Math.min((width-48)/Math.max(1920,...root.draft.map(m=>m.x-map.minX+root.logicalWidth(m))), (height-48)/Math.max(1080,...root.draft.map(m=>m.y-map.minY+root.logicalHeight(m))))
        Repeater {
            model: root.draft
            Rectangle {
                id: monitor
                required property var modelData
                required property int index
                x: 24+(modelData.x-map.minX)*map.factor; y: 24+(modelData.y-map.minY)*map.factor
                width: Math.max(60,root.logicalWidth(modelData)*map.factor); height: Math.max(40,root.logicalHeight(modelData)*map.factor)
                color: root.selected === index ? Theme.elevated : Theme.background
                border.color: root.selected === index ? Theme.green : Theme.border; radius: 6
                GlowText { anchors.centerIn: parent; text: monitor.modelData.name + (monitor.modelData.name === Config.saved.mainDisplay ? " · MAIN" : ""); font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                    property real startX: 0; property real startY: 0
                    property real startItemX: 0; property real startItemY: 0
                    drag.target: monitor
                    drag.threshold: 3
                    onPressed: mouse => { root.selected = monitor.index; startX = mouse.x; startY = mouse.y; startItemX=monitor.x; startItemY=monitor.y; }
                    onReleased: mouse => {
                        const dx = (monitor.x-startItemX)/map.factor, dy = (monitor.y-startItemY)/map.factor;
                        if (Math.abs(dx)+Math.abs(dy)<10) return;
                        const nextX = Math.round((monitor.modelData.x+dx)/10)*10;
                        const nextY = Math.round((monitor.modelData.y+dy)/10)*10;
                        root.change("x",nextX); root.change("y",nextY);
                    }
                }
            }
        }
    }
    StationCombo { Layout.fillWidth: true; model: root.draft; textRole: "name"; currentIndex: root.selected; onActivated: root.selected = currentIndex }
    GlowText { text: root.current?.description || "No display information available."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 11 }
    GridLayout {
        enabled: !DesktopSettings.busy && DesktopSettings.pending === null
        objectName:"displayMode"; columns:root.width<500 ? 1:2; Layout.fillWidth: true; visible: root.current !== null; columnSpacing: 20; rowSpacing: 10
        GlowText { text: "Resolution / refresh rate" }
        StationCombo {
            Layout.fillWidth: true
            model: root.current ? [...new Set([root.current.mode].concat(root.current.modes.map(m=>m.replace("Hz",""))))] : []
            currentIndex: model.indexOf(root.current?.mode)
            onActivated: { root.change("mode", currentText); const size = currentText.split("@")[0].split("x"); root.change("width", Number(size[0])); root.change("height",Number(size[1])); }
        }
        GlowText { text: "Scale" }
        StationField { Layout.fillWidth: true; text: String(root.current?.scale ?? 1); onCommit: value => root.change("scale", Number(value)) }
        GlowText { text: "Position X / Y" }
        RowLayout {
            StationField { Layout.fillWidth: true; text: String(root.current?.x ?? 0); onCommit: value => root.change("x", Number(value)) }
            StationField { Layout.fillWidth: true; text: String(root.current?.y ?? 0); onCommit: value => root.change("y", Number(value)) }
        }
        GlowText { text: "Rotation" }
        StationCombo { Layout.fillWidth: true; model: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]; currentIndex: root.current?.transform ?? 0; onActivated: root.change("transform", currentIndex) }
    }
    SettingRow {
        objectName:"vrr"; Layout.fillWidth:true; title:"Variable Refresh Rate"; enabled:root.current?.vrrAvailable===true && !DesktopSettings.busy && DesktopSettings.pending===null
        description:!root.current?.vrrAvailable ? "VRR status is not exposed by this display.":"Request adaptive sync on compatible hardware. Currently "+(root.current.vrrActive ? "active":"inactive")+". Changes are included in the display trial."
        StationCombo {
            Layout.fillWidth:true
            model:[{value:-2,label:"Keep existing policy"},{value:-1,label:"Follow global policy"},{value:0,label:"Off"},{value:1,label:"On"},{value:2,label:"Fullscreen only"},{value:3,label:"Fullscreen games / video"}]; textRole:"label"
            currentIndex:model.findIndex(m=>m.value===(root.current?.vrrPolicy ?? -2))
            onActivated:root.change("vrrPolicy",model[currentIndex].value)
        }
    }
    GlowText { text:"HDR configuration is not exposed here because support has not been verified. All active displays remain enabled during arrangement trials."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted; font.pixelSize:Theme.small }
    RowLayout {
        visible: DesktopSettings.pending === null
        StationButton { text: "Test display layout"; enabled: root.dirty && !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"displays",monitors:root.draft,expected:root.base}) }
        StationButton { text: "Refresh"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.refresh() }
    }
    RowLayout {
        visible: DesktopSettings.pending !== null
        GlowText { text: "Reverting in " + root.seconds + "s"; color: Theme.amber }
        StationButton { text: "Keep layout"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"keep",token:DesktopSettings.pending.token}) }
        StationButton { text: "Revert now"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"revert",token:DesktopSettings.pending.token}) }
    }
}
