pragma Singleton
import QtQuick
import Quickshell
import ".."

Singleton {
    id: root
    readonly property var topics: ["quick", "audio", "network", "bluetooth", "power", "system", "weather", "calendar", "clipboard", "notifications", "trails", "station"]
    // One route per destination: a topic with a visible bar button gets no tab.
    // The bar's center control always opens Quick Controls.
    function barRoute(value) {
        return value === "quick" || (value === "network" && Config.moduleEnabled("network")) || (value === "notifications" && Config.stage >= 3 && Config.moduleEnabled("notifications")) || (value === "station" && Config.stage >= 2 && Config.moduleEnabled("identity"));
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
    // Entrance clock for whichever panel is showing: 0→1 over about a second,
    // started by the drop when content begins to show. Panels stagger their
    // instruments through ease(start, span). Reduced Motion and tests snap.
    property real reveal: 1
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    function enter() {
        entrance.stop();
        if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; }
        reveal = 0;
        entrance.start();
    }
    property NumberAnimation entrance: NumberAnimation { target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    property Connections motionGuard: Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { root.entrance.stop(); root.reveal = 1; } } }
    property bool pinned: false
    property bool peeking: false
    property string outputName: ""
    // Bar controls register a provider returning the screen x of their centre,
    // keyed by topic and output. The open panel descends from that point when
    // one exists, otherwise from the screen centre under the Core pill.
    property var anchorProviders: ({})
    function setAnchorProvider(value, output, provider) {
        const next = Object.assign({}, anchorProviders);
        next[value + "@" + output] = provider;
        anchorProviders = next;
    }
    // Only the registered provider may clear its key: bar layouts instantiate
    // the same control more than once and hide the spares.
    function clearAnchorProvider(value, output, provider) {
        const key = value + "@" + output;
        if (anchorProviders[key] !== provider)
            return;
        const next = Object.assign({}, anchorProviders);
        delete next[key];
        anchorProviders = next;
    }
    // A panel descending from its own bar control is its own thing: no topic
    // tabs, no Quick Controls footer, and the Core pill does not react to it.
    // Decided by topic, not by the anchor lookup: the pill's width depends on
    // this, and the pill's own anchor provider reads that width.
    readonly property bool standalone: shown && topic !== "quick" && barRoute(topic)
    // The registered control's screen rect {x, width} for the shown topic, or null.
    readonly property var anchorRect: {
        const provider = shown ? anchorProviders[topic + "@" + (screen?.name || "")] : null;
        const r = provider ? provider() : null;
        return r && Number.isFinite(r.x) && Number.isFinite(r.width) && r.width > 0 ? r : null;
    }
    readonly property real anchorX: anchorRect ? anchorRect.x + anchorRect.width / 2 : -1
    readonly property var screen: Quickshell.screens.find(s => s.name === outputName) || CoreService.hostScreen
    readonly property bool shown: Config.saved.canopyEnabled && !ShellState.locked && (ShellState.panel === "canopy" || pinned)
    function titleFor(value) {
        return ({
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
            trails: "Recent Trail",
            station: "Field Station"
        })[value] || "Canopy";
    }
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
            trails: "Recent Trail",
            station: "Field Station"
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
    // Open a control's topic, or close it when that topic is already open.
    function toggleTopic(value, output = "") {
        if (shown && topic === value && !peeking)
            close();
        else
            open(value, output);
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
