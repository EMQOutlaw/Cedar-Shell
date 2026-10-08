import QtQuick
import ".."
import "../services"
import "core/Kinetic.js" as Kinetic

// Kinetic Type: a label that moves when its meaning changes and is an
// ordinary static Text the rest of the time. On a change the policy in
// components/core/Kinetic.js picks one of:
//   relay    the glyphs that stayed hold still; the changed run leaves
//            upward and the new run arrives from below (simple scripts, short)
//   resolve  the whole label leaves upward and the new one arrives from below
//   fade     a crossfade
//   none     a static update (Reduced Motion, "none", or a rate-limited change)
// The transition objects exist only while a transition runs; nothing stays
// allocated at rest. Durations are Theme's, scaled by VisualQuality.
Item {
    id: root
    property string text: ""
    property string transitionStyle: "resolve"   // relay | resolve | fade | reveal | none
    property int duration: Theme.morphGrow
    property bool animateChanges: Config.saved.barKinetic && VisualQuality.effects
    property int maximumAnimatedLength: 16
    // Semantic compression: variants longest first; the longest that fits
    // `availableWidth` is shown, and the change between them animates.
    property var variants: []
    property real availableWidth: -1
    // Changes arriving faster than this are shown statically (numbers, clocks).
    property int minimumInterval: 0
    property real travel: 9
    property alias font: label.font
    property alias color: label.color
    property alias horizontalAlignment: label.horizontalAlignment
    property alias verticalAlignment: label.verticalAlignment
    property alias elide: label.elide
    property alias wrapMode: label.wrapMode
    property alias renderType: label.renderType
    readonly property string shown: label.text
    readonly property bool transitioning: overlay.active
    // Compression is computed, not bound: measuring sets the metrics' text,
    // which would loop a binding. It reruns when the inputs change.
    property string fitted: ""
    readonly property string effective: variants.length && availableWidth >= 0 ? fitted : text
    function refit() { fitted = variants.length && availableWidth >= 0 ? Kinetic.fit(variants, availableWidth, v => metrics.widthOf(v)) : ""; }
    onVariantsChanged: refit()
    onAvailableWidthChanged: refit()
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: effective
    property double lastChangeAt: 0

    TextMetrics { id: metrics; font: label.font; function widthOf(v) { text = v; return advanceWidth; } onFontChanged: root.refit() }
    Text {
        id: label
        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: Theme.normal
        color: Theme.text
        renderType: Text.QtRendering
        opacity: overlay.active ? 0 : 1
    }
    onEffectiveChanged: change(effective)
    Component.onCompleted: { refit(); label.text = effective; }
    function change(next) {
        const from = label.text, now = Date.now();
        if (from === next) return;
        // The first fill is not a change in meaning: no motion, no rate-limit mark.
        if (from === "" || next === "") { overlay.active = false; label.text = next; return; }
        const gated = minimumInterval > 0 && !Kinetic.allowed(lastChangeAt, now, minimumInterval);
        lastChangeAt = now;
        const style = !animateChanges || gated || !root.visible || root.width <= 0 ? "none" : Kinetic.choose(transitionStyle, from, next, maximumAnimatedLength, Theme.reducedMotion || !VisualQuality.decorative && VisualQuality.gaming);
        if (style === "none") { overlay.active = false; label.text = next; return; }
        overlay.from = from; overlay.to = next; overlay.style = style;
        label.text = next;                 // layout takes the new width at once; the overlay draws the motion
        overlay.active = false; overlay.active = true;
    }
    Loader {
        id: overlay
        property string from: ""
        property string to: ""
        property string style: "fade"
        anchors.fill: parent
        active: false
        sourceComponent: style === "relay" ? relay : style === "reveal" ? reveal : style === "fade" ? fade : resolve
        onLoaded: item.finished.connect(() => overlay.active = false)
    }
    readonly property int ms: VisualQuality.ms(duration)
    // A pair of labels in the label's own style: the base for resolve and fade.
    component Pair: Item {
        id: pair
        signal finished()
        property bool vertical: true
        anchors.fill: parent
        Text {
            id: outgoing
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: overlay.from; textFormat: Text.PlainText; font: label.font; color: label.color; horizontalAlignment: label.horizontalAlignment; elide: label.elide; renderType: label.renderType
        }
        Text {
            id: incoming
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: overlay.to; textFormat: Text.PlainText; font: label.font; color: label.color; horizontalAlignment: label.horizontalAlignment; elide: label.elide; renderType: label.renderType
            opacity: 0
        }
        ParallelAnimation {
            running: true
            NumberAnimation { target: outgoing; property: "opacity"; to: 0; duration: Math.round(root.ms * .6); easing.type: Easing.InCubic }
            NumberAnimation { target: outgoing; property: "anchors.verticalCenterOffset"; to: pair.vertical ? -root.travel : 0; duration: root.ms; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: Math.round(root.ms * .25) }
                ParallelAnimation {
                    NumberAnimation { target: incoming; property: "opacity"; to: 1; duration: Math.round(root.ms * .75); easing.type: Easing.OutCubic }
                    NumberAnimation { target: incoming; property: "anchors.verticalCenterOffset"; from: pair.vertical ? root.travel : 0; to: 0; duration: Math.round(root.ms * .75); easing.type: Easing.OutCubic }
                }
            }
            onFinished: pair.finished()
        }
    }
    Component { id: resolve; Pair { vertical: true } }
    Component { id: fade; Pair { vertical: false } }
    // Reveal: the new label is typed in, each glyph a beat after the last, the newest one bright.
    Component {
        id: reveal
        Item {
            id: typed
            signal finished()
            readonly property var glyphs: Array.from(overlay.to)
            readonly property int step: Math.max(14, Math.round(root.ms * .07))
            anchors.fill: parent
            Text { id: whole; visible: false; text: overlay.to; font: label.font; textFormat: Text.PlainText }
            readonly property real baseX: label.horizontalAlignment === Text.AlignHCenter ? (width - whole.implicitWidth) / 2 : label.horizontalAlignment === Text.AlignRight ? width - whole.implicitWidth : 0
            Row {
                x: typed.baseX; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: typed.glyphs
                    Item {
                        id: g
                        required property string modelData
                        required property int index
                        width: t.implicitWidth; height: t.implicitHeight
                        Text { id: t; text: g.modelData; textFormat: Text.PlainText; font: label.font; color: label.color; renderType: label.renderType; opacity: 0 }
                        Text { id: bright; text: g.modelData; textFormat: Text.PlainText; font: label.font; color: Theme.white; renderType: label.renderType; opacity: 0 }
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: g.index * typed.step }
                            PropertyAction { target: bright; property: "opacity"; value: 1 }
                            ParallelAnimation {
                                NumberAnimation { target: t; property: "opacity"; to: 1; duration: typed.step * 3 }
                                NumberAnimation { target: bright; property: "opacity"; to: 0; duration: typed.step * 5; easing.type: Easing.InQuad }
                            }
                        }
                    }
                }
            }
            Timer { interval: typed.glyphs.length * typed.step + typed.step * 6 + 40; running: true; onTriggered: typed.finished() }
        }
    }
    // Character relay: prefix and suffix hold still, the changed run resolves.
    Component {
        id: relay
        Item {
            id: run
            signal finished()
            readonly property var plan: Kinetic.relay(overlay.from, overlay.to)
            anchors.fill: parent
            // The run is laid out from the label's left edge for left-aligned
            // text; centred and right-aligned labels start from their own offset.
            readonly property real baseX: label.horizontalAlignment === Text.AlignHCenter ? (width - full.implicitWidth) / 2 : label.horizontalAlignment === Text.AlignRight ? width - full.implicitWidth : 0
            Text { id: full; visible: false; text: overlay.to; font: label.font; textFormat: Text.PlainText }
            Text { id: prefix; x: run.baseX; anchors.verticalCenter: parent.verticalCenter; text: run.plan.prefix; textFormat: Text.PlainText; font: label.font; color: label.color; renderType: label.renderType }
            Text { id: leaving; x: run.baseX + prefix.implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: run.plan.leaving; textFormat: Text.PlainText; font: label.font; color: label.color; renderType: label.renderType }
            // The arriving run, letter by letter: each glyph drops into place a beat after the last, bright, then settles to the label's colour.
            Text { id: arriving; visible: false; x: run.baseX + prefix.implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: run.plan.arriving; textFormat: Text.PlainText; font: label.font }
            Row {
                id: cascade
                x: run.baseX + prefix.implicitWidth; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: Array.from(run.plan.arriving)
                    Item {
                        id: glyph
                        required property string modelData
                        required property int index
                        width: glyphText.implicitWidth; height: glyphText.implicitHeight
                        Text { id: glyphText; text: glyph.modelData; textFormat: Text.PlainText; font: label.font; color: label.color; renderType: label.renderType; opacity: 0
                            Text { anchors.fill: parent; text: glyph.modelData; textFormat: Text.PlainText; font: label.font; color: Theme.white; renderType: label.renderType; opacity: 0; id: flash } }
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: Math.round(root.ms * .18) + glyph.index * Math.round(root.ms * .09) }
                            ParallelAnimation {
                                NumberAnimation { target: glyphText; property: "opacity"; to: 1; duration: Math.round(root.ms * .5); easing.type: Easing.OutCubic }
                                NumberAnimation { target: glyphText; property: "y"; from: root.travel; to: 0; duration: Math.round(root.ms * .55); easing.type: Easing.OutBack }
                                SequentialAnimation { NumberAnimation { target: flash; property: "opacity"; to: .9; duration: Math.round(root.ms * .2) } NumberAnimation { target: flash; property: "opacity"; to: 0; duration: Math.round(root.ms * .5) } }
                            }
                        }
                    }
                }
            }
            Text { id: suffix; anchors.verticalCenter: parent.verticalCenter; text: run.plan.suffix; textFormat: Text.PlainText; font: label.font; color: label.color; renderType: label.renderType
                x: run.baseX + prefix.implicitWidth + leaving.implicitWidth }
            ParallelAnimation {
                running: true
                NumberAnimation { target: leaving; property: "opacity"; to: 0; duration: Math.round(root.ms * .55); easing.type: Easing.InCubic }
                NumberAnimation { target: leaving; property: "anchors.verticalCenterOffset"; to: -root.travel * .8; duration: root.ms; easing.type: Easing.OutCubic }
                NumberAnimation { target: suffix; property: "x"; to: run.baseX + prefix.implicitWidth + arriving.implicitWidth; duration: root.ms; easing.type: Easing.OutCubic }
                PauseAnimation { duration: Math.round(root.ms * .75) + Array.from(run.plan.arriving).length * Math.round(root.ms * .09) }
                onFinished: run.finished()
            }
        }
    }
}
