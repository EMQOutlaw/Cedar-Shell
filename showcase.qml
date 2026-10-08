import QtQuick
import QtQuick.Layouts
import Quickshell
import "."
import "components"
import "services"

// Development showcase for the bar's animation identity. Run it beside the
// shell with `qs -p showcase.qml` (never as a profile). It instantiates the
// production components themselves and triggers their real transitions;
// the only synthetic input is the labelled test signal for Canopy Pulse.
ShellRoot {
    FloatingWindow {
        id: win
        title: "CEDAR Showcase"
        visible: true
        implicitWidth: 1180
        implicitHeight: 860
        color: Theme.background
        property string kineticWord: "BALANCED"
        property string revealLine: "THE FOREST IS STILL"
        property string statusWord: "CONNECTING"
        property int number: 41
        property bool synthetic: false
        // Keyboard drive, so the showcase can be exercised without a pointer:
        // H pulse · G gaming · F focus · W warning · U unfold · I idle
        // T trace · P profile pulse · S shield signal · O open · R retarget · C close
        // A awaken · E ripple · D grow · L flow on/off · V reveal line
        // K word · N status · M number · 1/2/3 whispers · Q quote · X synthetic
        Item {
            anchors.fill: parent; focus: true
            Keys.onPressed: event => {
                const k = String.fromCharCode(event.key).toUpperCase();
                if (k === "H") heart.pulse(); else if (k === "G") heart.mode = "gaming"; else if (k === "F") heart.mode = "focus"; else if (k === "I") { heart.mode = "idle"; heart.warning = false; }
                else if (k === "W") heart.warning = !heart.warning; else if (k === "U") heart.separateOnce(); else if (k === "A") heart.awaken(); else if (k === "E") heart.ripple();
                else if (k === "T") roots.trace(8, roots.width / 2); else if (k === "P") roots.pulse("centre", Theme.teal); else if (k === "S") roots.signalTo(roots.width / 2, Theme.amber); else if (k === "D") roots.grow(); else if (k === "L") { roots.flowTo = roots.width / 2; roots.flowing = !roots.flowing; }
                else if (k === "O") { frame.lit = false; frame.lit = true; frame.x = 60; frame.width = 420; frame.height = 280; } else if (k === "R") { frame.lit = false; frame.lit = true; frame.x = 160; frame.width = 560; frame.height = 220; } else if (k === "C") { frame.lit = false; frame.height = 0; }
                else if (k === "K") win.kineticWord = win.kineticWord === "GAMING" ? "BALANCED" : "GAMING"; else if (k === "V") win.revealLine = win.revealLine === "THE FOREST IS STILL" ? "LIGHT RUNS ALONG THE ROOT" : "THE FOREST IS STILL"; else if (k === "N") win.statusWord = win.statusWord === "CONNECTED" ? "CONNECTING" : "CONNECTED"; else if (k === "M") win.number++;
                else if (k === "1") whispers.whisper("WORK PROFILE · NOTIFICATIONS, VISUAL QUALITY, BACKGROUND ACTIVITY"); else if (k === "2") whispers.whisper("FOCUS · 25 MIN"); else if (k === "3") whispers.whisper("SHIELD · ATTENTION REQUIRED"); else if (k === "Q") whispers.quoteIndex++;
                else if (k === "X") { win.synthetic = !win.synthetic; if (!win.synthetic) { Pulse.levels = []; Pulse.energy = 0; } }
                else return;
                event.accepted = true;
            }
        }
        // A labelled synthetic signal for the Pulse strip: a slow sine over the bands.
        Timer {
            interval: 33; repeat: true; running: win.synthetic
            property real t: 0
            onTriggered: { t += .09; const rows = []; for (let i = 0; i < 24; i++) rows.push(Math.max(0, Math.min(1, .5 + .5 * Math.sin(t + i * .5)))); Pulse.levels = rows; Pulse.energy = .5; Pulse.available = true; }
        }
        Flickable {
            anchors.fill: parent; contentWidth: width; contentHeight: column.implicitHeight + 48; clip: true
            ColumnLayout {
                id: column
                x: 24; y: 24; width: parent.width - 48; spacing: 18
                GlowText { text: "CEDAR SHOWCASE · PRODUCTION COMPONENTS, REAL TRANSITIONS"; font.pixelSize: 11; font.letterSpacing: 2; color: Theme.teal }
                GlowText { text: "Preset: " + Config.saved.motionPreset + " · intensity " + Math.round(Config.saved.effectIntensity * 100) + "% · reduced motion " + (Theme.reducedMotion ? "on" : "off"); font.pixelSize: Theme.small; color: Theme.muted }

                // Heartwood
                RowLayout {
                    Layout.fillWidth: true; spacing: 24
                    CedarHeartwood { id: heart; size: 120; intensity: VisualQuality.effectIntensity; hovered: heartHover.hovered
                        HoverHandler { id: heartHover } TapHandler { onTapped: heart.pulse() } }
                    ColumnLayout { spacing: 8
                        SectionMark { text: "HEARTWOOD" }
                        GlowText { text: "Hover turns the middle ring; click runs the light. Buttons set the real states."; font.pixelSize: Theme.small; color: Theme.muted }
                        Flow { spacing: 6; Layout.fillWidth: true
                            StationButton { text: "Idle"; checked: heart.mode === "idle"; onClicked: { heart.mode = "idle"; heart.warning = false; } }
                            StationButton { text: "Gaming (one turn, lock)"; checked: heart.mode === "gaming"; onClicked: heart.mode = "gaming" }
                            StationButton { text: "Focus (contract)"; checked: heart.mode === "focus"; onClicked: heart.mode = "focus" }
                            StationButton { text: "Shield warning"; checked: heart.warning; onClicked: heart.warning = !heart.warning }
                            StationButton { text: "Panel unfolding"; onClicked: heart.separateOnce() }
                            StationButton { text: "Pulse (bloom)"; onClicked: heart.pulse() }
                            StationButton { text: "Ripple (signal)"; onClicked: heart.ripple() }
                            StationButton { text: "Awaken"; onClicked: heart.awaken() } } }
                }
                // Rootlines on a bar-like strip
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    SectionMark { text: "ROOTLINES" }
                    Item {
                        Layout.fillWidth: true; implicitHeight: 44
                        HudPanel { anchors.fill: parent; fillColor: Qt.alpha(Theme.background, .94); padding: 0 }
                        CedarRootlines { id: roots; anchors.fill: parent; anchors.margins: 6 }
                    }
                    Flow { spacing: 6; Layout.fillWidth: true
                        StationButton { text: "Trace left → centre"; onClicked: roots.trace(8, roots.width / 2) }
                        StationButton { text: "Trace right → bell"; onClicked: roots.trace(roots.width - 8, roots.width - 120) }
                        StationButton { text: "Profile pulse (centre)"; onClicked: roots.pulse("centre", Theme.teal) }
                        StationButton { text: "Focus pulse (centre)"; onClicked: roots.pulse("centre", Theme.green) }
                        StationButton { text: "Shield signal → pill"; onClicked: roots.signalTo(roots.width / 2, Theme.amber) }
                        StationButton { text: "Grow (awaken)"; onClicked: roots.grow() }
                        StationButton { text: roots.flowing ? "Stop flow" : "Flow → centre (panel open)"; checked: roots.flowing; onClicked: { roots.flowTo = roots.width / 2; roots.flowing = !roots.flowing; } } }
                }
                // Strata frame
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    SectionMark { text: "STRATA · DROP FRAME" }
                    GlowText { text: "Open grows the frame from the bar line; the Grain follows a beat later and the Living Edge runs the contour once. Retarget morphs in place. Close contracts."; font.pixelSize: Theme.small; color: Theme.muted }
                    Item {
                        Layout.fillWidth: true; implicitHeight: 320
                        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.teal, .3) }
                        DropFrame {
                            id: frame
                            x: 60; y: 1; width: 420; height: 0
                            lit: false
                            Behavior on width { NumberAnimation { duration: VisualQuality.ms(Theme.expand); easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1, 1] } }
                            Behavior on x { NumberAnimation { duration: VisualQuality.ms(Theme.expand); easing.type: Easing.OutCubic } }
                            GlowText { anchors.centerIn: parent; text: frame.height > 60 ? "PANEL CONTENT" : ""; font.pixelSize: 10; font.letterSpacing: 2; color: Theme.muted; opacity: frame.height > 120 ? 1 : 0; Behavior on opacity { NumberAnimation { duration: VisualQuality.ms(Theme.reveal) } } }
                        }
                    }
                    Flow { spacing: 6; Layout.fillWidth: true
                        StationButton { text: "Open"; onClicked: { frame.lit = false; frame.lit = true; frame.width = 420; frame.height = 280; } }
                        StationButton { text: "Retarget (wider)"; onClicked: { frame.lit = false; frame.lit = true; frame.x = 160; frame.width = 560; frame.height = 220; } }
                        StationButton { text: "Close"; onClicked: { frame.lit = false; frame.height = 0; } } }
                }
                // Kinetic Type
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    SectionMark { text: "KINETIC TYPE" }
                    RowLayout { spacing: 32
                        ColumnLayout { GlowText { text: "resolve"; font.pixelSize: 10; color: Theme.muted } KineticLabel { width: 220; height: 28; text: win.kineticWord; transitionStyle: "resolve"; font.pixelSize: 20; font.family: Theme.labelFont } }
                        ColumnLayout { GlowText { text: "relay (letter cascade)"; font.pixelSize: 10; color: Theme.muted } KineticStatus { width: 220; height: 28; text: win.statusWord; font.pixelSize: 14 } }
                        ColumnLayout { GlowText { text: "reveal (typed)"; font.pixelSize: 10; color: Theme.muted } KineticLabel { width: 300; height: 28; text: win.revealLine; transitionStyle: "reveal"; font.pixelSize: 14; font.family: Theme.labelFont; font.letterSpacing: 2; color: Theme.teal } }
                        ColumnLayout { GlowText { text: "number (rate-limited)"; font.pixelSize: 10; color: Theme.muted } KineticNumber { width: 120; height: 28; text: win.number + "%"; font.pixelSize: 20 } }
                        ColumnLayout { GlowText { text: "status pill"; font.pixelSize: 10; color: Theme.muted } StatusPill { text: win.statusWord; tone: win.statusWord === "CONNECTED" ? Theme.green : Theme.teal } } }
                    Flow { spacing: 6; Layout.fillWidth: true
                        StationButton { text: "BALANCED → GAMING"; onClicked: win.kineticWord = win.kineticWord === "GAMING" ? "BALANCED" : "GAMING" }
                        StationButton { text: "READY → FOCUS"; onClicked: win.kineticWord = win.kineticWord === "FOCUS" ? "READY" : "FOCUS" }
                        StationButton { text: "CONNECTING → CONNECTED"; onClicked: win.statusWord = win.statusWord === "CONNECTED" ? "CONNECTING" : "CONNECTED" }
                        StationButton { text: "PROTECTED → ATTENTION"; onClicked: win.statusWord = win.statusWord === "ATTENTION" ? "PROTECTED" : "ATTENTION" }
                        StationButton { text: "Unicode 🙂 → 🙁 (fallback)"; onClicked: win.statusWord = win.statusWord === "🙂 OK" ? "🙁 OFF" : "🙂 OK" }
                        StationButton { text: "Number +1"; onClicked: win.number++ }
                        StationButton { text: "Reveal a line"; onClicked: win.revealLine = win.revealLine === "THE FOREST IS STILL" ? "LIGHT RUNS ALONG THE ROOT" : "THE FOREST IS STILL" } }
                }
                // Whispers
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    SectionMark { text: "WHISPERS" }
                    Item { Layout.fillWidth: true; implicitHeight: 24
                        CedarWhispers { id: whispers; anchors.fill: parent; windowTitle: whisperTitle.checked ? "Summit1g · YouTube — Zen Browser" : "" } }
                    Flow { spacing: 6; Layout.fillWidth: true
                        StationButton { id: whisperTitle; text: "Window title"; checkable: true; checked: true; onClicked: checked = !checked }
                        StationButton { text: "Profile · Work"; onClicked: whispers.whisper("WORK PROFILE · NOTIFICATIONS, VISUAL QUALITY, BACKGROUND ACTIVITY") }
                        StationButton { text: "Focus · 25 min"; onClicked: whispers.whisper("FOCUS · 25 MIN") }
                        StationButton { text: "Shield · Attention"; onClicked: whispers.whisper("SHIELD · ATTENTION REQUIRED") }
                        StationButton { text: "Next quote"; onClicked: whispers.quoteIndex++ } }
                }
                // Canopy Pulse
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    SectionMark { text: "CANOPY PULSE" }
                    RowLayout { spacing: 24
                        Rectangle { width: 140; height: 44; radius: 8; color: Qt.alpha(Theme.surface, .9); CanopyPulse { anchors.centerIn: parent; active: true } }
                        GlowText { text: win.synthetic ? "SYNTHETIC TEST SIGNAL (labelled; not audio)" : Pulse.running ? "REAL CAVA FEED · " + Math.round(Pulse.energy * 100) + "% energy" : Pulse.available ? "FEED IDLE" : "CAVA UNAVAILABLE: " + Pulse.error; font.pixelSize: 10; font.letterSpacing: 1.2; color: win.synthetic ? Theme.amber : Theme.muted } }
                    Flow { spacing: 6
                        StationButton { text: win.synthetic ? "Stop synthetic signal" : "Synthetic test signal"; accent: Theme.amber; checked: win.synthetic; onClicked: { win.synthetic = !win.synthetic; if (!win.synthetic) { Pulse.levels = []; Pulse.energy = 0; } } } }
                }
            }
        }
    }
}
