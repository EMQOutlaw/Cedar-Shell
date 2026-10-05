import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema
import "../services"
Rectangle {
    id: root
    property bool active:false
    property string section:"overview"
    property string highlightKey:""
    property bool navigationOpen:false
    property string pendingPage:""
    property string pendingAnchor:""
    property bool resetConfirm:false
    readonly property bool dirty:loader.item?.dirty === true
    readonly property bool narrow:width<760
    readonly property var page:Schema.pages.find(p=>p.id===section) || Schema.pages[0]
    readonly property var searchEntries:Schema.fields.concat(DefaultApps.data.roles.map(r=>({page:"apps",key:r.id,label:r.label,description:r.description,aliases:"default applications"})),Schema.pages.map(p=>({page:p.id,key:"",label:p.label,description:p.description})),Schema.extras.filter(e=>e.key!=="vrr" || DesktopSettings.data.monitors.some(m=>"vrr" in m)),Schema.inputFields.filter(f=>f.key in DesktopSettings.data.input && (!f.key.startsWith("touchpad:") || DesktopSettings.data.hasTouchpad===true)).map(f=>Object.assign({page:"input"},f)))
    readonly property var results:Schema.search(searchEntries,search.text)
    property alias searchText:search.text
    color:Qt.alpha(Theme.background,Config.panelOpacity); radius:Config.panelRadius
    border.color:Qt.alpha(Theme.teal,.22); border.width:1
    clip:true
    function navigate(page,anchor="") {
        if(loader.item && loader.item.dirty && section!==page) {pendingPage=page;pendingAnchor=anchor;return;}
        Forest.record("settings","Settings / "+(Schema.pages.find(p=>p.id===page)?.label || page),page);
        section=page;highlightKey=anchor;search.text="";navigationOpen=false;resetConfirm=false;
        Qt.callLater(reveal.restart);
    }
    function findItem(item,name) {
        if(!item) return null;
        if(item.objectName===name) return item;
        for(let child of item.children || []) { const found=findItem(child,name); if(found) return found; }
        return null;
    }
    function revealSetting() {
        const item=highlightKey ? findItem(loader.item,highlightKey):null;
        if(item) {const point=item.mapToItem(content,0,0);scroll.contentItem.contentY=Math.max(0,Math.min(point.y-24,content.height-scroll.height));}
        else scroll.contentItem.contentY=0;
        highlightTimer.restart();
    }
    function resetPage() {
        if(section==="bar") Config.resetBar();
        else Schema.fields.filter(f=>f.page===section).forEach(f=>Config.set(f.key,f.defaultValue));
        if(section==="core")Config.set("coreMonitor","");
        resetConfirm=false;
    }
    onSectionChanged:{if(active)ShellState.settingsSection=section;highlightKey="";resetConfirm=false;Qt.callLater(()=>scroll.contentItem.contentY=0);}
    onActiveChanged:if(active){ShellState.settingsSection=section;SettingsInfo.refresh();DefaultApps.refresh();DesktopSettings.refresh();Controls.refresh();if(ShellState.settingsPage){root.navigate(ShellState.settingsPage, ShellState.settingsAnchor);ShellState.settingsPage="";ShellState.settingsAnchor="";}}
    Component.onCompleted:if(active){SettingsInfo.refresh();DefaultApps.refresh();DesktopSettings.refresh();}
    Timer { id:reveal; interval:120; onTriggered:root.revealSetting() }
    Timer { id:highlightTimer; interval:4000; onTriggered:root.highlightKey="" }
    Shortcut { sequence:"Ctrl+F"; enabled:root.active && !(loader.item?.recording===true); onActivated:{search.forceActiveFocus();search.selectAll();} }
    MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons }
    CedarAtmosphere { anchors.fill:parent; active:root.active && Config.saved.ambientIntensity>0; opacity:Config.saved.ambientIntensity*.35 }
    ColumnLayout {
        anchors.fill:parent; anchors.margins:root.narrow ? 16:24; spacing:16
        Item {
            Layout.fillWidth:true; implicitHeight:root.narrow ? 100:50
            ColumnLayout {
                anchors.left:parent.left; anchors.top:parent.top; spacing:3
                GlowText { text:"CEDAR"; font.family:Theme.labelFont; font.pixelSize:25; color:Theme.green }
                GlowText { text:"Settings"; color:Theme.muted; font.pixelSize:Theme.small }
            }
            StationField {
                id:search; objectName:"settingsSearch"
                anchors.right:parent.right; anchors.rightMargin:root.narrow ? 0:52
                anchors.top:parent.top; anchors.topMargin:root.narrow ? 60:2
                width:root.narrow ? parent.width:Math.min(420,parent.width-205)
                placeholderText:"Search settings…"; Accessible.name:"Search Settings"
                onTextChanged:resultsList.currentIndex=0
                Keys.onDownPressed:{if(root.results.length){resultsList.forceActiveFocus();resultsList.currentIndex=0;}}
                Keys.onReturnPressed:if(root.results.length)root.navigate(root.results[0].page,root.results[0].key || "")
                Keys.onEscapePressed:{text="";focus=false;}
            }
            StationButton { anchors.right:parent.right; anchors.top:parent.top; text:"×"; iconOnly:true; hint:"Close Settings"; onClicked:ShellState.close() }
        }
        Rectangle { Layout.fillWidth:true; implicitHeight:1; color:Qt.alpha(Theme.teal,.15) }
        StationButton { visible:root.narrow; text:(root.navigationOpen ? "←  Back to ":"☰  ")+root.page.label; checked:root.navigationOpen; onClicked:root.navigationOpen=!root.navigationOpen }
        RowLayout {
            Layout.fillWidth:true; Layout.fillHeight:true; spacing:24
            ScrollView {
                id:nav; visible:!root.narrow || root.navigationOpen
                Layout.preferredWidth:root.narrow ? -1:208; Layout.fillWidth:root.narrow; Layout.fillHeight:true
                contentWidth:availableWidth; clip:true; ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
                ColumnLayout {
                    width:nav.availableWidth; spacing:3
                    Repeater {
                        model:Schema.pages
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth:true; spacing:4
                            GlowText { visible:modelData.group!==""; text:modelData.group; font.pixelSize:10; color:Theme.muted; Layout.topMargin:14; Layout.bottomMargin:3; Layout.leftMargin:12 }
                            StationButton {
                                Layout.fillWidth:true; implicitHeight:40; checked:root.section===modelData.id
                                text:modelData.icon+"  "+modelData.label
                                contentItem:Text { text:parent.text; font.family:Theme.dataFont; font.pixelSize:Theme.small; color:parent.checked ? Theme.green:Theme.text; verticalAlignment:Text.AlignVCenter; leftPadding:4 }
                                onClicked:root.navigate(modelData.id)
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                visible:!root.narrow || !root.navigationOpen; Layout.fillWidth:true; Layout.fillHeight:true; spacing:12
                SettingsCard {
                    visible:root.pendingPage!==""; Layout.fillWidth:true; padding:12
                    GlowText { text:"You have unapplied changes on this page."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.amber }
                    Flow { Layout.fillWidth:true; spacing:8
                        StationButton { text:"Discard and continue"; onClicked:{if(root.section==="input")DesktopSettings.loadInput();const p=root.pendingPage,a=root.pendingAnchor;root.pendingPage="";root.section=p;root.navigate(p,a);} }
                        StationButton { text:"Keep editing"; onClicked:root.pendingPage="" }
                    }
                }
                ListView {
                    id:resultsList; visible:search.text.trim()!==""; Layout.fillWidth:true; Layout.fillHeight:true
                    model:root.results; clip:true; spacing:6; keyNavigationEnabled:true
                    ScrollBar.vertical:ScrollBar {}
                    Keys.onReturnPressed:if(currentIndex>=0 && root.results[currentIndex])root.navigate(root.results[currentIndex].page,root.results[currentIndex].key || "")
                    Keys.onEscapePressed:{search.text="";search.forceActiveFocus();}
                    delegate:StationButton {
                        required property var modelData
                        required property int index
                        width:ListView.view.width; implicitHeight:82; checked:ListView.isCurrentItem
                        onClicked:root.navigate(modelData.page,modelData.key || "")
                        contentItem:ColumnLayout {
                            spacing:4
                            GlowText { text:modelData.label; color:Theme.text; Layout.fillWidth:true; elide:Text.ElideRight }
                            GlowText { text:(Schema.pages.find(p=>p.id===modelData.page)?.label || "")+(modelData.group ? "  →  "+modelData.group:""); color:Theme.teal; font.pixelSize:Theme.small }
                            GlowText { text:modelData.description || ""; color:Theme.muted; font.pixelSize:Theme.small-1; Layout.fillWidth:true; elide:Text.ElideRight }
                        }
                    }
                    GlowText { visible:!root.results.length; width:parent.width; wrapMode:Text.WordWrap; text:"No available settings match “"+search.text+"”. Try a device or category name."; color:Theme.muted }
                }
                ScrollView {
                    id:scroll; visible:!search.text.trim(); Layout.fillWidth:true; Layout.fillHeight:true
                    contentWidth:availableWidth; clip:true; ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
                    ColumnLayout {
                        id:content; width:scroll.availableWidth; spacing:16
                        ColumnLayout {
                            Layout.fillWidth:true; spacing:6
                            GlowText { text:root.page.label; font.family:Theme.labelFont; font.pixelSize:Math.round(28*Theme.fontScale); Layout.fillWidth:true }
                            GlowText { text:root.page.description; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                        }
                        GlowText {
                            visible:["displays","input","keybinds"].includes(root.section) && (DesktopSettings.busy || DesktopSettings.error!=="" || DesktopSettings.message!=="")
                            text:DesktopSettings.busy ? "Reading your desktop…":DesktopSettings.error || DesktopSettings.message
                            color:DesktopSettings.error ? Theme.amber:Theme.teal; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small
                        }
                        GlowText { visible:SettingsInfo.error!=="" || SettingsInfo.message!==""; text:SettingsInfo.error || SettingsInfo.message; color:SettingsInfo.error ? Theme.amber:Theme.teal; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                        GlowText { visible:Config.persistenceMessage!==""; text:Config.persistenceMessage; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                        Loader {
                            id:loader; Layout.fillWidth:true
                            asynchronous:true
                            active:root.active || !!item?.dirty
                            sourceComponent:({setup:setupPage,overview:overview,appearance:appearance,desktop:desktop,apps:appsPage,bar:bar,core:corePage,displays:displays,input:input,keybinds:keybinds,connections:connections,audio:audio,notifications:notifications,power:power,time:time,system:system,about:about})[root.section] || overview
                            onLoaded:Qt.callLater(reveal.restart)
                        }
                        Flow {
                            Layout.fillWidth:true; spacing:8; Layout.topMargin:20; Layout.bottomMargin:16
                            visible:Schema.fields.some(f=>f.page===root.section)
                            StationButton { text:root.resetConfirm ? "Confirm reset":"Reset "+root.page.label; accent:root.resetConfirm ? Theme.amber:Theme.teal; onClicked:root.resetConfirm ? root.resetPage():root.resetConfirm=true }
                            StationButton { visible:root.resetConfirm; text:"Cancel"; onClicked:root.resetConfirm=false }
                            GlowText { visible:root.resetConfirm; text:"Only this page’s CEDAR preferences will reset."; color:Theme.muted; font.pixelSize:Theme.small; width:Math.min(360,parent.width); wrapMode:Text.WordWrap }
                        }
                    }
                }
            }
        }
    }
    Component { id:overview; SettingsOverview { onNavigate:(page,anchor)=>root.navigate(page,anchor) } }
    Component { id:appearance; AppearanceSettings { highlightKey:root.highlightKey } }
    Component { id:setupPage; FirstRunSettings { active:root.active; onNavigate:page=>root.navigate(page) } }
    Component { id:appsPage; DefaultAppsSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:desktop; DesktopSettingsPage { highlightKey:root.highlightKey } }
    Component { id:bar; TopBarSettings { highlightKey:root.highlightKey } }
    Component { id:corePage; CoreSettings { highlightKey:root.highlightKey } }
    Component { id:displays; DisplaySettings { active:root.active } }
    Component { id:input; InputSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:keybinds; KeybindSettings { active:root.active } }
    Component { id:connections; ColumnLayout {
        id:connectionPage
        property bool bluetooth:false
        Component.onCompleted:bluetooth=root.highlightKey==="bluetooth"
        Connections { target:root; function onHighlightKeyChanged(){if(root.highlightKey==="bluetooth")connectionPage.bluetooth=true;else if(root.highlightKey==="wifi")connectionPage.bluetooth=false;} }
        Layout.fillWidth:true; spacing:16
        RowLayout {
            StationButton { text:"Wi-Fi & VPN"; checked:!parent.parent.bluetooth; onClicked:parent.parent.bluetooth=false }
            StationButton { text:"Bluetooth"; checked:parent.parent.bluetooth; onClicked:parent.parent.bluetooth=true }
        }
        Loader { Layout.fillWidth:true; sourceComponent:parent.bluetooth ? bt:net }
        Component { id:net; ConnectionSettings { active:root.active } }
        Component { id:bt; BluetoothSettings { active:root.active } }
    } }
    Component { id:audio; AudioSettings {} }
    Component { id:notifications; ColumnLayout {
        spacing:12
        SettingsFields { Layout.fillWidth:true; page:"notifications"; highlightKey:root.highlightKey }
        SettingRow { Layout.fillWidth:true; title:"Notification history"; description:NoticeStore.history.length+" retained notifications"; StationButton { text:"Open history"; onClicked:ShellState.toggle("history") } }
    } }
    Component { id:power; PowerSettings { highlightKey:root.highlightKey } }
    Component { id:time; ColumnLayout {
        spacing:12
        SystemClock { id:clock; precision:SystemClock.Minutes }
        SettingsCard {
            Layout.fillWidth:true
            GlowText { text:Config.formatTime(clock.date); font.family:Theme.labelFont; font.pixelSize:46; color:Theme.green }
            GlowText { text:Config.formatDate(clock.date); color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
        }
        SettingsFields { Layout.fillWidth:true; page:"time"; highlightKey:root.highlightKey }
    } }
    Component { id:system; SystemSettings {} }
    Component { id:about; AboutSettings {} }
}
