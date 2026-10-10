import QtQuick
import QtQuick.Shapes
import ".."

// One continuous material surface. Only the outer ends are chamfered; the
// center instrument rests on an unoutlined grain plane in the same surface.
// All paths are retained and change only with the bar's logical dimensions.
Item {
    id: root
    property real materialOpacity: 1
    property real centerWidth: 0
    // A one-shot increase in edge light, owned by the bar's awakening.
    property real awakening: 0
    readonly property real insetLeft: Math.min(Theme.strataInset, width / 2)
    readonly property real insetRight: Math.max(insetLeft, width - Theme.strataInset)
    readonly property real insetTop: Math.min(Theme.strataInset, height / 2)
    readonly property real insetBottom: Math.max(insetTop, height - Theme.strataInset)
    readonly property real cut: Math.max(0, Math.min(Theme.strataCut, (insetRight - insetLeft) / 2, (insetBottom - insetTop) / 2))
    readonly property real center: width / 2
    readonly property real seatHalf: Math.min(Math.max(0, centerWidth) / 2, Math.max(0, (insetRight - insetLeft) / 2 - cut - 12))
    readonly property real seatLeft: center - seatHalf
    readonly property real seatRight: center + seatHalf
    readonly property real shoulder: Math.min(10, seatHalf / 3)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Foundation: no separate cards or central cutout in the material.
        ShapePath {
            strokeWidth: 0
            strokeColor: Theme.transparent
            fillGradient: LinearGradient {
                x1: 0; y1: root.insetTop; x2: 0; y2: root.insetBottom
                GradientStop { position: 0; color: Qt.alpha(Theme.strataSurface, root.materialOpacity) }
                GradientStop { position: 1; color: Qt.alpha(Theme.strataFoundation, root.materialOpacity) }
            }
            startX: root.insetLeft + root.cut; startY: root.insetTop
            PathLine { x: root.insetRight; y: root.insetTop }
            PathLine { x: root.insetRight; y: root.insetBottom - root.cut }
            PathLine { x: root.insetRight - root.cut; y: root.insetBottom }
            PathLine { x: root.insetLeft; y: root.insetBottom }
            PathLine { x: root.insetLeft; y: root.insetTop + root.cut }
            PathLine { x: root.insetLeft + root.cut; y: root.insetTop }
        }
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
            strokeColor: Qt.alpha(Theme.strataGrain, .28 + root.awakening * .12)
            fillColor: Theme.transparent
            startX: root.seatLeft - root.shoulder; startY: root.insetTop
            PathLine { x: root.insetLeft + root.cut; y: root.insetTop }
            PathLine { x: root.insetLeft; y: root.insetTop + root.cut }
            PathLine { x: root.insetLeft; y: root.insetBottom }
            PathLine { x: root.seatLeft; y: root.insetBottom }
            PathMove { x: root.seatRight + root.shoulder; y: root.insetTop }
            PathLine { x: root.insetRight; y: root.insetTop }
            PathLine { x: root.insetRight; y: root.insetBottom - root.cut }
            PathLine { x: root.insetRight - root.cut; y: root.insetBottom }
            PathLine { x: root.seatRight; y: root.insetBottom }
        }
        // Grain is a partial inner lip, never a second full contour.
        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.strataGrain, .12 + root.awakening * .08)
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
