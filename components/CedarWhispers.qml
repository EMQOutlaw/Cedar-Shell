import QtQuick
import ".."
import "../services"

// The bar's text region as Whispers: the active window's title by default,
// a contextual line as things happen (a Desktop Profile changing, Focus
// starting, pausing or ending, Shield's posture moving, a Forest whisper),
// and a curated line when no window has a title. Lines resolve in and out;
// nothing scrolls, and a quote changes only every ninety seconds while the
// user is present. A signal asking for attention on the Core pill takes
// priority: contextual lines then stay quiet.
Item {
    id: root
    property string windowTitle: ""
    property real fontSize: Theme.small
    property color color: Theme.muted
    readonly property bool enabled: Config.saved.barWhispers
    readonly property var quotes: [
        "A cold, living light in the dark woods.",
        "The woods are quiet.",
        "The light stays on.",
        "Keeping watch.",
        "Rooted in faith. Built with care.",
        "He shall grow like a cedar in Lebanon.",
        "Signals through the trees.",
        "The forest settles."
    ]
    property int quoteIndex: 0
    property string message: ""
    property double messageUntil: 0
    readonly property bool messaging: message !== "" && messageUntil > now
    property double now: Date.now()
    // A signal asking for attention at high or critical priority keeps Whispers quiet; an ordinary one (a volume change, a power profile) does not.
    readonly property bool busy: !!CoreService.foreground && (CoreService.foreground.sticky || (CoreService.foreground.priority >= 2 && CoreService.foreground.attentionUntil > CoreService.model.now))
    readonly property string shown: enabled && messaging ? message : windowTitle !== "" ? windowTitle : enabled ? quotes[quoteIndex % quotes.length] : "A cold, living light in the dark woods."
    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth

    function whisper(text, ms) {
        if (!enabled || !text || busy) return;
        now = Date.now(); message = text; messageUntil = now + (ms || 7000);
        clear.interval = ms || 7000; clear.restart();
    }
    Timer { id: clear; onTriggered: { root.now = Date.now(); root.message = ""; } }
    // Quotes turn only while there is no title to show and the user is present.
    Timer { interval: 90000; repeat: true; running: root.enabled && root.windowTitle === "" && Motion.active && !root.messaging; onTriggered: root.quoteIndex++ }

    KineticLabel {
        id: label
        anchors.fill: parent
        text: root.shown
        transitionStyle: root.messaging ? "reveal" : "fade"
        duration: root.messaging ? Theme.morphGrow : Theme.transition
        minimumInterval: 350
        elide: Text.ElideRight
        color: root.messaging ? Theme.teal : root.color
        font.pixelSize: root.fontSize
        font.letterSpacing: root.messaging ? 1.2 : 0
    }

    Connections { target: Profiles; function onCurrentChanged() { root.whisper(Profiles.current ? Profiles.currentLabel.toUpperCase() + " PROFILE · " + Profiles.managed(Profiles.current).map(m => Profiles.ops[m.key].hud.toUpperCase()).slice(0, 3).join(", ") : "PROFILE OFF · DESKTOP AS YOU LEFT IT"); } }
    Connections {
        target: Focus
        function onActiveChanged() { root.whisper(Focus.active ? "FOCUS · " + Focus.minutes(Focus.planned).toUpperCase() : Focus.lastSession ? "FOCUS ENDED · " + Focus.minutes(Focus.lastSession.actual).toUpperCase() + " · " + Focus.lastSession.held + " HELD" : "FOCUS ENDED"); }
        function onPausedChanged() { if (Focus.active) root.whisper(Focus.paused ? "FOCUS PAUSED" : "FOCUS RESUMED · " + Focus.minutes(Focus.remaining).toUpperCase() + " LEFT"); }
    }
    Connections { target: Shield; function onPostureChanged() { if (Shield.ready) root.whisper("SHIELD · " + Shield.headline.toUpperCase()); } }
    Connections { target: Gaming; function onActiveChanged() { if (!Gaming.busy || Gaming.active) root.whisper(Gaming.active ? "GAMING MODE · THE DESKTOP STEPS ASIDE" : "GAMING MODE ENDED · DESKTOP RESTORED"); } }
    Connections { target: Forest; function onWhisperChanged() { if (Forest.whisper) root.whisper(Forest.whisper.toUpperCase(), 6000); } }
    Accessible.role: Accessible.StaticText
    Accessible.name: shown
}
