import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// One reserved centre, two bounded rails. Optional text and tray items yield
// their space before any of the status controls do. The centre's Core lives
// in its own surface; this component never registers its topic anchors.
Item {
    id: root
    required property var output
    readonly property string outputName: output?.name || ""
    readonly property bool coreHost: CoreService.enabled && CoreService.hostName === outputName
    readonly property real centerWidth: coreHost ? CoreService.reserveWidth : Math.max(96, Math.ceil(centerClockMetrics.advanceWidth) + 20)
    readonly property real sideWidth: Math.max(0, (width - centerWidth) / 2 - 8)
    readonly property real controlHeight: Math.max(24, height)
    readonly property real railGap: sideWidth < 240 ? 1 : 2
    readonly property var monitor: Hyprland.monitorFor(output)
    property var workspaceModel: Hyprland.workspaces
    property var activeWorkspace: monitor?.activeWorkspace || null
    readonly property var localWorkspaces: (Array.isArray(workspaceModel) ? workspaceModel : (workspaceModel?.values || [])).filter(w => w.id > 0 && w.monitor?.name === outputName)
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryPresent: battery?.isPresent ?? false
    readonly property int batteryPercent: Math.round((battery?.percentage ?? 0) * 100)
    readonly property bool nerdIcons: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    readonly property bool networkShown: Config.moduleEnabled("network")
    readonly property bool audioShown: Config.moduleEnabled("audio")
    readonly property bool powerShown: Config.moduleEnabled("battery")
    readonly property bool clockShown: Config.moduleEnabled("clock")
    readonly property string calendarCompactText: nerdIcons ? "󰃭" : "Cal"
    readonly property string calendarDateText: Config.saved.barShowDate ? Config.formatDate(clock.date, true) : calendarCompactText
    readonly property bool notesShown: Config.stage >= 3 && Config.moduleEnabled("notes")
    readonly property bool dictationShown: Config.stage >= 3 && Dictation.installed && Config.moduleEnabled("dictation")
    readonly property int statusCount: 1 + Number(networkShown) + Number(audioShown) + Number(powerShown) + Number(clockShown) + Number(notesShown) + Number(dictationShown)
    readonly property real networkWidth: Network.vpnActive ? 46 : 32
    readonly property real compactClockWidth: Math.ceil(compactClockMetrics.advanceWidth) + 12
    readonly property real normalClockWidth: Math.ceil(normalClockMetrics.advanceWidth) + 14
    readonly property real fullClockWidth: Math.ceil(fullClockMetrics.advanceWidth) + 14
    readonly property real audioTextWidth: Math.max(26, Math.ceil(audioMetrics.advanceWidth) + 14)
    readonly property real powerTextWidth: Math.max(26, Math.ceil(powerMetrics.advanceWidth) + 14)
    readonly property real minimumStatusWidth: (networkShown ? networkWidth : 0) + (audioShown ? 26 : 0) + (powerShown ? 26 : 0)
        + (clockShown ? compactClockWidth : 0) + (notesShown ? 26 : 0) + (dictationShown ? 26 : 0) + 30 + railGap * (statusCount - 1)
    readonly property real statusLabelExtra: (audioShown ? audioTextWidth - 26 : 0) + (powerShown ? powerTextWidth - 26 : 0)
    // Measured text, rather than screen-width breakpoints, keeps enlarged fonts
    // inside the rail. The calendar yields to an icon while the time stays centered.
    readonly property bool statusLabels: sideWidth >= minimumStatusWidth + statusLabelExtra + 40
    readonly property real labeledStatusWidth: minimumStatusWidth + (statusLabels ? statusLabelExtra : 0)
    readonly property bool fullClock: clockShown && sideWidth >= labeledStatusWidth + fullClockWidth - compactClockWidth + 28
    readonly property bool normalClock: !fullClock && clockShown && sideWidth >= labeledStatusWidth + normalClockWidth - compactClockWidth + 12
    readonly property real clockWidth: fullClock ? fullClockWidth : normalClock ? normalClockWidth : compactClockWidth
    readonly property real statusWidth: labeledStatusWidth + (clockShown ? clockWidth - compactClockWidth : 0)
    readonly property real pulseWidth: 93 // CanopyPulse's sixteen 3px strokes, spaced by 3px.
    readonly property bool pulseShown: visible && Config.saved.barPulse && Motion.active && VisualQuality.effects && VisualQuality.decorative
        && !ShellState.locked && !!(Media.player && Media.player.isPlaying) && sideWidth - statusWidth >= pulseWidth + 8
    readonly property real pulseReservation: pulseShown ? pulseWidth + railGap : 0
    readonly property var activeTrayItems: SystemTray.items.values.filter(item => item.status !== Status.Passive)
    readonly property int trayCapacity: Config.moduleEnabled("tray") && statusLabels
        ? Math.max(0, Math.floor((sideWidth - statusWidth - pulseReservation - 8) / 26)) : 0
    readonly property var visibleTrayItems: activeTrayItems.slice(0, trayCapacity)
    readonly property real identityWidth: Config.moduleEnabled("identity") ? Math.ceil(identityMetrics.advanceWidth) + 14 : 0
    readonly property real launcherWidth: Config.stage >= 3 && Config.moduleEnabled("go") ? 28 : 0
    readonly property bool workspacesShown: Config.moduleEnabled("workspaces")
    readonly property bool overviewShown: Config.stage >= 3 && Config.saved.canopyEnabled
    readonly property real workspaceCell: Math.max(28, Math.ceil(workspaceMetrics.advanceWidth) + 10)
    readonly property real workspaceBudget: Math.max(0, sideWidth - identityWidth - launcherWidth - 12)
    readonly property real fullWorkspaceWidth: localWorkspaces.length * workspaceCell + (overviewShown ? 28 : 0) + 8
    readonly property bool compactWorkspaces: sideWidth < 280 || fullWorkspaceWidth > workspaceBudget
    readonly property var shownWorkspaces: compactWorkspaces
        ? localWorkspaces.filter(w => w.id === activeWorkspace?.id).slice(0, 1) : localWorkspaces
    readonly property real workspaceWidth: workspacesShown ? shownWorkspaces.length * workspaceCell + (overviewShown ? 28 : 0) + 8 : 0
    readonly property real occupiedLeftWidth: identityWidth + launcherWidth + workspaceWidth
        + 4 * Math.max(0, Number(identityWidth > 0) + Number(launcherWidth > 0) + Number(workspaceWidth > 0) - 1)
    readonly property bool titleShown: (Config.moduleEnabled("activeWindow") || Config.saved.barWhispers)
        && !compactWorkspaces && sideWidth - occupiedLeftWidth >= 92
    readonly property string activeTitle: Config.moduleEnabled("activeWindow") && Hyprland.focusedMonitor?.name === outputName
        ? (Hyprland.activeToplevel?.title || "") : ""

    function selected(topic) {
        return Canopy.shown && Canopy.topic === topic && Canopy.outputName === outputName && !Canopy.peeking;
    }
    function openTopic(topic, fallback) {
        if (ShellState.locked) return;
        if (Config.saved.canopyEnabled) Canopy.toggleTopic(topic, outputName);
        else if (fallback) ShellState.toggle(fallback);
    }
    function openAudio() {
        if (ShellState.locked) return;
        if (Config.saved.canopyEnabled) openTopic("audio", "");
        else { ShellState.settingsPage = "audio"; ShellState.open("settings"); }
    }
    function openCalendar() {
        if (ShellState.locked) return;
        if (Config.saved.canopyEnabled) openTopic("calendar", "");
        else { ShellState.settingsPage = "time"; ShellState.open("settings"); }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    TextMetrics { id: centerClockMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small + 1; text: Config.formatTime(clock.date) }
    TextMetrics { id: compactClockMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: root.calendarCompactText }
    TextMetrics { id: normalClockMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: root.calendarDateText }
    TextMetrics { id: fullClockMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: root.calendarDateText }
    TextMetrics { id: audioMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: Audio.label }
    TextMetrics { id: powerMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: root.batteryPresent ? root.batteryPercent + "%" : root.nerdIcons ? "⏻" : "P" }
    TextMetrics { id: identityMetrics; font.family: Theme.labelFont; font.pixelSize: Theme.small; font.letterSpacing: 2; text: "CEDAR" }
    TextMetrics { id: workspaceMetrics; font.family: Theme.dataFont; font.pixelSize: Theme.small; text: "00" }

    Text {
        objectName: "barCoreControls"
        visible: !root.coreHost
        anchors.centerIn: parent
        width: root.centerWidth
        text: root.clockShown ? Config.formatTime(clock.date) : "◈"
        color: Theme.strataText
        font.family: Theme.dataFont
        font.pixelSize: Theme.small + 1
        horizontalAlignment: Text.AlignHCenter
        Accessible.name: root.clockShown ? "Time " + text : ""
    }

    Item {
        id: leftControls
        objectName: "barLeftControls"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.sideWidth
        height: parent.height
        Row {
            id: leftRail
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            BarButton {
                objectName: "strataIdentity"
                visible: root.identityWidth > 0
                width: root.identityWidth
                height: root.controlHeight
                text: "CEDAR"
                fontFamily: Theme.labelFont
                fontSize: Theme.small
                letterSpacing: 2
                accent: Theme.strataAccent
                // The mark opens the Understory, the rail that grows from this end
                // of the bar; Field Station keeps its place behind the rail's Heartwood.
                hint: Config.stage >= 3 ? "Understory" : "Field Station"
                enabled: Config.stage >= 2 && !ShellState.locked
                anchorsCanopy: false
                checked: Understory.shown && Understory.outputName === root.outputName
                onClicked: {
                    if (Config.stage >= 3) Understory.toggle(root.outputName);
                    else root.openTopic("station", "hud");
                }
            }
            BarButton {
                objectName: "strataLauncher"
                visible: root.launcherWidth > 0
                width: root.launcherWidth
                height: root.controlHeight
                text: root.nerdIcons ? "󰀻" : "⊞"
                iconOnly: true
                quiet: true
                accent: Theme.strataAccent
                hint: "Applications"
                enabled: !ShellState.locked
                anchorTopic: "go"
                canopyOutput: root.outputName
                checked: root.selected("go")
                onClicked: {
                    if (Config.saved.canopyEnabled) Canopy.toggleTopic("go", root.outputName);
                    else Go.toggle("root");
                }
            }
            Item {
                id: workspaceRail
                objectName: "strataWorkspaces"
                visible: root.workspacesShown
                width: root.workspaceWidth
                height: root.controlHeight
                property real markX: 0
                property real markWidth: root.workspaceCell - 10
                property bool markVisible: false
                function placeMark() {
                    let found = false;
                    for (let i = 0; i < workspaceRepeater.count; ++i) {
                        const button = workspaceRepeater.itemAt(i);
                        if (button && button.checked) {
                            markX = 4 + button.x + 5;
                            found = true;
                            break;
                        }
                    }
                    markVisible = found;
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Qt.alpha(Theme.strataSurface, .65)
                    border.width: 1
                    border.color: Qt.alpha(Theme.strataGrain, .52)
                }
                Row {
                    x: 4
                    height: parent.height
                    Repeater {
                        id: workspaceRepeater
                        model: root.shownWorkspaces
                        onCountChanged: Qt.callLater(workspaceRail.placeMark)
                        BarButton {
                            id: workspaceButton
                            required property var modelData
                            width: root.workspaceCell
                            height: root.controlHeight
                            text: /^\d+$/.test(modelData.name) ? modelData.name.padStart(2, "0") : modelData.name
                            hint: "Workspace " + modelData.name
                            quiet: true
                            glide: true
                            enabled: !ShellState.locked
                            accent: modelData.urgent ? Theme.warning : Theme.strataAccent
                            checked: root.activeWorkspace?.id === modelData.id
                            onClicked: modelData.activate()
                            onCheckedChanged: Qt.callLater(workspaceRail.placeMark)
                            onXChanged: Qt.callLater(workspaceRail.placeMark)
                            Component.onCompleted: Qt.callLater(workspaceRail.placeMark)
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 10
                                width: 1
                                color: Qt.alpha(Theme.strataGrain, .5)
                            }
                        }
                    }
                    BarButton {
                        objectName: "strataWorkspaceOverview"
                        visible: root.overviewShown
                        width: 28
                        height: root.controlHeight
                        text: "▣"
                        iconOnly: true
                        quiet: true
                        enabled: !ShellState.locked
                        hint: "Workspace overview"
                        accent: Theme.strataAccent
                        anchorTopic: "workspaces"
                        canopyOutput: root.outputName
                        checked: root.selected("workspaces")
                        onClicked: Canopy.toggleTopic("workspaces", root.outputName)
                    }
                }
                Rectangle {
                    visible: workspaceRail.markVisible
                    x: workspaceRail.markX
                    y: parent.height - 3
                    width: workspaceRail.markWidth
                    height: 2
                    color: Theme.strataAccent
                    Behavior on x {
                        enabled: VisualQuality.functionalMotion
                        NumberAnimation { duration: VisualQuality.ms(Theme.expand); easing.type: Easing.OutCubic }
                    }
                }
            }
        }
        Item {
            objectName: "strataWindowTitle"
            visible: root.titleShown
            clip: true
            x: leftRail.width + 12
            width: Math.max(0, parent.width - x)
            height: root.controlHeight
            anchors.verticalCenter: parent.verticalCenter
            Loader {
                id: whispersLoader
                objectName: "strataWhispers"
                anchors.fill: parent
                active: root.visible && root.titleShown && Config.saved.barWhispers && Motion.active && !ShellState.locked
                sourceComponent: CedarWhispers {
                    windowTitle: root.activeTitle
                    fontSize: Theme.small
                    color: Theme.strataMuted
                }
            }
            Text {
                visible: !whispersLoader.active
                anchors.fill: parent
                text: root.activeTitle
                textFormat: Text.PlainText
                font.family: Theme.labelFont
                font.pixelSize: Theme.small
                color: Theme.strataMuted
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                Accessible.name: text
            }
        }
    }

    Item {
        id: rightControls
        objectName: "barRightControls"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.sideWidth
        height: parent.height
        Row {
            id: statusRail
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.railGap
            Loader {
                id: pulseLoader
                objectName: "strataPulse"
                visible: active
                active: root.pulseShown
                width: active ? root.pulseWidth : 0
                height: root.controlHeight
                sourceComponent: Item {
                    CanopyPulse {
                        anchors.centerIn: parent
                        width: root.pulseWidth
                        height: Math.min(22, parent.height)
                        active: pulseLoader.active
                        tone: Theme.strataAccent
                    }
                }
            }
            Row {
                id: trayRow
                visible: root.visibleTrayItems.length > 0
                spacing: 2
                Repeater {
                    model: root.visibleTrayItems
                    BarButton {
                        id: trayButton
                        required property var modelData
                        width: 24
                        height: root.controlHeight
                        hint: modelData.title || modelData.id || "Tray application"
                        enabled: !ShellState.locked
                        onClicked: {
                            if (modelData.onlyMenu && modelData.hasMenu) trayMenu.open();
                            else modelData.activate();
                        }
                        Keys.onMenuPressed: if (modelData.hasMenu) trayMenu.open()
                        contentItem: Image {
                            source: Config.imageSource(trayButton.modelData.icon)
                            sourceSize.width: 18
                            sourceSize.height: 18
                            fillMode: Image.PreserveAspectFit
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton | Qt.MiddleButton
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton) trayButton.modelData.secondaryActivate();
                                else if (trayButton.modelData.hasMenu) trayMenu.open();
                            }
                            onWheel: event => trayButton.modelData.scroll(event.angleDelta.y, false)
                        }
                        QsMenuAnchor {
                            id: trayMenu
                            menu: trayButton.modelData.menu
                            anchor.item: trayButton
                            anchor.edges: Edges.Bottom
                            anchor.gravity: Edges.Bottom
                        }
                    }
                }
            }
            NetworkIndicator {
                objectName: "strataNetwork"
                visible: root.networkShown
                width: root.networkWidth
                height: root.controlHeight
                outputName: root.outputName
                inline: false
                // Notices remain in the tooltip; an unbounded notice must not
                // cover the neighbouring volume control or the reserved Core.
                clip: true
                checked: root.selected("network")
            }
            BarButton {
                objectName: "strataAudio"
                visible: root.audioShown
                width: root.statusLabels ? root.audioTextWidth : 26
                height: root.controlHeight
                text: root.statusLabels ? Audio.label : root.nerdIcons ? (Audio.muted ? "󰝟" : "󰕾") : (Audio.muted ? "×♪" : "♪")
                iconOnly: !root.statusLabels
                quiet: true
                enabled: !ShellState.locked
                hint: "Audio · " + Audio.label + " · Scroll to change volume"
                accent: Theme.strataAccent
                anchorTopic: "audio"
                canopyOutput: root.outputName
                checked: root.selected("audio")
                onClicked: root.openAudio()
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        if (ShellState.locked) return;
                        Audio.change(event.angleDelta.y > 0 ? 5 : event.angleDelta.y < 0 ? -5 : 0);
                        event.accepted = true;
                    }
                }
            }
            BarButton {
                objectName: "strataPower"
                visible: root.powerShown
                width: root.statusLabels ? root.powerTextWidth : 26
                height: root.controlHeight
                text: root.statusLabels && root.batteryPresent ? root.batteryPercent + "%"
                    : root.nerdIcons ? (root.batteryPresent ? (UPower.onBattery ? "󰁹" : "󰂄") : "⏻") : "P"
                iconOnly: !root.statusLabels || !root.batteryPresent
                quiet: !(root.batteryPresent && UPower.onBattery && root.batteryPercent <= 20)
                enabled: !ShellState.locked
                hint: (root.batteryPresent ? "Battery " + root.batteryPercent + "% · " + (UPower.onBattery ? "On battery" : "External power") + " · " : "") + "Power and session controls"
                accent: root.batteryPresent && UPower.onBattery && root.batteryPercent <= 20 ? Theme.warning : Theme.strataAccent
                anchorTopic: "power"
                canopyOutput: root.outputName
                checked: root.selected("power")
                onClicked: root.openTopic("power", "power")
            }
            BarButton {
                objectName: "strataClock"
                visible: root.clockShown
                width: root.clockWidth
                height: root.controlHeight
                text: root.fullClock || root.normalClock ? root.calendarDateText : root.calendarCompactText
                hint: Config.formatDate(clock.date) + " · " + Config.formatTime(clock.date) + " · Calendar"
                enabled: !ShellState.locked
                accent: Theme.strataAccent
                anchorTopic: "calendar"
                canopyOutput: root.outputName
                checked: root.selected("calendar")
                onClicked: root.openCalendar()
            }
            // Field Notes: the floating sheet opens on this bar's display; a
            // right-click goes to its Settings page without closing the notes.
            BarButton {
                objectName: "strataNotes"
                visible: root.notesShown
                width: 26
                height: root.controlHeight
                text: root.nerdIcons ? "󰈙" : "N"
                iconOnly: true
                quiet: true
                enabled: !ShellState.locked
                hint: "Field Notes · Right-click for its settings"
                accent: Theme.strataAccent
                anchorsCanopy: false
                checked: FieldNotes.opened && FieldNotes.screenName === root.outputName
                onClicked: FieldNotes.summon({ toggle: true, screen: root.outputName })
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: FieldNotes.openSettings()
                }
            }
            // Dictation: Voxtype's microphone. Ember while it listens, amber while
            // it transcribes; a click toggles, a right-click opens Settings › Dictation.
            BarButton {
                objectName: "strataDictation"
                visible: root.dictationShown
                width: 26
                height: root.controlHeight
                text: root.nerdIcons ? (Dictation.transcribing ? "󰔟" : "󰍬") : (Dictation.transcribing ? "…" : "M")
                iconOnly: true
                quiet: !Dictation.active
                enabled: !ShellState.locked && Dictation.available
                hint: "Dictation · " + Dictation.label + " · Super+Ctrl+X toggles, hold F9 to talk"
                accent: Dictation.recording ? Theme.ember : Dictation.transcribing ? Theme.amber : Theme.strataAccent
                anchorsCanopy: false
                checked: Dictation.active
                onClicked: Dictation.toggle()
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: Dictation.openSettings()
                }
            }
            // No bell: notifications unfold from the Core pill and gather in Signals.
            BarButton {
                id: quickButton
                objectName: "strataQuick"
                width: 30
                height: root.controlHeight
                text: root.nerdIcons ? "󰒓" : "☷"
                iconOnly: true
                enabled: !ShellState.locked
                hint: "Quick Controls"
                accent: Theme.strataAccent
                anchorTopic: "quick"
                canopyOutput: root.outputName
                checked: root.selected("quick")
                onClicked: Canopy.toggleQuick(root.outputName)
                background: Rectangle {
                    radius: 2
                    color: Qt.alpha(Theme.strataAccent, quickButton.down ? .18 : quickButton.checked ? .13 : quickButton.hovered ? .09 : .04)
                    border.width: quickButton.visualFocus ? Theme.focusWidth : 1
                    border.color: Qt.alpha(Theme.strataAccent, quickButton.visualFocus ? 1 : quickButton.checked ? .75 : .35)
                }
            }
        }
    }
}
