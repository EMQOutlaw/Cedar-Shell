pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "services"

Singleton {
    id: root
    property string panel: ""
    property string settingsAnchor: ""
    property string settingsPage: ""
    property string output: ""
    property bool locked: false
    property bool authTest: false
    property bool suspendAfterLock: false
    property string osdKind: ""
    property real osdValue: 0
    property string osdLabel: ""
    property string osdOutput: ""
    property bool osdOpen: false
    property bool osdLegacyInteracting: false
    property bool osdCoreInteracting: false
    property bool osdCoreDragging: false
    readonly property bool osdInteracting: osdLegacyInteracting || osdCoreInteracting || osdCoreDragging
    readonly property bool osdVisible: osdOpen && !locked
    onOsdInteractingChanged: {
        if (osdInteracting)
            osdTimer.stop();
        else if (osdOpen)
            osdTimer.restart();
    }
    onLockedChanged: if (locked) {
        osdOpen = false;
        osdTimer.stop();
    }
    property int greetingIndex: 0
    readonly property var greetings: ["Evenin'. CEDAR's lit.", "A little light from the deep woods.", "Set a spell. There's knowledge to keep.", "The ridge is quiet. The light stays on.", "Old wisdom. New trails."]
    readonly property string greeting: greetings[greetingIndex % greetings.length]
    function focusedOutput() {
        return Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
    }
    function preferredOutput() {
        return Quickshell.screens.find(s => s.name === Config.saved.mainDisplay)?.name || focusedOutput();
    }
    function toggle(name) {
        if (locked)
            return;
        if (name === "control" && Config.saved.canopyEnabled) {
            Canopy.toggleQuick();
            return;
        }
        if (name === "power" && Config.saved.canopyEnabled) {
            if (Canopy.shown && Canopy.topic === "power")
                Canopy.close();
            else
                Canopy.open("power");
            return;
        }
        const target = preferredOutput();
        panel = panel === name && output === target ? "" : name;
        output = target;
    }
    function open(name) {
        if (locked)
            return;
        if (name === "control" && Config.saved.canopyEnabled) {
            Canopy.open("quick");
            return;
        }
        if (name === "power" && Config.saved.canopyEnabled) {
            Canopy.open("power");
            return;
        }
        panel = name;
        output = preferredOutput();
    }
    function close() {
        panel = "";
    }
    function shows(name, screen) {
        return !locked && panel === name && output === screen?.name;
    }
    function osd(kind, value, label) {
        osdKind = kind;
        osdValue = value;
        osdLabel = label;
        if (!osdOpen)
            osdOutput = preferredOutput();
        osdOpen = true;
        if (!osdInteracting)
            osdTimer.restart();
    }
    function lock(suspend) {
        authTest = false;
        close();
        suspendAfterLock = suspend;
        locked = true;
    }
    Timer {
        id: osdTimer
        interval: Math.max(2000, Theme.osdDuration)
        onTriggered: root.osdOpen = false
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.greetingIndex++
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!Quickshell.screens.some(s => s.name === root.output))
                root.close();
            if (root.osdOpen && !Quickshell.screens.some(s => s.name === root.osdOutput))
                root.osdOutput = root.preferredOutput();
        }
    }
}
