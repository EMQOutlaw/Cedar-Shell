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
    property string settingsSection: "overview"
    property string output: ""
    property bool locked: false
    property bool lockSecure: false
    property bool nativeLockReady: false
    property int securedUnlocks: 0
    // Successful local PAM checks that did not involve a session lock.
    property int authTests: 0
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
    // Whoever locks (lock(), the lock screen, an external session), every
    // surface is released here, so nothing waits behind the lock to reopen.
    onLockedChanged: if (locked) {
        close();
        osdOpen = false;
        osdTimer.stop();
    }
    property int greetingIndex: 0
    property real greetingAt: 0
    // Every visible Field Station ticks this; the index moves once a minute
    // however many stations are on screen.
    function rotateGreeting() {
        const now = Date.now();
        if (now - greetingAt < 55000) return;
        greetingAt = now;
        greetingIndex++;
    }
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
        // Settings is a window owned by its service; the requested page travels with the call.
        if (name === "settings") {
            SettingsService.route(settingsPage, settingsAnchor, true);
            settingsPage = ""; settingsAnchor = "";
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
        if (name === "settings") {
            SettingsService.route(settingsPage, settingsAnchor, false);
            settingsPage = ""; settingsAnchor = "";
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
    // One interactive surface at a time. `panel` names the bar-grown surfaces
    // (core hub, canopy, understory, the legacy hud/power/themes/... panels);
    // Settings is a window owned by its service but joins the same policy, so
    // opening either side dismisses the other. The resting Core pill is not a
    // surface here: it may stay while any of these shows.
    function surfaceOwner() {
        if (locked) return "";
        if (panel !== "") return panel;
        if (SettingsService.windowOpen) return "settings";
        return "";
    }
    onPanelChanged: if (panel !== "" && SettingsService.windowOpen) SettingsService.closeApp()
    // SettingsService watches ShellState too; attach once construction has
    // settled (next event-loop turn) so the two singletons never instantiate
    // each other mid-construction — that cycle left other singletons, e.g.
    // Understory, unresolved on a named output. Nothing can open Settings
    // before the loop runs, so no transition is missed.
    Connections {
        id: settingsWatch
        target: null
        function onWindowOpenChanged() {
            if (SettingsService.windowOpen && root.panel !== "")
                root.close();
        }
    }
    Component.onCompleted: Qt.callLater(() => { settingsWatch.target = SettingsService; })
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
        if (Config.externalSession) {
            locked = true;
            const helper = Quickshell.env("CEDAR_SESSION_HELPER");
            if (helper && helper.startsWith("/"))
                Quickshell.execDetached(["python3", helper, "lock", ...(suspend ? ["--suspend"] : [])]);
            return;
        }
        suspendAfterLock = suspend;
        locked = true;
    }
    Timer {
        id: osdTimer
        interval: Math.max(2000, Theme.osdDuration)
        onTriggered: root.osdOpen = false
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
