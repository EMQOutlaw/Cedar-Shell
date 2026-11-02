import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// One continuous material surface. Only the outer ends are chamfered; the
// center instrument rests on an unoutlined grain plane in the same surface.
// All paths are retained and change only with the bar's logical dimensions.
Item {
    id: root
    property real materialOpacity: 1
    // Preview callers may supply a candidate palette without changing Theme.
    property color foundation: Theme.strataFoundation
    property color materialSurface: Theme.strataSurface
    property color grain: Theme.strataGrain
    property real centerWidth: 0
    // A one-shot increase in edge light, owned by the bar's awakening.
    property real awakening: 0
    property color eventAccent: Theme.strataAccent
    readonly property color awakeGrain: Qt.tint(root.grain, Qt.alpha(eventAccent, awakening * .7))
    // Flush (the default): the bar is the screen's upper edge, the material
    // running to the top and both sides with no wallpaper showing above or
    // beside it, so a drop growing from its lower edge is the same body
    // continuing. Only the lower edge keeps the inset the drops join at. A
    // detached bar floats with the inset and the pill's end cuts all round.
    property bool flush: false
    readonly property real insetLeft: flush ? 0 : Math.min(Theme.strataInset, width / 2)
    readonly property real insetRight: flush ? width : Math.max(insetLeft, width - Theme.strataInset)
    readonly property real insetTop: flush ? 0 : Math.min(Theme.strataInset, height / 2)
    readonly property real insetBottom: Math.max(insetTop, height - Theme.strataInset)
    readonly property real cut: flush ? 0 : Math.max(0, Math.min(Theme.strataCut, (insetRight - insetLeft) / 2, (insetBottom - insetTop) / 2))
    readonly property real center: width / 2
    readonly property real seatHalf: Math.min(Math.max(0, centerWidth) / 2, Math.max(0, (insetRight - insetLeft) / 2 - cut - 12))
    readonly property real seatLeft: center - seatHalf
    readonly property real seatRight: center + seatHalf
    readonly property real shoulder: Math.min(10, seatHalf / 3)
    // A span of the bottom edge left to the drop's field (bar coordinates);
    // empty when nothing drops. The stroke skips it, the material does not.
    property real gapFrom: 0
    property real gapTo: 0
    readonly property bool gapped: gapTo > gapFrom
    readonly property real leftBreak: gapped ? Math.max(insetLeft, Math.min(seatLeft, gapFrom)) : seatLeft
    readonly property real leftResume: gapped ? Math.max(insetLeft, Math.min(seatLeft, gapTo)) : seatLeft
    readonly property real rightBreak: gapped ? Math.min(insetRight - cut, Math.max(seatRight, gapTo)) : seatRight
    readonly property real rightResume: gapped ? Math.min(insetRight - cut, Math.max(seatRight, gapFrom)) : seatRight

    // ---- the field ----------------------------------------------------------
    // With effects on, the plate is drawn as its band of the Strata field
    // (shaders/strata.frag) together with whatever drop is growing out of it
    // (`Canopy.field`, published by the drop's window each frame it moves), so
    // the drop's fillets form in this plate's own lower edge. The Foundation
    // fill and the edge stroke come from the field; the seat and the grain
    // lip stay as the vector overlays below.
    readonly property var drop: Canopy.field
    readonly property bool field: VisualQuality.effects && !Config.testMode && shader.GraphicsInfo.api !== GraphicsInfo.Software && shader.status !== ShaderEffect.Error
    ShaderEffect {
        id: shader
        visible: root.field
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/strata.frag.qsb")
        readonly property size size: Qt.size(width, height)
        readonly property vector4d barRect: Qt.vector4d((root.insetLeft + root.insetRight) / 2, (root.insetTop + root.insetBottom) / 2, (root.insetRight - root.insetLeft) / 2, (root.insetBottom - root.insetTop) / 2)
        readonly property vector4d barCuts: Qt.vector4d(0, root.cut, 0, root.cut)
        readonly property var d: root.drop
        readonly property vector4d dropRect: d ? Qt.vector4d(d.x + d.width / 2, (d.top + d.bottom) / 2, d.width / 2, (d.bottom - d.top) / 2) : Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d dropCuts: Qt.vector4d(0, Theme.strataCut, Math.round(Theme.strataCut * 16 / 9), 0)
        readonly property vector4d invDeform: {
            if (!d) return Qt.vector4d(1, 0, 0, 1);
            const det = d.m00 * d.m11 - d.m01 * d.m01;
            const inv = Math.abs(det) > 1e-6 ? 1 / det : 1;
            return Qt.vector4d(d.m11 * inv, -d.m01 * inv, -d.m01 * inv, d.m00 * inv);
        }
        readonly property vector2d origin: d ? Qt.vector2d(d.ox, d.oy) : Qt.vector2d(0, 0)
        readonly property real minEig: {
            if (!d) return 1;
            const halfTr = (d.m00 + d.m11) / 2, halfDiff = (d.m00 - d.m11) / 2;
            return halfTr - Math.sqrt(halfDiff * halfDiff + d.m01 * d.m01);
        }
        readonly property real smoothing: Theme.morphSmoothing
        readonly property real side: 0
        readonly property real paintFrom: -1e6
        readonly property real paintTo: root.height
        readonly property vector2d seatGap: Qt.vector2d(root.seatLeft - root.shoulder, root.seatRight + root.shoulder)
        readonly property color fill: Qt.alpha(root.foundation, root.materialOpacity)
        readonly property color edge: d && d.lit ? Qt.alpha(root.awakeGrain, Math.min(1, .28 * 2.2)) : Qt.alpha(root.awakeGrain, .28 + root.awakening * .26)
        readonly property color restEdge: Qt.alpha(root.awakeGrain, .28 + root.awakening * .26)
        readonly property color grain: Qt.alpha(root.grain, .55)
        readonly property real edgeWidth: 1
        readonly property real grainInset: Theme.grainInset
        readonly property real grainAlpha: 1
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("StrataBarFrame: field shader unavailable, drawing vector paths:", log)
    }

    // Foundation (vector fallback): no separate cards or central cutout.
    Shape {
        visible: !root.field
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            strokeColor: Theme.transparent
            fillGradient: LinearGradient {
                x1: 0; y1: root.insetTop; x2: 0; y2: root.insetBottom
                // Flush, the bar is the same flat Foundation the drops are
                // made of; detached, it keeps the lighter surface at its top.
                GradientStop { position: 0; color: Qt.alpha(root.flush ? root.foundation : root.materialSurface, root.materialOpacity) }
                GradientStop { position: 1; color: Qt.alpha(root.foundation, root.materialOpacity) }
            }
            startX: root.insetLeft + root.cut; startY: root.insetTop - (root.flush ? 1 : 0)
            PathLine { x: root.insetRight + (root.flush ? 1 : 0); y: root.insetTop - (root.flush ? 1 : 0) }
            PathLine { x: root.insetRight + (root.flush ? 1 : 0); y: root.insetBottom - root.cut }
            PathLine { x: root.insetRight - root.cut; y: root.insetBottom }
            PathLine { x: root.insetLeft - (root.flush ? 1 : 0); y: root.insetBottom }
            PathLine { x: root.insetLeft - (root.flush ? 1 : 0); y: root.insetTop + root.cut }
            PathLine { x: root.insetLeft + root.cut; y: root.insetTop - (root.flush ? 1 : 0) }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // A quiet seat, flush with the surrounding material. Its shoulders
        // lean inwards without putting another outline around the Core.
        ShapePath {
            strokeWidth: 0
            strokeColor: Theme.transparent
            fillColor: Qt.alpha(Theme.strataGrain, root.seatHalf > 0 ? .055 : 0)
            startX: root.seatLeft - root.shoulder; startY: root.insetTop + 1
            PathLine { x: root.seatRight + root.shoulder; y: root.insetTop + 1 }
            PathLine { x: root.seatRight; y: root.insetBottom - 1 }
            PathLine { x: root.seatLeft; y: root.insetBottom - 1 }
            PathLine { x: root.seatLeft - root.shoulder; y: root.insetTop + 1 }
        }
        // The edge belongs to the two ends, leaving the center free of a
        // horizontal border beneath its own text and controls.
        ShapePath {
            strokeWidth: 1
            strokeColor: root.field ? Theme.transparent : Qt.alpha(root.awakeGrain, .28 + root.awakening * .26)
            fillColor: Theme.transparent
            startX: root.flush ? root.insetLeft : root.seatLeft - root.shoulder; startY: root.flush ? root.insetBottom : root.insetTop
            PathLine { x: root.flush ? root.insetLeft : root.insetLeft + root.cut; y: root.flush ? root.insetBottom : root.insetTop }
            PathLine { x: root.insetLeft; y: root.flush ? root.insetBottom : root.insetTop + root.cut }
            PathLine { x: root.insetLeft; y: root.insetBottom }
            PathLine { x: root.leftBreak; y: root.insetBottom }
            PathMove { x: root.leftResume; y: root.insetBottom }
            PathLine { x: root.seatLeft; y: root.insetBottom }
            PathMove { x: root.flush ? root.insetRight : root.seatRight + root.shoulder; y: root.flush ? root.insetBottom : root.insetTop }
            PathLine { x: root.insetRight; y: root.flush ? root.insetBottom : root.insetTop }
            PathLine { x: root.insetRight; y: root.insetBottom - root.cut }
            PathLine { x: root.insetRight - root.cut; y: root.insetBottom }
            PathLine { x: root.rightBreak; y: root.insetBottom }
            PathMove { x: root.rightResume; y: root.insetBottom }
            PathLine { x: root.seatRight; y: root.insetBottom }
        }
        // Grain is a partial inner lip, never a second full contour.
        ShapePath {
            strokeWidth: 1
            strokeColor: root.flush ? Theme.transparent : Qt.alpha(root.awakeGrain, .12 + root.awakening * .18)
            fillColor: Theme.transparent
            startX: root.insetLeft + root.cut + 2; startY: root.insetTop + 2
            PathLine { x: root.seatLeft - root.shoulder - 6; y: root.insetTop + 2 }
            PathMove { x: root.seatRight + root.shoulder + 6; y: root.insetTop + 2 }
            PathLine { x: root.insetRight - 2; y: root.insetTop + 2 }
        }
        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.strataGrain, root.seatHalf > 0 ? .10 : 0)
            fillColor: Theme.transparent
            startX: root.seatLeft - root.shoulder; startY: root.insetTop + 3
            PathLine { x: root.seatLeft; y: root.insetBottom - 3 }
            PathMove { x: root.seatRight + root.shoulder; y: root.insetTop + 3 }
            PathLine { x: root.seatRight; y: root.insetBottom - 3 }
        }
    }
}
