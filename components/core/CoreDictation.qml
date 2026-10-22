import QtQuick
import "../.."
import ".."
import "../../services"

// Dictation inside the Core pill. While Voxtype listens, the pill's text
// yields to a single filament: the recent loudness of the microphone drawn
// as one line that swells toward the right where the newest reading is, with
// its root mirrored faintly beneath. It is cedar green while the room is
// quiet and turns ember while Voxtype's own voice detection hears speech.
// When the recording stops and Voxtype transcribes, the filament settles flat
// and one amber light travels along it, left to right, until the words land;
// then the pill returns to the clock.
//
// Every reading is Voxtype's (Dictation.frame); nothing is synthesised. With
// no level feed the line rests quiet and the glyph and clock still say what
// Voxtype is doing. Reduced Motion draws the levels without easing, at a slow
// cadence, and shows a static amber line instead of the travelling light.
// The sweep is bounded: it stops on its own after two minutes even if the
// state never returns, and the moment the surface is hidden.
Item {
    id: root
    readonly property bool recording: Dictation.recording
    readonly property bool transcribing: Dictation.transcribing
    readonly property bool live: visible && width > 0 && (recording || transcribing)
    readonly property bool animated: VisualQuality.functionalMotion
    readonly property int sampleCount: 56
    property var samples: []
    // Voxtype's RMS sits near .05 in a quiet room and .15–.3 for ordinary
    // speech; a gain of four and a gentle curve keep room noise low on the
    // line and let speech reach its full height.
    property real gain: 4
    // Voxtype's VAD, held a moment so a syllable gap does not flicker the colour.
    property bool speaking: false
    property real voiceBlend: speaking ? 1 : 0
    Behavior on voiceBlend { enabled: root.animated; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    property real sweep: 0
    property bool dirty: true
    property string elapsed: "0:00"
    readonly property color quietColor: Theme.green
    readonly property color voiceColor: Theme.ember
    readonly property color doneColor: Theme.amber
    readonly property color lineColor: transcribing ? doneColor : Qt.rgba(
        quietColor.r + (voiceColor.r - quietColor.r) * voiceBlend,
        quietColor.g + (voiceColor.g - quietColor.g) * voiceBlend,
        quietColor.b + (voiceColor.b - quietColor.b) * voiceBlend, 1)
    implicitHeight: 24

    function reset() {
        const next = [];
        for (let i = 0; i < sampleCount; i++) next.push(0);
        samples = next;
        speaking = false;
        voiceHold.stop();
        dirty = true;
    }
    function push(level) {
        const next = samples.length === sampleCount ? samples.slice(1) : samples.slice(Math.max(0, samples.length + 1 - sampleCount));
        next.push(Math.pow(Math.max(0, Math.min(1, level * gain)), 1.3));
        samples = next;
        dirty = true;
    }
    // While transcribing the line settles flat on its own; no new readings arrive.
    function settle() {
        let moved = false;
        const next = samples.map(v => { const n = v > .01 ? v * .82 : 0; if (n !== v) moved = true; return n; });
        if (moved) { samples = next; dirty = true; }
    }
    function tick() {
        if (!recording) return;
        elapsed = Media.elapsed((Date.now() - Dictation.startedAt) / 1000);
    }
    Component.onCompleted: reset()
    onRecordingChanged: {
        if (recording) { reset(); tick(); }
        else { speaking = false; voiceHold.stop(); }
    }
    onTranscribingChanged: { capped = false; if (!transcribing) sweep = 0; }
    onLiveChanged: { dirty = true; if (!live) reset(); }
    // A colour change is rare and visible at once; levels wait for the tick.
    onLineColorChanged: if (live) canvas.requestPaint()
    onSweepChanged: dirty = true
    onWidthChanged: dirty = true

    Connections {
        target: Dictation
        function onFrame(peak, rms, voice) {
            if (!root.recording) return;
            root.push(rms);
            if (voice) { root.speaking = true; voiceHold.restart(); }
            else if (!voiceHold.running) root.speaking = false;
        }
    }
    Timer { id: voiceHold; interval: 260; onTriggered: if (!Dictation.voice) root.speaking = false }
    // One repaint per tick while live, never per frame: thirty a second with
    // motion, four without. Nothing repaints once the pill is back at rest.
    Timer {
        interval: root.animated ? 33 : 250
        repeat: true
        running: root.live
        onTriggered: {
            if (root.transcribing) root.settle();
            if (root.dirty) { root.dirty = false; canvas.requestPaint(); }
        }
    }
    Timer { interval: 1000; repeat: true; running: root.recording && root.visible; triggeredOnStart: true; onTriggered: root.tick() }
    // The travelling light: a loop with a lifetime, stopped by the state, the
    // surface or the two-minute cap, whichever comes first.
    property bool capped: false
    SequentialAnimation {
        id: travel
        running: root.transcribing && root.live && root.animated && !root.capped
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.sweep = 0
        NumberAnimation { target: root; property: "sweep"; from: 0; to: 1; duration: 1300; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 220 }
    }
    Timer { interval: 120000; running: root.transcribing; onTriggered: root.capped = true }

    Text {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.transcribing ? "󰔟" : "󰍬"
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: Theme.small + 2
        color: root.lineColor
        opacity: .9
        Accessible.role: Accessible.StaticText
        Accessible.name: root.transcribing ? "Transcribing dictation" : "Dictation listening"
    }
    Canvas {
        id: canvas
        objectName: "coreDictationLine"
        anchors.left: glyph.right
        anchors.leftMargin: 8
        anchors.right: time.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            ctx.clearRect(0, 0, w, h);
            if (w < 8 || root.samples.length < 2) return;
            const mid = h / 2;
            const rise = Math.max(2, mid - 3);
            const n = root.samples.length;
            const step = w / (n - 1);
            const color = root.lineColor;
            const dim = Qt.alpha(color, .16);
            const lit = Qt.alpha(color, root.transcribing ? .55 : .92);
            // The ground: a faint rest line the filament rises from.
            ctx.lineWidth = 1;
            ctx.strokeStyle = dim;
            ctx.beginPath(); ctx.moveTo(0, mid + .5); ctx.lineTo(w, mid + .5); ctx.stroke();
            if (!root.transcribing || root.samples.some(v => v > 0)) {
                // The filament above and its root below, one smooth path each.
                for (const side of [1, -1]) {
                    ctx.beginPath();
                    ctx.moveTo(0, mid - side * root.samples[0] * rise * (side > 0 ? 1 : .45));
                    for (let i = 1; i < n; i++) {
                        const x0 = (i - 1) * step, x1 = i * step;
                        const y0 = mid - side * root.samples[i - 1] * rise * (side > 0 ? 1 : .45);
                        const y1 = mid - side * root.samples[i] * rise * (side > 0 ? 1 : .45);
                        ctx.quadraticCurveTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
                    }
                    ctx.lineTo(w, mid);
                    ctx.lineWidth = side > 0 ? 1.6 : 1;
                    ctx.strokeStyle = side > 0 ? lit : Qt.alpha(color, .28);
                    ctx.stroke();
                    if (side > 0 && root.voiceBlend > .02 && !root.transcribing) {
                        // Speech lights a soft aura along the same path.
                        ctx.lineWidth = 5;
                        ctx.strokeStyle = Qt.alpha(color, .14 * root.voiceBlend);
                        ctx.stroke();
                    }
                }
            }
            if (root.transcribing && root.sweep > 0) {
                // One light travelling the length of the line.
                const span = Math.max(18, w * .22);
                const x = -span + (w + span) * root.sweep;
                const g = ctx.createLinearGradient(x, 0, x + span, 0);
                g.addColorStop(0, Qt.alpha(color, 0));
                g.addColorStop(.6, Qt.alpha(color, .95));
                g.addColorStop(1, Qt.alpha(color, 0));
                ctx.lineWidth = 2;
                ctx.strokeStyle = g;
                ctx.beginPath(); ctx.moveTo(Math.max(0, x), mid + .5); ctx.lineTo(Math.min(w, x + span), mid + .5); ctx.stroke();
            } else if (root.transcribing && !root.animated) {
                ctx.lineWidth = 2;
                ctx.strokeStyle = Qt.alpha(color, .7);
                ctx.beginPath(); ctx.moveTo(0, mid + .5); ctx.lineTo(w, mid + .5); ctx.stroke();
            }
        }
    }
    Text {
        id: time
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.elapsed
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: Theme.small + 1
        color: root.transcribing ? Theme.strataMuted : Theme.strataText
        renderType: Text.QtRendering
    }
}
