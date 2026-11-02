import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// The silhouette of anything that grows out of the bar: a flat top that
// flows into the bar through two concave fillets (the bar's lower edge
// bending down to become the drop's sides), the long cut bottom-left and
// the short cut bottom-right of the Core pill's language. The top edge is
// left open so the surface reads as the bar itself continuing.
//
// With effects on, the drop is one distance field with the bar
// (shaders/strata.frag): the bar's plate and the drop are two chamfered boxes,
// joined by a circular smooth-minimum of radius `smoothing`. The fillet is
// then a true tangent arc at every size, present from the first pixel of
// growth as a low swell in the bar's edge, and the grow curve's overshoot
// stretches that swell rather than a hard outline. The body also yields to
// its own motion: a spring-driven squash along the direction of travel,
// which the owner applies to the content through `deformMatrix` so the
// instruments lean with the surface. Both rest the moment the surface does.
//
// Without effects (Reduced Motion, Gaming, tests, or a shader that failed
// to load) the same silhouette is drawn as retained vector paths, rigid.
//
// `join` is the fillet radius of the vector fallback; 0 gives the straight
// wedges of the first drops. The owner animates width and height; this
// draws whatever it is.
Item {
    id: root
    property real cut: 12
    readonly property real longCut: Math.round(cut * 16 / 9)
    property real join: cut
    property real smoothing: Theme.morphSmoothing
    property real squash: Theme.morphSquash
    // How far along the bar the field draws beyond the drop (fillets and lean).
    readonly property real padAlong: smoothing + Theme.spaceSm
    // Sideways: the surface grows out of a bar on the left. The open edge is
    // the left one, the fillets bend the bar's right edge into the panel's top
    // and bottom, and the right side carries the pill's cuts (short above, long below).
    property bool side: false
    property color fill: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
    property color stroke: Qt.alpha(Theme.teal, .25)
    // The bar's own edge colour: the field continues the bar's line in it.
    property color barStroke: stroke
    property real strokeWidth: 1
    // Strata: Foundation is the fill; Grain a lighter contour two pixels
    // inside it; the Living Edge the outline, which brightens while `lit`
    // (the surface unfolding) and settles back. Nothing moves otherwise.
    property bool grain: true
    property color grainColor: Qt.alpha(Theme.border, .55)
    property bool lit: false
    // The leading edge while the surface grows: a band of light along the bottom.
    property bool growing: false
    readonly property bool live: visible && Motion.active && VisualQuality.effects
    readonly property bool animating: grainIn.running || trace.running || physics.running
    // The field renderer, when the shell draws effects, the scene graph has a
    // GPU backend (the software backend draws no ShaderEffect at all and
    // reports no error) and the shader loaded.
    readonly property bool field: VisualQuality.effects && !Config.testMode && shader.GraphicsInfo.api !== GraphicsInfo.Software && shader.status !== ShaderEffect.Error
    onFieldChanged: if (!field) physics.rest()
    property color edge: lit ? Qt.alpha(stroke, Math.min(1, stroke.a * 2.2)) : stroke
    Behavior on edge { enabled: root.live; ColorAnimation { duration: VisualQuality.ms(Theme.morphGrow) } }
    // Unfolding: the Grain separates from the Foundation a beat later, and a
    // light runs the whole contour once, tracing the boundary as it forms.
    property real grainReveal: 1
    property real runner: -1
    // The Grain contour of the vector fallback: this far inside the edge, and
    // along a 45-degree cut that inset lands half as far along the cut's run.
    readonly property real grainIn: Theme.grainInset
    readonly property real grainCut: Math.round(Theme.grainInset / 2)
    // The vector paths never ask for an arc taller than the surface.
    readonly property real arc: Math.max(0, Math.min(join, (side ? width : height) / 2))
    readonly property real contourUnits: (2 * (height + width) + 2 * arc) / Math.max(1, strokeWidth)
    onLitChanged: if (lit && live) { grainIn.restart(); trace.restart(); }
    onLiveChanged: {
        if (live) return;
        grainIn.stop(); trace.stop();
        grainReveal = 1; runner = -1;
        physics.rest();
    }
    SequentialAnimation { id: grainIn; PropertyAction { target: root; property: "grainReveal"; value: 0 } PauseAnimation { duration: VisualQuality.ms(80) } NumberAnimation { target: root; property: "grainReveal"; to: 1; duration: VisualQuality.ms(Theme.reveal); easing.type: Easing.OutCubic } }
    NumberAnimation { id: trace; target: root; property: "runner"; from: 0; to: 1; duration: VisualQuality.ms(Theme.morphGrow + Theme.reveal); easing.type: Easing.InOutQuad; onFinished: root.runner = -1 }

    // ---- the squash ---------------------------------------------------------
    // The surface's centre is sampled each frame while it moves; its speed
    // sets a target stretch along the direction of travel (and the matching
    // compression across it), and three underdamped springs carry the
    // symmetric 2x2 matrix there and back. The fixed point is where the drop
    // meets the bar, so the join never parts. Rests, and stops sampling, as
    // soon as the surface is still and the springs have settled.
    readonly property real m00: physics.m00
    readonly property real m01: physics.m01
    readonly property real m11: physics.m11
    readonly property point deformOrigin: side ? Qt.point(0, height / 2) : Qt.point(width / 2, 0)
    readonly property matrix4x4 deformMatrix: {
        const o = deformOrigin;
        return Qt.matrix4x4(m00, m01, 0, o.x - m00 * o.x - m01 * o.y,
                            m01, m11, 0, o.y - m01 * o.x - m11 * o.y,
                            0, 0, 1, 0,
                            0, 0, 0, 1);
    }
    function nudge() { if (live && field && squash > 0) physics.running = true; }
    onWidthChanged: nudge()
    onHeightChanged: nudge()
    onXChanged: nudge()
    onYChanged: nudge()
    // The owner moves the drop, not this frame (anchors.fill), so watch it too.
    Connections { target: root.parent; function onXChanged() { root.nudge(); } function onYChanged() { root.nudge(); } }
    FrameAnimation {
        id: physics
        property real m00: 1
        property real m01: 0
        property real m11: 1
        property real v00: 0
        property real v01: 0
        property real v11: 0
        property real prevX: 0
        property real prevY: 0
        property bool primed: false
        property int skipped: 0
        readonly property real stiffness: 200
        readonly property real damping: 16
        running: false
        function rest() { running = false; primed = false; skipped = 0; m00 = 1; m01 = 0; m11 = 1; v00 = 0; v01 = 0; v11 = 0; }
        onRunningChanged: if (!running) primed = false
        onTriggered: {
            const c = root.mapToItem(null, root.width / 2, root.height / 2);
            const cx = c.x, cy = c.y;
            const dt = frameTime;
            if (!primed || dt <= 0.001 || dt > 0.1) {
                // An unusable step is skipped, never integrated; a run of them
                // (a stalled or hidden surface) rests outright so sampling ends.
                prevX = cx; prevY = cy; primed = true;
                if (++skipped >= 8) rest();
                return;
            }
            skipped = 0;
            const vx = (cx - prevX) / dt, vy = (cy - prevY) / dt;
            prevX = cx; prevY = cy;
            const speed = Math.sqrt(vx * vx + vy * vy);
            let t00 = 1, t01 = 0, t11 = 1;
            if (speed > 5) {
                const scale = root.squash * Math.min(1, VisualQuality.effectIntensity) / 10000;
                const stretch = 1 + Math.min(speed * scale, .35), compress = 1 / stretch;
                const c = vx / speed, s = vy / speed;
                t00 = stretch * c * c + compress * s * s;
                t01 = (stretch - compress) * c * s;
                t11 = stretch * s * s + compress * c * c;
            }
            // Damping is implicit so a slow frame can only settle, never add energy.
            const inv = 1 / (1 + damping * dt);
            v00 = (v00 - stiffness * (m00 - t00) * dt) * inv; m00 += v00 * dt;
            v01 = (v01 - stiffness * (m01 - t01) * dt) * inv; m01 += v01 * dt;
            v11 = (v11 - stiffness * (m11 - t11) * dt) * inv; m11 += v11 * dt;
            const still = speed < 5 && Math.abs(m00 - 1) < 1e-3 && Math.abs(m01) < 1e-3 && Math.abs(m11 - 1) < 1e-3
                        && Math.abs(v00) < 1e-2 && Math.abs(v01) < 1e-2 && Math.abs(v11) < 1e-2;
            if (still) rest();
        }
    }

    // ---- the field ----------------------------------------------------------
    // The owner describes the bar's plate in this item's coordinates
    // (`barRect`, `barCuts`) and how far the drop's body reaches up into it
    // (`emerge`); this instance paints the field only from `paintFrom` on the
    // reach axis (the bar's window paints the rest, from the same geometry).
    // Padded beyond the drop so the fillets and a stretched body have room.
    property vector4d barRect: side ? Qt.vector4d(-1e4, height / 2, 1e4, 1e5) : Qt.vector4d(width / 2, -1e4, 1e5, 1e4)
    property vector4d barCuts: Qt.vector4d(0, 0, 0, 0)
    property real emerge: 0
    property real paintFrom: 0
    property vector2d seatGap: Qt.vector2d(0, 0)
    ShaderEffect {
        id: shader
        visible: root.field
        readonly property real padAlong: root.padAlong
        readonly property real padReach: Theme.spaceLg
        readonly property real padBar: root.emerge + root.smoothing
        x: root.side ? -padBar : -padAlong
        y: root.side ? -padAlong : -padBar
        width: root.side ? root.width + padReach + padBar : root.width + 2 * padAlong
        height: root.side ? root.height + 2 * padAlong : root.height + padReach + padBar
        fragmentShader: Qt.resolvedUrl("shaders/strata.frag.qsb")
        // Uniforms, named as in the shader (item px: the drop's origin is at (padAlong, padBar) or (padBar, padAlong)).
        readonly property vector2d off: root.side ? Qt.vector2d(padBar, padAlong) : Qt.vector2d(padAlong, padBar)
        readonly property size size: Qt.size(width, height)
        readonly property vector4d barRect: Qt.vector4d(root.barRect.x + off.x, root.barRect.y + off.y, root.barRect.z, root.barRect.w)
        readonly property vector4d barCuts: root.barCuts
        readonly property vector4d dropRect: root.side ? Qt.vector4d(off.x + (root.width - root.emerge) / 2, off.y + root.height / 2, (root.width + root.emerge) / 2, root.height / 2)
                                                       : Qt.vector4d(off.x + root.width / 2, off.y + (root.height - root.emerge) / 2, root.width / 2, (root.height + root.emerge) / 2)
        readonly property vector4d dropCuts: root.side ? Qt.vector4d(root.cut, root.longCut, 0, 0) : Qt.vector4d(0, root.cut, root.longCut, 0)
        readonly property vector4d invDeform: {
            const det = root.m00 * root.m11 - root.m01 * root.m01;
            const inv = Math.abs(det) > 1e-6 ? 1 / det : 1;
            return Qt.vector4d(root.m11 * inv, -root.m01 * inv, -root.m01 * inv, root.m00 * inv);
        }
        readonly property vector2d origin: root.side ? Qt.vector2d(off.x, off.y + root.height / 2) : Qt.vector2d(off.x + root.width / 2, off.y)
        readonly property real minEig: {
            const halfTr = (root.m00 + root.m11) / 2, halfDiff = (root.m00 - root.m11) / 2;
            return halfTr - Math.sqrt(halfDiff * halfDiff + root.m01 * root.m01);
        }
        readonly property real smoothing: root.smoothing
        readonly property real side: root.side ? 1 : 0
        readonly property real paintFrom: padBar + root.paintFrom
        readonly property real paintTo: 1e6
        readonly property vector2d seatGap: Qt.vector2d(root.seatGap.x + off.x, root.seatGap.y + off.x)
        readonly property color fill: root.fill
        readonly property color edge: root.edge
        readonly property color restEdge: root.barStroke
        readonly property color grain: root.grain ? root.grainColor : Theme.transparent
        readonly property real edgeWidth: root.strokeWidth
        readonly property real grainInset: Theme.grainInset
        readonly property real grainAlpha: root.grainReveal
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("DropFrame: field shader unavailable, drawing vector paths:", log)
    }

    // ---- the vector fallback ------------------------------------------------
    Shape {
        visible: !root.side && !root.field
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"; fillColor: root.fill
            startX: -root.arc; startY: -1
            PathLine { x: root.width + root.arc; y: -1 }
            PathLine { x: root.width + root.arc; y: 0 }
            PathArc { x: root.width; y: root.arc; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Counterclockwise }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: 0; y: root.arc }
            PathArc { x: -root.arc; y: 0; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Counterclockwise }
            PathLine { x: -root.arc; y: -1 }
        }
        // Grain: the same contour, two pixels in, in the lighter material.
        ShapePath {
            strokeWidth: 1; strokeColor: root.grain ? Qt.alpha(root.grainColor, root.grainColor.a * root.grainReveal) : "transparent"; fillColor: "transparent"
            startX: -root.arc + root.grainIn; startY: root.grainIn
            PathArc { x: root.grainIn; y: root.arc + root.grainCut; radiusX: Math.max(1, root.arc - root.grainIn); radiusY: Math.max(1, root.arc - root.grainIn); direction: PathArc.Clockwise }
            PathLine { x: root.grainIn; y: root.height - root.longCut - root.grainCut }
            PathLine { x: root.longCut + root.grainCut; y: root.height - root.grainIn }
            PathLine { x: root.width - root.cut - root.grainCut; y: root.height - root.grainIn }
            PathLine { x: root.width - root.grainIn; y: root.height - root.cut - root.grainCut }
            PathLine { x: root.width - root.grainIn; y: root.arc + root.grainCut }
            PathArc { x: root.width + root.arc - root.grainIn; y: root.grainIn; radiusX: Math.max(1, root.arc - root.grainIn); radiusY: Math.max(1, root.arc - root.grainIn); direction: PathArc.Clockwise }
        }
        // The Living Edge leaves the top open, so nothing draws a line across the bar.
        ShapePath {
            strokeWidth: root.strokeWidth; strokeColor: root.edge; fillColor: "transparent"
            startX: -root.arc; startY: 0
            PathArc { x: 0; y: root.arc; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width; y: root.arc }
            PathArc { x: root.width + root.arc; y: 0; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
        }
    }
    Shape {
        visible: root.side && !root.field
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"; fillColor: root.fill
            startX: -1; startY: -root.arc
            PathLine { x: 0; y: -root.arc }
            PathArc { x: root.arc; y: 0; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
            PathLine { x: root.width - root.cut; y: 0 }
            PathLine { x: root.width; y: root.cut }
            PathLine { x: root.width; y: root.height - root.longCut }
            PathLine { x: root.width - root.longCut; y: root.height }
            PathLine { x: root.arc; y: root.height }
            PathArc { x: 0; y: root.height + root.arc; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
            PathLine { x: -1; y: root.height + root.arc }
            PathLine { x: -1; y: -root.arc }
        }
        ShapePath {
            strokeWidth: 1; strokeColor: root.grain ? Qt.alpha(root.grainColor, root.grainColor.a * root.grainReveal) : "transparent"; fillColor: "transparent"
            startX: root.grainIn; startY: -root.arc + root.grainIn
            PathArc { x: root.arc + root.grainCut; y: root.grainIn; radiusX: Math.max(1, root.arc - root.grainIn); radiusY: Math.max(1, root.arc - root.grainIn); direction: PathArc.Counterclockwise }
            PathLine { x: root.width - root.cut - root.grainCut; y: root.grainIn }
            PathLine { x: root.width - root.grainIn; y: root.cut + root.grainCut }
            PathLine { x: root.width - root.grainIn; y: root.height - root.longCut - root.grainCut }
            PathLine { x: root.width - root.longCut - root.grainCut; y: root.height - root.grainIn }
            PathLine { x: root.arc + root.grainCut; y: root.height - root.grainIn }
            PathArc { x: root.grainIn; y: root.height + root.arc - root.grainIn; radiusX: Math.max(1, root.arc - root.grainIn); radiusY: Math.max(1, root.arc - root.grainIn); direction: PathArc.Counterclockwise }
        }
        // The Living Edge leaves the left open, so nothing draws a line down the bar.
        ShapePath {
            strokeWidth: root.strokeWidth; strokeColor: root.edge; fillColor: "transparent"
            startX: 0; startY: -root.arc
            PathArc { x: root.arc; y: 0; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
            PathLine { x: root.width - root.cut; y: 0 }
            PathLine { x: root.width; y: root.cut }
            PathLine { x: root.width; y: root.height - root.longCut }
            PathLine { x: root.width - root.longCut; y: root.height }
            PathLine { x: root.arc; y: root.height }
            PathArc { x: 0; y: root.height + root.arc; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
        }
    }

    // ---- the trace and the leading edge, on either renderer ----------------
    // The light that traces the contour once as it forms: a short bright
    // dash on the contour path, its offset run from one end to the other.
    // It leans with the body like the content does.
    Item {
        anchors.fill: parent
        transform: Matrix4x4 { matrix: root.deformMatrix }
        Shape {
            visible: root.runner >= 0
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: root.strokeWidth * 3; strokeColor: Qt.alpha(Theme.green, Math.min(1, VisualQuality.effectIntensity)); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                dashPattern: [40, root.contourUnits]
                dashOffset: 40 - root.runner * (root.contourUnits + 40)
                startX: root.side ? 0 : -root.arc; startY: root.side ? -root.arc : 0
                PathArc { x: root.side ? root.arc : 0; y: root.side ? 0 : root.arc; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
                PathLine { x: root.side ? root.width - root.cut : 0; y: root.side ? 0 : root.height - root.longCut }
                PathLine { x: root.side ? root.width : root.longCut; y: root.side ? root.cut : root.height }
                PathLine { x: root.side ? root.width : root.width - root.cut; y: root.side ? root.height - root.longCut : root.height }
                PathLine { x: root.side ? root.width - root.longCut : root.width; y: root.side ? root.height : root.height - root.cut }
                PathLine { x: root.side ? root.arc : root.width; y: root.side ? root.height : root.arc }
                PathArc { x: root.side ? 0 : root.width + root.arc; y: root.side ? root.height + root.arc : 0; radiusX: root.arc; radiusY: root.arc; direction: PathArc.Clockwise }
            }
        }
        Rectangle {
            // Sideways, the leading edge is the right side.
            visible: root.side && root.growing && VisualQuality.effects
            x: root.width - 3; y: root.cut; width: 3; height: Math.max(0, root.height - root.cut - root.longCut)
            gradient: Gradient { orientation: Gradient.Vertical
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: .5; color: Qt.alpha(Theme.green, Math.min(1, .85 * VisualQuality.effectIntensity)) }
                GradientStop { position: 1; color: "transparent" } }
        }
        Rectangle {
            // The leading edge: the bar's material arriving, lit along its front.
            visible: !root.side && root.growing && VisualQuality.effects
            x: root.longCut; y: root.height - 3; width: Math.max(0, root.width - root.longCut - root.cut); height: 3
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: .5; color: Qt.alpha(Theme.green, Math.min(1, .85 * VisualQuality.effectIntensity)) }
                GradientStop { position: 1; color: "transparent" } }
        }
    }
}
