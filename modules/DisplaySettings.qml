import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "../components"
ColumnLayout {
    id: root
    property bool active: false
    property string highlightKey: ""
    property var draft: []
    property int selected: 0
    property bool dirty: false
    property var base:[]
    property bool externalChange:false
    property int seconds: 0
    property string confirmDelete: ""
    property string notice: ""
    readonly property bool locked: DesktopSettings.busy || DesktopSettings.pending !== null
    readonly property var outputs: Quickshell.screens.filter(s => s.name).map(s => s.name)
    readonly property var mainChoices: [{label:"Follow focused display", name:""}].concat(outputs.map(name=>({label:name,name:name}))).concat(Config.saved.mainDisplay && !outputs.includes(Config.saved.mainDisplay) ? [{label:Config.saved.mainDisplay + " (disconnected)",name:Config.saved.mainDisplay}] : [])
    readonly property var current: draft[selected] || null
    readonly property var profiles: DesktopSettings.data.owned?.displayProfiles || []
    readonly property var connected: DesktopSettings.data.monitors.filter(m => !m.disabled).map(m => m.name).sort()
    function load() {
        base=JSON.parse(JSON.stringify(DesktopSettings.data.monitors));externalChange=false;
        draft = DesktopSettings.data.monitors.filter(m => !m.disabled).map(m => ({name:m.name, description:m.description,
            mode:m.width+"x"+m.height+"@"+Number(m.refreshRate).toFixed(2), modes:m.availableModes || [],
            x:m.x,y:m.y,scale:m.scale,transform:m.transform || 0,width:m.width,height:m.height,vrrAvailable:"vrr" in m,vrrActive:m.vrr===true,vrrPolicy:DesktopSettings.data.owned.monitors?.find(o=>o.name===m.name)?.vrrPolicy ?? -2,
            mirror:m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : ""}));
        selected = Math.min(selected, Math.max(0,draft.length-1)); dirty = false;
    }
    function logicalWidth(m) { return (m.transform % 2 ? m.height : m.width) / m.scale; }
    function logicalHeight(m) { return (m.transform % 2 ? m.width : m.height) / m.scale; }
    function change(key,value) {
        if (!current) return;
        if (["x","y","scale"].includes(key) && (!isFinite(value) || (key === "scale" && (value < 0.5 || value > 4)))) {
            DesktopSettings.error = "Enter a valid number; display scale must be between 0.5 and 4."; return;
        } const items = draft.slice(); items[selected] = Object.assign({}, current, {[key]:value}); draft = items; dirty = true; }
    // Modes as {mode,width,height,rate}; the current mode is always offered.
    function modesOf(m) {
        if (!m) return [];
        const seen = {}, list = [];
        [m.mode].concat(m.modes.map(x => x.replace("Hz",""))).forEach(mode => {
            const match = /^(\d+)x(\d+)@([\d.]+)$/.exec(mode);
            if (!match || seen[mode]) return; seen[mode] = true;
            list.push({mode:mode, width:Number(match[1]), height:Number(match[2]), rate:Number(match[3])});
        });
        return list;
    }
    function resolutions(m) {
        const sizes = {};
        modesOf(m).forEach(x => sizes[x.width+"x"+x.height] = x);
        return Object.values(sizes).sort((a,b) => b.width*b.height - a.width*a.height).map(x => ({value:x.width+"x"+x.height, label:x.width+" × "+x.height}));
    }
    function rates(m) {
        if (!m) return [];
        return modesOf(m).filter(x => x.width === m.width && x.height === m.height).sort((a,b) => b.rate-a.rate)
            .map(x => ({value:x.mode, label:(Math.abs(x.rate-Math.round(x.rate)) < .1 ? Math.round(x.rate) : x.rate.toFixed(2))+" Hz"}));
    }
    function chooseMode(mode) {
        const x = modesOf(current).find(r => r.mode === mode); if (!x) return;
        change("mode", mode); change("width", x.width); change("height", x.height);
    }
    function chooseResolution(size) {
        const options = modesOf(current).filter(x => x.width+"x"+x.height === size).sort((a,b) => b.rate-a.rate);
        if (!options.length) return;
        // Keep the current refresh rate when the new size offers it.
        chooseMode((options.find(x => Math.round(x.rate) === Math.round(current.mode.split("@")[1])) || options[0]).mode);
    }
    // Drop a display flush against the nearest edge of another display.
    function snap(index, nextX, nextY) {
        const m = draft[index], w = logicalWidth(m), h = logicalHeight(m);
        let bestX = Math.round(nextX/10)*10, bestY = Math.round(nextY/10)*10, dx = Infinity, dy = Infinity;
        const reach = Math.max(80, Math.min(w, h) * .12);
        draft.forEach((o, i) => {
            if (i === index || o.mirror) return;
            const ow = logicalWidth(o), oh = logicalHeight(o);
            [o.x+ow, o.x-w, o.x, o.x+ow-w].forEach(x => { const d = Math.abs(x-nextX); if (d < reach && d < dx) { dx = d; bestX = Math.round(x); } });
            [o.y+oh, o.y-h, o.y, o.y+oh-h].forEach(y => { const d = Math.abs(y-nextY); if (d < reach && d < dy) { dy = d; bestY = Math.round(y); } });
        });
        return {x:bestX, y:bestY};
    }
    function profileReady(p) { return JSON.stringify(p.monitors.map(m => m.name).sort()) === JSON.stringify(connected); }
    function profileSummary(p) { return p.monitors.map(m => m.name+" "+m.mode.split("@")[0].replace("x"," × ")+(m.mirror ? " mirroring "+m.mirror : "")).join("  ·  "); }
    function loadProfile(p) {
        draft = draft.map(d => {
            const s = p.monitors.find(m => m.name === d.name); if (!s) return d;
            const size = s.mode.split("@")[0].split("x");
            return Object.assign({}, d, {mode:s.mode, width:Number(size[0]), height:Number(size[1]), x:s.x, y:s.y, scale:s.scale, transform:s.transform, mirror:s.mirror || "", vrrPolicy:s.vrrPolicy ?? -2});
        });
        if (p.mainDisplay) Config.set("mainDisplay", p.mainDisplay);
        dirty = true; notice = "Loaded “"+p.name+"”. Test the layout to apply it.";
    }
    onActiveChanged: if (active) DesktopSettings.refresh()
    Connections { target: DesktopSettings; function onRefreshed() { if(!root.dirty || DesktopSettings.pending)root.load();else root.externalChange=true; }
        function onApplied(action) {if(action==="displays"){root.dirty=false;root.notice="";}} }
    Timer { interval: 250; repeat: true; running: DesktopSettings.pending !== null; triggeredOnStart: true; onTriggered: root.seconds = Math.max(0, Math.ceil(DesktopSettings.pending.deadline-Date.now()/1000)) }
    Component.onCompleted:load()
    spacing: 16

    // Detect
    RowLayout {
        objectName: "detect"
        Layout.fillWidth: true; spacing: 12
        Rectangle { width: 8; height: 8; radius: 4; color: root.draft.length ? Theme.green : Theme.amber }
        GlowText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: DesktopSettings.busy && DesktopSettings.operation === "snapshot" ? "Detecting displays…" : root.draft.length === 1 ? "1 display detected" : root.draft.length + " displays detected"
            color: Theme.text; font.pixelSize: Theme.small
        }
        StationButton { text: "Detect displays"; enabled: !DesktopSettings.busy; onClicked: { DesktopSettings.operation = "snapshot"; DesktopSettings.refresh(); } }
    }

    // Live trial
    Rectangle {
        visible: DesktopSettings.pending !== null
        Layout.fillWidth: true; implicitHeight: trial.implicitHeight + 28
        radius: 10; color: Qt.alpha(Theme.amber, .07); border.color: Qt.alpha(Theme.amber, .45)
        ColumnLayout {
            id: trial
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 10
            GlowText { text: "Testing the new layout"; font.family: Theme.labelFont; font.pixelSize: 20; color: Theme.amber }
            GlowText { text: "Can you see this clearly? Keep it, or CEDAR restores the previous layout in " + root.seconds + " seconds — even if this window stops responding."; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 3; radius: 2; color: Qt.alpha(Theme.amber, .15)
                Rectangle { width: parent.width * Math.min(1, root.seconds/20); height: parent.height; radius: 2; color: Theme.amber; Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 250 } } }
            }
            Flow {
                Layout.fillWidth: true; spacing: 8
                StationButton { text: "Keep layout"; accent: Theme.green; checked: true; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"keep",token:DesktopSettings.pending.token}) }
                StationButton { text: "Revert now"; enabled: !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"revert",token:DesktopSettings.pending.token}) }
            }
        }
    }

    SettingsSection {
        visible: root.externalChange; accent: Theme.amber; padding: 14
        GlowText { text:"Your displays changed while you were editing. Your draft is kept; reload if a monitor was connected or removed."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize: Theme.small }
        StationButton { text:"Discard draft and reload"; onClicked:root.load() }
    }

    // Arrangement
    Rectangle {
        id: map
        objectName:"arrangement"
        enabled: !root.locked
        Layout.fillWidth: true; implicitHeight: root.width < 560 ? 200 : 250
        radius: 10; color: Theme.surface; border.color: Qt.alpha(Theme.teal,.18); clip: true
        readonly property var placed: root.draft.filter(m => !m.mirror)
        readonly property real minX: Math.min(0, ...placed.map(m => m.x))
        readonly property real minY: Math.min(0, ...placed.map(m => m.y))
        readonly property real spanX: Math.max(1920, ...placed.map(m=>m.x-minX+root.logicalWidth(m)))
        readonly property real spanY: Math.max(1080, ...placed.map(m=>m.y-minY+root.logicalHeight(m)))
        readonly property real factor: Math.min((width-64)/spanX, (height-64)/spanY)
        readonly property real offsetX: (width - spanX*factor)/2
        readonly property real offsetY: (height - spanY*factor)/2
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d"); ctx.reset();
                ctx.strokeStyle = Theme.grid; ctx.lineWidth = 1;
                for (let x = 16; x < width; x += 24) { ctx.beginPath(); ctx.moveTo(x+.5, 0); ctx.lineTo(x+.5, height); ctx.stroke(); }
                for (let y = 16; y < height; y += 24) { ctx.beginPath(); ctx.moveTo(0, y+.5); ctx.lineTo(width, y+.5); ctx.stroke(); }
            }
        }
        GlowText { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10; text: "Drag to arrange · edges snap together"; color: Qt.alpha(Theme.muted, .8); font.pixelSize: 10 }
        Repeater {
            model: root.draft
            Rectangle {
                id: monitor
                required property var modelData
                required property int index
                readonly property var source: modelData.mirror ? root.draft.find(m => m.name === modelData.mirror) : null
                readonly property var anchorMonitor: source || modelData
                readonly property bool chosen: root.selected === index
                x: map.offsetX+(anchorMonitor.x-map.minX)*map.factor + (source ? 10 : 0)
                y: map.offsetY+(anchorMonitor.y-map.minY)*map.factor + (source ? 10 : 0)
                z: chosen ? 3 : source ? 2 : 1
                width: Math.max(72,root.logicalWidth(anchorMonitor)*map.factor); height: Math.max(48,root.logicalHeight(anchorMonitor)*map.factor)
                radius: 6; opacity: source ? .82 : 1
                color: chosen ? Theme.elevated : Theme.background
                border.width: chosen ? 2 : 1
                border.color: chosen ? Theme.green : source ? Qt.alpha(Theme.teal,.5) : Theme.border
                Behavior on x { enabled: !mover.drag.active && !Theme.reducedMotion; NumberAnimation { duration: Theme.transition; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !mover.drag.active && !Theme.reducedMotion; NumberAnimation { duration: Theme.transition; easing.type: Easing.OutCubic } }
                // A thin top edge reads as the bar side of the screen.
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4; height: 3; radius: 2; color: Qt.alpha(monitor.chosen ? Theme.green : Theme.teal, .35) }
                Column {
                    anchors.centerIn: parent; width: parent.width - 12; spacing: 2
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: monitor.modelData.name; font.family: Theme.labelFont; font.pixelSize: monitor.height > 70 ? 18 : 14; color: monitor.chosen ? Theme.green : Theme.text; elide: Text.ElideRight }
                    Text { visible: monitor.height > 64; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: monitor.source ? "mirrors " + monitor.source.name : monitor.modelData.width + " × " + monitor.modelData.height + "  ·  " + Math.round(Number(monitor.modelData.mode.split("@")[1])) + " Hz"; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; elide: Text.ElideRight }
                    Text { visible: monitor.height > 84 && (monitor.modelData.name === Config.saved.mainDisplay || monitor.modelData.scale !== 1); width: parent.width; horizontalAlignment: Text.AlignHCenter; text: [monitor.modelData.name === Config.saved.mainDisplay ? "MAIN" : "", monitor.modelData.scale !== 1 ? Math.round(monitor.modelData.scale*100)+"%" : ""].filter(Boolean).join("  ·  "); font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1; color: Theme.teal }
                }
                MouseArea {
                    id: mover
                    anchors.fill: parent; cursorShape: monitor.source ? Qt.PointingHandCursor : Qt.SizeAllCursor
                    property real startItemX: 0; property real startItemY: 0
                    drag.target: monitor.source ? null : monitor
                    drag.threshold: 3
                    onPressed: { root.selected = monitor.index; startItemX=monitor.x; startItemY=monitor.y; }
                    onReleased: {
                        if (monitor.source) return;
                        const dx = (monitor.x-startItemX)/map.factor, dy = (monitor.y-startItemY)/map.factor;
                        if (Math.abs(dx)+Math.abs(dy)<10) { monitor.x = Qt.binding(() => map.offsetX+(monitor.anchorMonitor.x-map.minX)*map.factor); monitor.y = Qt.binding(() => map.offsetY+(monitor.anchorMonitor.y-map.minY)*map.factor); return; }
                        const next = root.snap(monitor.index, monitor.modelData.x+dx, monitor.modelData.y+dy);
                        root.change("x",next.x); root.change("y",next.y);
                        monitor.x = Qt.binding(() => map.offsetX+(monitor.anchorMonitor.x-map.minX)*map.factor);
                        monitor.y = Qt.binding(() => map.offsetY+(monitor.anchorMonitor.y-map.minY)*map.factor);
                    }
                }
            }
        }
    }

    // Selected display
    SettingsSection {
        visible: root.current !== null
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                GlowText { text: root.current?.name || ""; font.family: Theme.labelFont; font.pixelSize: Theme.title; color: Theme.green }
                GlowText { text: root.current?.description || "No display information available."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideRight }
            }
            ChoiceChips {
                visible: root.draft.length > 1; Layout.maximumWidth: root.width * .55
                accessibleLabel: "Display"; options: root.draft.map((m,i) => ({value:i, label:m.name})); current: root.selected
                onChosen: value => root.selected = value
            }
        }
        GridLayout {
            objectName:"displayMode"; enabled: !root.locked
            Layout.fillWidth: true; columns: root.width < 620 ? 1 : 2; columnSpacing: 20; rowSpacing: 12
            GlowText { text: "Resolution"; color: Theme.muted; font.pixelSize: Theme.small }
            StationCombo {
                Layout.fillWidth: true; model: root.resolutions(root.current); textRole: "label"; Accessible.name: "Resolution"
                currentIndex: model.findIndex(r => r.value === (root.current ? root.current.width+"x"+root.current.height : ""))
                onActivated: root.chooseResolution(model[currentIndex].value)
            }
            GlowText { text: "Refresh rate"; color: Theme.muted; font.pixelSize: Theme.small }
            ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Refresh rate"; options: root.rates(root.current); current: root.current?.mode; onChosen: value => root.chooseMode(value) }
            GlowText { text: "Scale"; color: Theme.muted; font.pixelSize: Theme.small }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Scale"; options: [1,1.25,1.5,1.75,2].map(v => ({value:v, label:Math.round(v*100)+"%"})); current: root.current?.scale; onChosen: value => root.change("scale", value) }
                StationField { Layout.preferredWidth: 72; text: String(root.current?.scale ?? 1); Accessible.name: "Custom scale"; onCommit: value => root.change("scale", Number(value)) }
            }
            GlowText { text: "Rotation"; color: Theme.muted; font.pixelSize: Theme.small }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Rotation"; options: [{value:0,label:"Normal"},{value:1,label:"90°"},{value:2,label:"180°"},{value:3,label:"270°"}]; current: (root.current?.transform ?? 0) % 4; onChosen: value => root.change("transform", value + ((root.current?.transform ?? 0) >= 4 ? 4 : 0)) }
                StationButton { text: "Flipped"; checked: (root.current?.transform ?? 0) >= 4; onClicked: root.change("transform", (root.current.transform % 4) + (root.current.transform >= 4 ? 0 : 4)) }
            }
            GlowText { text: "Position X / Y"; color: Theme.muted; font.pixelSize: Theme.small }
            RowLayout {
                Layout.fillWidth: true
                StationField { Layout.fillWidth: true; text: String(root.current?.x ?? 0); Accessible.name: "Position X"; onCommit: value => root.change("x", Number(value)) }
                StationField { Layout.fillWidth: true; text: String(root.current?.y ?? 0); Accessible.name: "Position Y"; onCommit: value => root.change("y", Number(value)) }
            }
        }
        SettingRow {
            objectName: "mirror"; Layout.fillWidth: true; highlighted: root.highlightKey === "mirror"
            readonly property var mirroredBy: root.draft.filter(m => m.mirror === root.current?.name).map(m => m.name)
            enabled: root.draft.length > 1 && mirroredBy.length === 0 && !root.locked
            title: "Mirroring"
            description: root.draft.length < 2 ? "Connect another display to mirror it." : mirroredBy.length ? "Shown on " + mirroredBy.join(", ") + ". Stop mirroring there first." : "Show another display’s picture here instead of its own desktop."
            StationCombo {
                Layout.fillWidth: true; textRole: "label"; Accessible.name: "Mirror"
                model: [{value:"", label:"Extend — own desktop"}].concat(root.draft.filter(m => m.name !== root.current?.name && !m.mirror).map(m => ({value:m.name, label:"Mirror " + m.name})))
                currentIndex: Math.max(0, model.findIndex(m => m.value === (root.current?.mirror || "")))
                onActivated: root.change("mirror", model[currentIndex].value)
            }
        }
        SettingRow {
            objectName:"vrr"; Layout.fillWidth:true; title:"Variable Refresh Rate"; enabled:root.current?.vrrAvailable===true && !root.locked; highlighted: root.highlightKey === "vrr"
            description:!root.current?.vrrAvailable ? "VRR status is not exposed by this display.":"Request adaptive sync on compatible hardware. Currently "+(root.current.vrrActive ? "active":"inactive")+". Changes are included in the display trial."
            StationCombo {
                Layout.fillWidth:true; Accessible.name: "Variable Refresh Rate"
                model:[{value:-2,label:"Keep existing policy"},{value:-1,label:"Follow global policy"},{value:0,label:"Off"},{value:1,label:"On"},{value:2,label:"Fullscreen only"},{value:3,label:"Fullscreen games / video"}]; textRole:"label"
                currentIndex:model.findIndex(m=>m.value===(root.current?.vrrPolicy ?? -2))
                onActivated:root.change("vrrPolicy",model[currentIndex].value)
            }
        }
    }

    // Test / discard
    Flow {
        visible: DesktopSettings.pending === null; Layout.fillWidth: true; spacing: 8
        StationButton { text: "Test display layout"; accent: Theme.green; checked: root.dirty; enabled: root.dirty && !DesktopSettings.busy; onClicked: DesktopSettings.apply({action:"displays",monitors:root.draft,expected:root.base}) }
        StationButton { text: "Discard changes"; enabled: root.dirty && !DesktopSettings.busy; onClicked: { root.load(); root.notice = ""; } }
        GlowText { visible: root.notice !== "" || root.dirty; height: 36; verticalAlignment: Text.AlignVCenter; text: root.notice || "Unapplied changes. Testing keeps them for 20 seconds unless you choose Keep."; color: Theme.teal; font.pixelSize: Theme.small }
    }

    // Main display
    SettingsSection {
        objectName: "mainDisplay"
        heading: "Main display"; badge: Config.saved.mainDisplay || "Follows focus"
        caption: "CEDAR panels, notifications, and volume controls open on this screen. If it disconnects, CEDAR follows the focused display."
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 1 : 2; columnSpacing: 8
            StationCombo {
                Layout.fillWidth: true; model: root.mainChoices; textRole: "label"; Accessible.name: "Main display"
                currentIndex: root.mainChoices.findIndex(m=>m.name===Config.saved.mainDisplay)
                onActivated: Config.set("mainDisplay", root.mainChoices[currentIndex].name)
            }
            StationButton {
                text: DesktopSettings.busy && DesktopSettings.operation === "primary" ? "Applying…" : "Apply system default"
                enabled: root.outputs.includes(Config.saved.mainDisplay) && !root.locked
                onClicked: DesktopSettings.apply({action:"primary",output:Config.saved.mainDisplay})
            }
        }
        GlowText {
            visible: DesktopSettings.operation === "primary" && (DesktopSettings.busy || DesktopSettings.error !== "" || DesktopSettings.message !== "")
            text: DesktopSettings.busy ? "Applying the main display…" : DesktopSettings.error || DesktopSettings.message
            color: DesktopSettings.error ? Theme.amber : Theme.green
            Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
        GlowText {
            text: "System default: " + (DesktopSettings.data.owned.mainDisplay || "not set by CEDAR") + ". Apply also sets the startup cursor and the main screen for X11 games. Native apps follow the focused screen."
            color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11
        }
    }

    // Saved layouts
    SettingsSection {
        objectName: "profiles"
        heading: "Saved layouts"; badge: root.profiles.length ? root.profiles.length + " saved" : ""
        caption: "Keep arrangements for the desk, the dock, or the projector. Loading one fills in the draft above; it is applied only after a successful test."
        Repeater {
            model: root.profiles
            ColumnLayout {
                id: profile
                required property var modelData
                readonly property bool ready: root.profileReady(modelData)
                Layout.fillWidth: true; spacing: 6
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.teal,.10) }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Rectangle { width: 8; height: 8; radius: 4; color: profile.ready ? Theme.green : Theme.muted }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        GlowText { text: profile.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                        GlowText { text: profile.ready ? root.profileSummary(profile.modelData) : "For " + profile.modelData.monitors.map(m => m.name).join(" + ") + " · connect exactly these displays to load it"; color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    StationButton { text: "Load"; enabled: profile.ready && !root.locked; onClicked: root.loadProfile(profile.modelData) }
                    StationButton { text: root.confirmDelete === profile.modelData.name ? "Confirm delete" : "Delete"; accent: root.confirmDelete === profile.modelData.name ? Theme.amber : Theme.teal; enabled: !root.locked
                        onClicked: { if (root.confirmDelete === profile.modelData.name) { DesktopSettings.apply({action:"delete-profile",name:profile.modelData.name}); root.confirmDelete = ""; } else root.confirmDelete = profile.modelData.name; } }
                }
            }
        }
        GlowText { visible: !root.profiles.length; text: "No saved layouts yet."; color: Theme.muted; font.pixelSize: Theme.small }
        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8
            StationField { id: profileName; Layout.fillWidth: true; placeholderText: "Layout name, e.g. Desk"; Accessible.name: "Layout name"; maximumLength: 40; onAccepted: saveProfile.clicked() }
            StationButton {
                id: saveProfile
                text: root.profiles.some(p => p.name === profileName.text.trim()) ? "Replace layout" : "Save this layout"
                enabled: profileName.text.trim() !== "" && !root.locked && root.draft.length > 0
                onClicked: { DesktopSettings.apply({action:"save-profile",name:profileName.text.trim(),monitors:root.draft,mainDisplay:Config.saved.mainDisplay || ""}); profileName.text = ""; }
            }
        }
        GlowText {
            visible: ["save-profile","delete-profile"].includes(DesktopSettings.operation) && (DesktopSettings.error !== "" || DesktopSettings.message !== "")
            text: DesktopSettings.error || DesktopSettings.message; color: DesktopSettings.error ? Theme.amber : Theme.green
            Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
    }
    GlowText { text:"HDR is not offered here because its support has not been verified. Every active display stays enabled during a trial."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted; font.pixelSize:Theme.small }
}
