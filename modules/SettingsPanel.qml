import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema
import "../services"
Rectangle {
    id: root
    property bool active: false
    property bool hasOpened: false
    readonly property string section: SettingsService.page
    property string highlightKey: SettingsService.anchor
    property bool navigationOpen: false
    readonly property string pendingPage: SettingsService.pendingPage
    readonly property string pendingAnchor: SettingsService.pendingAnchor
    property bool resetConfirm: false
    readonly property bool dirty: loader.item?.dirty === true
    readonly property bool narrow: width < 980
    readonly property real railWidth: narrow ? 0 : Math.max(220, Math.min(280, width * .205))
    readonly property var page: Schema.pages.find(p => p.id === section) || Schema.pages[0]
    readonly property string groupLabel: Schema.groupOf(page.id)
    readonly property var results: SettingsService.search(search.text)
    property alias searchText: search.text
    color: Theme.background; clip: true
    function navigate(page, anchor="") { SettingsService.navigate(page, anchor); }
    Connections {
        target: SettingsService
        function onGenerationChanged() {
            root.highlightKey=SettingsService.anchor;
            search.text=""; root.navigationOpen=false; root.resetConfirm=false; Qt.callLater(reveal.restart);
        }
    }
    Binding { target: SettingsService; property: "blocked"; value: root.dirty }
    function discardPending() {
        if(loader.item && typeof loader.item.discard === "function") loader.item.discard();
        else if(root.section==="input") DesktopSettings.loadInput();
        else if(root.section==="displays" && loader.item) loader.item.load();
        SettingsService.confirmPending();
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
    function resetPage() { SettingsService.resetPage(section); resetConfirm=false; }
    onSectionChanged: { resetConfirm=false; Qt.callLater(()=>scroll.contentItem.contentY=0); }
    onActiveChanged: if(active) {
        hasOpened=true; SettingsInfo.refresh(); DefaultApps.refresh(); DesktopSettings.refresh(); Controls.refresh();
    }
    Component.onCompleted: if(active) {hasOpened=true; SettingsInfo.refresh(); DefaultApps.refresh(); DesktopSettings.refresh();}
    Timer { id:reveal; interval:120; onTriggered:root.revealSetting() }
    Timer { id:highlightTimer; interval:4000; onTriggered:root.highlightKey="" }
    Shortcut { sequences:["Ctrl+F","Ctrl+K"]; enabled:root.active && !(loader.item?.recording===true); onActivated:{search.forceActiveFocus();search.selectAll();} }
    Shortcut { sequence:"Alt+Left"; enabled:root.active && !(loader.item?.recording===true); onActivated:SettingsService.back() }
    SettingsBackdrop { x:root.railWidth; width:parent.width-x; height:Math.min(420,parent.height); strength:.25 }
    Rectangle { visible:!root.narrow; width:root.railWidth; height:parent.height; color:Qt.alpha(Theme.background,.94) }
    Rectangle { visible:!root.narrow; x:root.railWidth; width:1; height:parent.height; color:Qt.alpha(Theme.strataAccent,.18) }
    ChamferFrame { anchors.fill:parent; fill:Theme.transparent; stroke:Qt.alpha(Theme.strataAccent,.32); cut:Theme.strataCut }

    RowLayout {
        x:20; y:20; width:root.narrow ? parent.width-76 : root.railWidth-40; spacing:10
        ShieldMark { interactive:false; width:28; height:34; Layout.preferredWidth:28; Layout.preferredHeight:34 }
        ColumnLayout {
            spacing:1
            Text { text:"CEDAR"; font.family:Theme.labelFont; font.pixelSize:25; font.letterSpacing:3; color:Theme.strataText }
            Text { text:"STRATA CONTROL CENTER"; font.family:Theme.dataFont; font.pixelSize:7; font.letterSpacing:.6; color:Theme.strataMuted }
        }
    }
    MouseArea {
        x:root.narrow ? 240 : root.railWidth+20; y:0; width:Math.max(0,root.width-x-56); height:64
        onPressed: if(root.Window.window)root.Window.window.startSystemMove()
        Text { anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; visible:!root.narrow; text:"STRATA CONTROL CENTER"; font.family:Theme.dataFont; font.pixelSize:9; font.letterSpacing:2; color:Theme.strataMuted }
    }
    StrataButton { x:root.width-width-16; y:18; text:"×"; iconOnly:true; hint:"Close Settings"; onClicked:SettingsService.closeApp() }
    StrataButton { visible:root.narrow; x:16;y:78; text:"☰"; iconOnly:true; hint:"Settings navigation"; checked:root.navigationOpen; onClicked:root.navigationOpen=!root.navigationOpen }
    StationField {
        id:search; objectName:"settingsSearch"
        x:root.narrow ? 60 : 16; y:root.narrow ? 78 : 86
        width:root.narrow ? root.width-76 : root.railWidth-32
        placeholderText:"Search settings…"; Accessible.name:"Search Settings"
        onTextChanged:resultsList.currentIndex=0
        Keys.onDownPressed:if(root.results.length){resultsList.forceActiveFocus();resultsList.currentIndex=0;}
        Keys.onReturnPressed:if(root.results.length)root.navigate(root.results[0].page,root.results[0].key || "")
        Keys.onEscapePressed:{text="";focus=false;}
    }
    SettingsNavigation {
        visible:!root.narrow || root.navigationOpen
        x:root.narrow ? 16 : 12; y:132
        width:root.narrow ? root.width-32 : root.railWidth-24
        height:root.height-y-18
        onChosen:page=>root.navigate(page)
    }
    ColumnLayout {
        visible:!root.narrow || !root.navigationOpen
        x:root.narrow ? 16 : root.railWidth+28
        y:root.narrow ? 132 : 86
        width:Math.min(1400,root.width-x-(root.narrow ? 16:28))
        height:root.height-y-20; spacing:14
        RowLayout {
            Layout.fillWidth:true
            StrataButton { text:"←"; iconOnly:true; hint:"Back · Alt+Left"; enabled:SettingsService.canGoBack; onClicked:SettingsService.back() }
            SectionMark { Layout.fillWidth:true; text:Schema.indexOf(root.section)+" / "+(root.section==="overview" ? "OVERVIEW":root.groupLabel.toUpperCase()); tone:Theme.strataAccent; size:10 }
            StrataButton { text:SettingsService.advanced ? "Advanced: on":"Show advanced"; checked:SettingsService.advanced; hint:"Reveal advanced controls"; onClicked:SettingsService.toggleLevel() }
        }
        ColumnLayout {
            visible:!search.text.trim(); Layout.fillWidth:true; spacing:4
            GlowText { text:root.section==="overview" ? "Welcome to CEDAR":root.page.label; font.family:Theme.labelFont; font.pixelSize:Math.round((root.narrow ? 29:36)*Theme.fontScale); Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.strataText }
            GlowText { text:root.page.description; color:Theme.strataMuted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
        }
        SettingsSurface {
            visible:root.pendingPage!==""; padding:12; accent:Theme.amber
            GlowText { text:"You have unapplied changes on this page."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.amber }
            Flow { Layout.fillWidth:true; spacing:8
                StationButton { text:"Discard and continue"; onClicked:root.discardPending() }
                StationButton { text:"Keep editing"; onClicked:SettingsService.cancelPending() }
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
                    GlowText { text:modelData.label; Layout.fillWidth:true; elide:Text.ElideRight }
                    GlowText { text:(Schema.pages.find(p=>p.id===modelData.page)?.label || "")+(modelData.group ? " → "+modelData.group:""); color:Theme.strataAccent; font.pixelSize:Theme.small }
                    GlowText { text:modelData.description || ""; color:Theme.muted; font.pixelSize:Theme.small; Layout.fillWidth:true; elide:Text.ElideRight }
                }
            }
            GlowText { visible:!root.results.length; width:parent.width; wrapMode:Text.WordWrap; text:"No settings match. Try a device or category name."; color:Theme.muted }
        }
        ScrollView {
            id:scroll; visible:!search.text.trim(); Layout.fillWidth:true; Layout.fillHeight:true
            contentWidth:availableWidth; clip:true; ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
            ColumnLayout {
                id:content; width:scroll.availableWidth; spacing:16
                GlowText {
                    visible:["displays","input","keybinds"].includes(root.section) && (DesktopSettings.busy || DesktopSettings.error!=="" || DesktopSettings.message!=="")
                    text:DesktopSettings.busy ? "Reading your desktop…":DesktopSettings.error || DesktopSettings.message
                    color:DesktopSettings.error ? Theme.amber:Theme.teal; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small
                }
                GlowText { visible:SettingsInfo.error!=="" || SettingsInfo.message!==""; text:SettingsInfo.error || SettingsInfo.message; color:SettingsInfo.error ? Theme.amber:Theme.teal; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                GlowText { visible:Config.persistenceMessage!==""; text:Config.persistenceMessage; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                Loader {
                    id:loader; objectName:"settingsPageLoader"; Layout.fillWidth:true
                    asynchronous:true; active:root.active || root.hasOpened
                    sourceComponent:({setup:setupPage,overview:overview,appearance:appearance,"application-theming":applicationTheming,desktop:desktop,apps:appsPage,bar:bar,core:corePage,displays:displays,input:input,keybinds:keybinds,connections:connections,audio:audio,notifications:notifications,power:power,time:time,notes:notesPage,dictation:dictationPage,system:system,about:about,animations:animations,windows:windows,profiles:profiles,privacy:privacy,security:security,advanced:advanced})[root.section] || overview
                    onLoaded:Qt.callLater(reveal.restart)
                }
                Flow {
                    Layout.fillWidth:true; spacing:8; Layout.topMargin:12; Layout.bottomMargin:12
                    visible:root.section!=="overview" && Schema.fields.some(f=>f.page===root.section)
                    StrataButton { text:root.resetConfirm ? "Confirm reset":"Reset this page"; accent:root.resetConfirm ? Theme.amber:Theme.strataAccent; onClicked:root.resetConfirm ? root.resetPage():root.resetConfirm=true }
                    StrataButton { visible:root.resetConfirm; text:"Cancel"; onClicked:root.resetConfirm=false }
                    GlowText { visible:root.resetConfirm; text:"Only this page’s CEDAR preferences will reset."; color:Theme.strataMuted; font.pixelSize:Theme.small; width:Math.min(360,parent.width); wrapMode:Text.WordWrap }
                }
            }
        }
    }
    Component { id:overview; SettingsOverview { active:root.active } }
    Component { id:applicationTheming; ApplicationThemingSettings {} }
    Component { id:appearance; AppearanceSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:setupPage; FirstRunSettings { active:root.active } }
    Component { id:appsPage; DefaultAppsSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:desktop; DesktopSettingsPage { highlightKey:root.highlightKey } }
    Component { id:bar; TopBarSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:corePage; CoreSettings { highlightKey:root.highlightKey } }
    Component { id:displays; DisplaySettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:input; InputSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:keybinds; KeybindSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:connections; ConnectionsPage { active:root.active; highlightKey:root.highlightKey } }
    Component { id:audio; AudioSettings {} }
    Component { id:notifications; NotificationSettings { highlightKey:root.highlightKey } }
    Component { id:power; PowerSettings { highlightKey:root.highlightKey } }
    Component { id:time; TimeSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:notesPage; FieldNotesSettings { highlightKey:root.highlightKey } }
    Component { id:dictationPage; DictationSettings { highlightKey:root.highlightKey } }
    Component { id:system; SystemSettings {} }
    Component { id:about; AboutSettings {} }
    Component { id:animations; AnimationSettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:windows; WindowsSettings {} }
    Component { id:profiles; ProfileSettings {} }
    Component { id:privacy; PrivacySettings { active:root.active; highlightKey:root.highlightKey } }
    Component { id:security; SecuritySettings { highlightKey:root.highlightKey } }
    Component { id:advanced; AdvancedSettings {} }
}
