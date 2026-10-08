import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// The silhouette of anything that grows out of the bar: a flat top that
// flows into the bar through two concave fillets (the bar's lower edge
// bending down to become the drop's sides), the long cut bottom-left and
// the short cut bottom-right of the Core pill's language. The top edge is
// left open so the surface reads as the bar itself continuing. Retained
// vector geometry: a size change re-renders two paths and nothing else.
//
// `join` is the fillet radius; 0 gives the straight wedges of the first
// drops. The owner animates width and height; this draws whatever it is.
Item {
    id: root
    property real cut: 12
    readonly property real longCut: Math.round(cut * 16 / 9)
    property real join: cut
    property color fill: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
    property color stroke: Qt.alpha(Theme.teal, .25)
    property real strokeWidth: 1
    // Strata: Foundation is the fill; Grain a lighter contour two pixels
    // inside it; the Living Edge the outline, which brightens while `lit`
    // (the surface unfolding) and settles back. Nothing moves otherwise.
    property bool grain: true
    property color grainColor: Qt.alpha(Theme.border, .55)
    property bool lit: false
    // The leading edge while the surface grows: a band of light along the bottom.
    property bool growing: false
    property color edge: lit ? Qt.alpha(stroke, Math.min(1, stroke.a * 2.2)) : stroke
    Behavior on edge { enabled: !Theme.reducedMotion; ColorAnimation { duration: VisualQuality.ms(Theme.morphGrow) } }
    // Unfolding: the Grain separates from the Foundation a beat later, and a
    // light runs the whole contour once, tracing the boundary as it forms.
    property real grainReveal: 1
    property real runner: -1
    readonly property real contourUnits: (2 * (height + width) + 2 * join) / Math.max(1, strokeWidth)
    onLitChanged: if (lit && VisualQuality.effects) { grainIn.restart(); trace.restart(); }
    SequentialAnimation { id: grainIn; PropertyAction { target: root; property: "grainReveal"; value: 0 } PauseAnimation { duration: VisualQuality.ms(80) } NumberAnimation { target: root; property: "grainReveal"; to: 1; duration: VisualQuality.ms(Theme.reveal); easing.type: Easing.OutCubic } }
    NumberAnimation { id: trace; target: root; property: "runner"; from: 0; to: 1; duration: VisualQuality.ms(Theme.morphGrow + Theme.reveal); easing.type: Easing.InOutQuad; onFinished: root.runner = -1 }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"; fillColor: root.fill
            startX: -root.join; startY: -1
            PathLine { x: root.width + root.join; y: -1 }
            PathLine { x: root.width + root.join; y: 0 }
            PathArc { x: root.width; y: root.join; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: 0; y: root.join }
            PathArc { x: -root.join; y: 0; radiusX: root.join; radiusY: root.join; direction: PathArc.Counterclockwise }
            PathLine { x: -root.join; y: -1 }
        }
        // Grain: the same contour, two pixels in, in the lighter material.
        ShapePath {
            strokeWidth: 1; strokeColor: root.grain ? Qt.alpha(root.grainColor, root.grainColor.a * root.grainReveal) : "transparent"; fillColor: "transparent"
            startX: -root.join + 2; startY: 2
            PathArc { x: 2; y: root.join + 1; radiusX: Math.max(1, root.join - 2); radiusY: Math.max(1, root.join - 2); direction: PathArc.Clockwise }
            PathLine { x: 2; y: root.height - root.longCut - 1 }
            PathLine { x: root.longCut + 1; y: root.height - 2 }
            PathLine { x: root.width - root.cut - 1; y: root.height - 2 }
            PathLine { x: root.width - 2; y: root.height - root.cut - 1 }
            PathLine { x: root.width - 2; y: root.join + 1 }
            PathArc { x: root.width + root.join - 2; y: 2; radiusX: Math.max(1, root.join - 2); radiusY: Math.max(1, root.join - 2); direction: PathArc.Clockwise }
        }
        // The Living Edge leaves the top open, so nothing draws a line across the bar.
        ShapePath {
            strokeWidth: root.strokeWidth; strokeColor: root.edge; fillColor: "transparent"
            startX: -root.join; startY: 0
            PathArc { x: 0; y: root.join; radiusX: root.join; radiusY: root.join; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width; y: root.join }
            PathArc { x: root.width + root.join; y: 0; radiusX: root.join; radiusY: root.join; direction: PathArc.Clockwise }
        }
        // The light that traces the contour once as it forms: a short bright
        // dash on the same path, its offset run from one end to the other.
        ShapePath {
            strokeWidth: root.strokeWidth * 3; strokeColor: root.runner >= 0 ? Qt.alpha(Theme.green, Math.min(1, VisualQuality.effectIntensity)) : "transparent"; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [40, root.contourUnits]
            dashOffset: 40 - root.runner * (root.contourUnits + 40)
            startX: -root.join; startY: 0
            PathArc { x: 0; y: root.join; radiusX: root.join; radiusY: root.join; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width; y: root.join }
            PathArc { x: root.width + root.join; y: 0; radiusX: root.join; radiusY: root.join; direction: PathArc.Clockwise }
        }
    }
    Rectangle {
        // The leading edge: the bar's material arriving, lit along its front.
        visible: root.growing && VisualQuality.effects
        x: root.longCut; y: root.height - 3; width: Math.max(0, root.width - root.longCut - root.cut); height: 3
        gradient: Gradient { orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: .5; color: Qt.alpha(Theme.green, Math.min(1, .85 * VisualQuality.effectIntensity)) }
            GradientStop { position: 1; color: "transparent" } }
    }
}
