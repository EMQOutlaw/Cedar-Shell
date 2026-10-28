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
    visible: true; color: TM.base
    font.family: TM.font; font.pixelSize: 14*TM.scale
    palette.window: TM.base; palette.base: TM.surface; palette.button: TM.elevated
    palette.text: TM.text; palette.buttonText: TM.text; palette.windowText: TM.text
    palette.highlight: TM.accent; palette.highlightedText: TM.base
    property int page: Task.preferences.page || 0
    property int performanceResource: 0
    property string confirmationIdentity: ""
    property string confirmationName: ""
    readonly property bool compactHeader: width<1000*TM.scale
    readonly property var sections: ["Overview","Processes","Performance","Services"]
    function forceStop(identity,name) { confirmationIdentity=identity;confirmationName=name;confirm.open(); }
    onVisibilityChanged: value => Task.visibility(visible && value!==Window.Minimized)
    onPageChanged: { if(page===3) Task.refreshServices(); if(TM.motion) pageEntrance.restart(); }
    onClosing: Task.savePreferences(width,height,page)
    Component.onCompleted: { if(page===3)Task.refreshServices();if(TM.motion)pageEntrance.restart(); }
    ParallelAnimation {
        id: pageEntrance
        NumberAnimation { target: content; property: "opacity"; from: .65; to: 1; duration: TM.ms(180) }
        NumberAnimation { target: content; property: "translation"; from: 5; to: 0; duration: TM.ms(220); easing.type: Easing.OutCubic }
    }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Escape"; onActivated: { if(confirm.opened)confirm.close();else if(preferences.opened)preferences.close();else processes.dismiss(); } }
    Shortcut { sequence: "Ctrl+F"; onActivated: {if(win.page>1)win.page=1;processes.openSearch();} }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.page=0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.page=1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.page=2 }
    Shortcut { sequence: "Ctrl+4"; onActivated: win.page=3 }
    header: Item {
        implicitHeight: win.compactHeader ? 102 : 62
        Rectangle { anchors.fill: parent; color: TM.surface }
        Image { anchors.fill: parent; source: "grain.svg"; fillMode: Image.Tile; opacity: .025; visible: TM.effects }
        Image { x: 18; y: 17; width: 27; height: 27; source: "../data/icons/cedar-station.svg"; sourceSize.width: 54; sourceSize.height: 54 }
        Column {
            x: 56; y: 14; spacing: 0
            TMText { text: "CEDAR"; font.pixelSize: 16*TM.scale; font.letterSpacing: 3; color: TM.accent }
            TMText { text: "TASK MANAGER"; technical: true; font.pixelSize: 9*TM.scale; font.letterSpacing: 1.5 }
        }
        Rectangle {
            id: navigation
            x: win.compactHeader ? 18 : 235*TM.scale; y: win.compactHeader ? 62 : 14
            width: win.compactHeader ? parent.width-36 : Math.min(430*TM.scale,parent.width-x-240)
            height: 34; radius: 4; color: TM.base
            Rectangle {
                x: win.page*navigation.width/4+2; y: 2; width: navigation.width/4-4; height: navigation.height-4
                radius: 3; color: TM.elevated
                Behavior on x { enabled: TM.motion; NumberAnimation { duration: TM.ms(220); easing.type: Easing.OutCubic } }
                LivingEdge { anchors.bottom: parent.bottom; width: parent.width; active: true }
            }
            Row {
                anchors.fill: parent
                Repeater { model: win.sections
                    TMButton { required property int index; required property string modelData; width: navigation.width/4; height: navigation.height; text: modelData; checked: index===win.page
                        onClicked: win.page=index
                        background: Rectangle { radius: 4; color: "transparent"; border.width: parent.visualFocus ? 2 : 0; border.color: TM.accent }
                        Accessible.role: Accessible.PageTab; Accessible.name: modelData; Accessible.description: "Ctrl+"+(index+1)
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 18; y: 16; spacing: 12
            Rectangle { width: 5; height: 5; radius: 3; y: 13; color: Task.connected ? TM.accent : TM.warning }
            TMHeading { width: win.width<650 ? 85 : 120; height: 32; text: Task.connected ? "LIVE / "+((Task.snapshot.sampleIntervalMs || 1000)/1000)+" s" : "CONNECTING"; size: 11; color: Task.connected ? TM.accent : TM.warning; font.family: TM.mono }
            TMButton { id: preferencesButton; text: "⋯"; implicitWidth: 32; onClicked: preferences.open(); Accessible.name: "Display preferences" }
        }
        LivingEdge { anchors.bottom: parent.bottom; width: parent.width; active: false }
    }
    footer: Rectangle {
        implicitHeight: Math.max(30,footerText.implicitHeight+12); color: TM.base
        Rectangle { height: 1; width: parent.width; color: Qt.alpha(TM.border,.4) }
        TMText { id: footerText; x: 18; y: 6; width: parent.width-36; text: !Task.connected ? Task.status : Task.message || "CPU in Processes: 100% = one logical core   ·   "+Task.gaming; color: !Task.connected || Task.actionFailed ? TM.warning : TM.muted; font.pixelSize: 11*TM.scale; wrapMode: Text.WordWrap; maximumLineCount: 2 }
    }
    Item {
        id: content; anchors.fill: parent; anchors.margins: win.width<650 ? 12 : 18
        property real translation: 0
        transform: Translate { y: content.translation }
        ColumnLayout {
            anchors.fill: parent; spacing: 10
            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 26*TM.scale
                TMHeading { text: win.sections[win.page]; size: 22; Layout.fillWidth: true }
                TMText { text: win.page===0 ? "SYSTEM / LIVE INSTRUMENTS" : win.page===1 ? "PROCESS / CONTROL" : win.page===2 ? "RESOURCE / DIAGNOSTICS" : "SYSTEMD / USER SESSION"; technical: true; secondary: true; visible: win.width>720; font.letterSpacing: 1 }
            }
            Item { Layout.fillWidth: true; Layout.fillHeight: true
                ProcessWorkspace { id: processes; anchors.fill: parent; visible: win.page<2; overview: win.page===0; onForceStop: (identity,name)=>win.forceStop(identity,name) }
                Loader { anchors.fill: parent; active: win.page===2; sourceComponent: PerformanceView { resource: win.performanceResource; onResourceChanged: win.performanceResource=resource } }
                Loader { id: serviceLoader; anchors.fill: parent; active: win.page===3; sourceComponent: ServicesView {} }
            }
        }
    }
    Popup {
        id: preferences; x: Math.max(12,win.width-width-18); y: 55; width: Math.min(350,win.width-24); padding: 18; modal: false
        background: Rectangle { color: TM.surface; border.color: TM.border; radius: 8 }
        contentItem: ColumnLayout { spacing: 12
            TMHeading { text: "Display preferences"; size: 21 }
            TMText { Layout.fillWidth: true; text: "CEDAR’s theme, fonts and accessibility settings apply here."; secondary: true; wrapMode: Text.WordWrap }
            ComboBox { Layout.fillWidth: true; model: ["Follow CEDAR","Full","Reduced","Minimal"]; currentIndex: Math.max(0,["auto","full","reduced","minimal"].indexOf(Task.style.visualMode || "auto")); onActivated: Task.setVisualMode(["auto","full","reduced","minimal"][currentIndex]); Accessible.name: "Effects level" }
            TMText { Layout.fillWidth: true; text: "Reduced Motion always takes precedence. Minimal removes transitions and material effects."; secondary: true; font.pixelSize: 12*TM.scale; wrapMode: Text.WordWrap }
        }
    }
    Dialog {
        id: confirm; title: "Force stop process?"; modal: true; anchors.centerIn: parent; width: Math.min(win.width-40,450)
        standardButtons: Dialog.Cancel | Dialog.Yes
        contentItem: TMText { text: win.confirmationName+"\n\nUnsaved work may be lost. Send SIGKILL to this exact process?"; wrapMode: Text.WordWrap }
        onAccepted: Task.action(win.confirmationIdentity,"kill",0,true)
    }
    Timer { interval: 28000; running: Task.testing; onTriggered: Task.finishTest(false,"UI test deadline; samples="+Task.samples) }
    Timer {
        id: selfTest; interval: 450; repeat: true; running: Task.testing
        property int step: 0
        property bool restartChecked: false
        property int resumeAt: 0
        onTriggered: {
            if(Task.failureTest()) {
                if(Task.status.indexOf("Fixture collector denied startup")>=0) { Task.finishTest(!Task.connected&&Task.processCount===0&&Object.keys(Task.snapshot).length===0,"Collector startup error is visible and readings are cleared");stop(); }
                return;
            }
            if(Task.samples<2)return;
            if(!restartChecked){restartChecked=true;resumeAt=Task.samples+2;if(Task.restartForTest())return;}
            if(Task.samples<resumeAt)return;
            if(step===0){win.width=1180;win.height=820;if(!Task.exerciseModel()){Task.finishTest(false,"Process batch/filter/sort/identity");return;}win.page=1;}
            else if(step===1){if(!Task.firstIdentity())return;Task.select(Task.firstIdentity());}
            else if(step===2){if(!processes.inspecting){Task.finishTest(false,"Inspector did not open");return;}Task.capture(win,"processes");Task.select("");win.page=2;}
            else if(step===3){Task.capture(win,"performance");win.page=3;}
            else if(step===4){Task.capture(win,"services");win.width=520;win.height=440;win.page=1;Task.select(Task.firstIdentity());}
            else if(step===5){Task.capture(win,"narrow-inspector");Task.select("");processes.searchField.text="no-process-matches-this";}
            else if(step===6){if(Task.processCount!==0){Task.finishTest(false,"Search debounce");return;}processes.searchField.text="";}
            else if(step===7){win.width=1180;win.height=820;win.page=0;}
            else if(step===8){Task.capture(win,"overview");win.page=2;win.performanceResource=1;}
            else if(step===9){Task.capture(win,"memory");win.performanceResource=2;}
            else if(step===10){Task.capture(win,"gpu");win.performanceResource=3;}
            else if(step===11){Task.capture(win,"storage");win.performanceResource=4;}
            else if(step===12){Task.capture(win,"network");win.page=3;}
            else if(step===13){if(serviceLoader.item && Task.services.length)serviceLoader.item.selectedName=Task.services[0].name;}
            else if(step===14){Task.capture(win,"service-details");win.page=1;Task.select(Task.firstIdentity());}
            else if(step>=15 && step<=24){
                Task.select(step%2 ? "" : Task.firstIdentity());
                if(step===23)Task.setVisualMode("minimal");
                if(step===24){if(TM.tier!==2){Task.finishTest(false,"Minimal effects policy");return;}Task.capture(win,"minimal");Task.setVisualMode("reduced");}
            }
            else if(step===25){if(TM.tier!==(Task.style.reducedMotion?2:1)){Task.finishTest(false,"Reduced effects policy");return;}Task.setVisualMode("auto");Task.capture(win,"inspector-cycles");Task.select("");win.page=0;if(!Task.nativeRendering()){win.width=1920;win.height=1080;}}
            else if(step===26){Task.capture(win,"desktop");if(!Task.nativeRendering()){win.width=2560;win.height=1440;}}
            else if(step===27){Task.capture(win,"large");if(!Task.nativeRendering()){win.width=3440;win.height=1440;}}
            else if(step===28){Task.capture(win,"ultrawide");win.width=1180;win.height=820;}
            else if(step===29){win.width=520;win.height=440;win.page=0;}
            else if(step===30){Task.capture(win,"narrow-overview");win.performanceResource=0;win.page=2;}
            else if(step===31){Task.capture(win,"narrow-performance");win.page=3;}
            else if(step===32){Task.capture(win,"narrow-services");win.page=0;win.width=1180;win.height=820;}
            else if(step===33){Task.finishTest(Task.capture(win),"Standalone views, live telemetry, 6000 process rows, search, sort, inspector and screenshot");stop();}
            step++;
        }
    }
}
