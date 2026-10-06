pragma Singleton
import QtQuick
import Quickshell
import ".."

Singleton {
    id: root
    readonly property var topics: ["quick", "audio", "network", "bluetooth", "power", "system", "weather", "calendar", "clipboard", "notifications", "trails"]
    // One route per destination: a topic with a visible bar button gets no tab.
    // The bar's center control always opens Quick Controls.
    function barRoute(value) {
        return value === "quick" || (value === "network" && Config.moduleEnabled("network")) || (value === "notifications" && Config.stage >= 3 && Config.moduleEnabled("notifications"));
    }
    readonly property var tabs: topics.filter(t => !barRoute(t))
    // Include the originating controls in the compositor grab. Otherwise an
    // outside-click dismissal can run before Core's click and reopen the panel.
    property var controlWindows: []
    function registerControls(window) {
        if (!controlWindows.includes(window))
            controlWindows = controlWindows.concat([window]);
    }
    function unregisterControls(window) {
        controlWindows = controlWindows.filter(w => w !== window);
    }
    property string topic: "quick"
    property bool pinned: false
    property bool peeking: false
    property string outputName: ""
    readonly property var screen: Quickshell.screens.find(s => s.name === outputName) || CoreService.hostScreen
    readonly property bool shown: Config.saved.canopyEnabled && !ShellState.locked && (ShellState.panel === "canopy" || pinned)
    readonly property string title: ({
            audio: "Audio",
            network: "Connections",
            bluetooth: "Bluetooth",
            power: "Power & Session",
            system: "System",
            weather: "Sky Watch",
            calendar: "Time & Calendar",
            clipboard: "Clipboard",
            notifications: "Notifications",
            quick: "Quick Controls",
            trails: "Recent Trail"
        })[topic] || "Canopy"
    function open(value, output = "", peek = false) {
        if (!topics.includes(value) || ShellState.locked || !Config.saved.canopyEnabled)
            return;
        if (peek && (pinned || (ShellState.panel !== "" && !peeking)))
            return;
        peeking = peek;
        topic = value;
        outputName = output || CoreService.hostName;
        ShellState.panel = "canopy";
        ShellState.output = screen?.name || "";
        if (!peek)
            Forest.record("canopy", title, value);
    }
    function toggleQuick(output = "") {
        if (ShellState.locked)
            return;
        if (!Config.saved.canopyEnabled) {
            ShellState.toggle("control");
            return;
        }
        if (shown && topic === "quick" && !peeking)
            close();
        else {
            CoreService.collapse();
            open("quick", output);
        }
    }
    // Compatibility for existing callers: the general control destination is stable.
    function context() {
        toggleQuick();
    }
    function close() {
        pinned = false;
        peeking = false;
        if (ShellState.panel === "canopy")
            ShellState.close();
    }
    function leavePeek() {
        if (peeking)
            leave.restart();
    }
    function holdPeek() {
        leave.stop();
    }
    function pin() {
        if (ShellState.locked)
            return;
        peeking = false;
        pinned = !pinned;
    }
    Timer {
        id: leave
        interval: 400
        onTriggered: if (root.peeking)
            root.close()
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked)
                root.close();
        }
    }
    Connections {
        target: Config.saved
        function onCanopyEnabledChanged() {
            if (!Config.saved.canopyEnabled)
                root.close();
        }
    }
}
