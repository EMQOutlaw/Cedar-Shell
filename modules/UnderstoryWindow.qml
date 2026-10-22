import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

// The Understory's window: a transparent strip down the left of one output,
// below the bar, masked to the rail. The rail slides in from the screen edge
// (180 ms, Reduced Motion snaps) and back out when closed; the window unmaps
// once that is done so a closed Understory holds no surface at all.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    readonly property bool requested: Understory.shown && Understory.screen === modelData
    property bool mapped: false
    visible: mapped
    readonly property bool sliding: VisualQuality.functionalMotion && !Config.testMode
    readonly property real sideInset: Config.barDetached ? Config.barMargin : 0
    // The bar frame sits five pixels inside the bar window; the rail joins its bottom edge.
    readonly property real barJoin: Config.barHeight - (Config.barStyle === "cedar" || Config.barIslands ? 5 : 0)
    readonly property int railWidth: 388
    // Beside the Understory bar the rail is a panel in its own right: it
    // starts at the screen's top, flush to the bar's outer edge, and wears
    // the pill's cuts at both right corners instead of the fillet into the bar.
    readonly property bool beside: Config.barVertical
    readonly property real join: beside ? 0 : Theme.strataCut
    anchors { top: true; left: true; bottom: true }
    margins.top: beside ? 0 : (Config.barDetached ? Config.barMargin : 0) + barJoin
    margins.left: beside ? Config.barWidth - Theme.strataInset : sideInset
    implicitWidth: railWidth + join + 2
    color: Theme.transparent
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: rail }
    WlrLayershell.namespace: "cedar-understory"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: requested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    HyprlandFocusGrab {
        windows: [root]
        active: root.requested && !Config.testMode
        onCleared: if (root.visible) Understory.close()
    }
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: Understory.close()

    function open() {
        closeDelay.stop();
        mapped = true;
        if (!sliding) { rail.x = 0; Understory.enter(); return; }
        rail.x = -rail.width - root.join;
        Qt.callLater(() => { if (root.requested) { rail.x = 0; Understory.enter(); } });
    }
    function shut() {
        if (!sliding) { mapped = false; return; }
        rail.x = -rail.width - root.join;
        closeDelay.restart();
    }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { mapped = true; rail.x = 0; }
    Timer { id: closeDelay; interval: VisualQuality.ms(Theme.morphShrink) + 40; onTriggered: if (!root.requested) root.mapped = false }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { closeDelay.stop(); root.mapped = false; } } }

    // ---- the rail ----------------------------------------------------------
    Item {
        id: rail
        objectName: "understoryRail"
        readonly property real cut: Theme.strataCut
        readonly property real longCut: Math.round(cut * 16 / 9)
        readonly property real join: root.join
        y: 0
        width: root.railWidth
        height: root.height
        Behavior on x { enabled: root.sliding; NumberAnimation { duration: VisualQuality.ms(rail.x < 0 ? Theme.morphShrink : Theme.morphGrow); easing.type: Easing.OutCubic } }
        // Strata: the Foundation flush to the screen edge and the bar's foot,
        // the Grain two pixels inside, the Living Edge along the seam. The
        // right side leaves the bar through a concave fillet and the bottom
        // right corner carries the pill's long cut.
        Shape {
            visible: !root.beside
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0; strokeColor: "transparent"
                fillColor: Qt.alpha(Theme.strataFoundation, Math.max(.94, Config.panelOpacity))
                startX: 0; startY: -1
                PathLine { x: rail.width + rail.join; y: -1 }
                PathLine { x: rail.width + rail.join; y: 0 }
                PathArc { x: rail.width; y: rail.join; radiusX: rail.join; radiusY: rail.join; direction: PathArc.Counterclockwise }
                PathLine { x: rail.width; y: rail.height - rail.longCut }
                PathLine { x: rail.width - rail.longCut; y: rail.height }
                PathLine { x: 0; y: rail.height }
                PathLine { x: 0; y: -1 }
            }
            ShapePath {
                strokeWidth: 1; strokeColor: Qt.alpha(Theme.border, .55); fillColor: "transparent"
                startX: rail.width + rail.join - 2; startY: 2
                PathArc { x: rail.width - 2; y: rail.join + 1; radiusX: Math.max(1, rail.join - 2); radiusY: Math.max(1, rail.join - 2); direction: PathArc.Counterclockwise }
                PathLine { x: rail.width - 2; y: rail.height - rail.longCut - 1 }
                PathLine { x: rail.width - rail.longCut - 1; y: rail.height - 2 }
                PathLine { x: 2; y: rail.height - 2 }
            }
            ShapePath {
                strokeWidth: 1; fillColor: "transparent"
                strokeColor: Qt.alpha(Theme.strataAccent, .32 + .3 * (1 - Understory.ease(0, .5)))
                startX: rail.width + rail.join; startY: 0
                PathArc { x: rail.width; y: rail.join; radiusX: rail.join; radiusY: rail.join; direction: PathArc.Counterclockwise }
                PathLine { x: rail.width; y: rail.height - rail.longCut }
                PathLine { x: rail.width - rail.longCut; y: rail.height }
                PathLine { x: 0; y: rail.height }
            }
        }
        // Beside the bar: the short cut top right, the long cut bottom right, square where it meets the bar.
        Shape {
            visible: root.beside
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0; strokeColor: "transparent"
                fillColor: Qt.alpha(Theme.strataFoundation, Math.max(.94, Config.panelOpacity))
                startX: 0; startY: 0
                PathLine { x: rail.width - rail.cut; y: 0 }
                PathLine { x: rail.width; y: rail.cut }
                PathLine { x: rail.width; y: rail.height - rail.longCut }
                PathLine { x: rail.width - rail.longCut; y: rail.height }
                PathLine { x: 0; y: rail.height }
                PathLine { x: 0; y: 0 }
            }
            ShapePath {
                strokeWidth: 1; strokeColor: Qt.alpha(Theme.border, .55); fillColor: "transparent"
                startX: 2; startY: 2
                PathLine { x: rail.width - rail.cut - 1; y: 2 }
                PathLine { x: rail.width - 2; y: rail.cut + 1 }
                PathLine { x: rail.width - 2; y: rail.height - rail.longCut - 1 }
                PathLine { x: rail.width - rail.longCut - 1; y: rail.height - 2 }
                PathLine { x: 2; y: rail.height - 2 }
            }
            ShapePath {
                strokeWidth: 1; fillColor: "transparent"
                strokeColor: Qt.alpha(Theme.strataAccent, .32 + .3 * (1 - Understory.ease(0, .5)))
                startX: 0; startY: 0
                PathLine { x: rail.width - rail.cut; y: 0 }
                PathLine { x: rail.width; y: rail.cut }
                PathLine { x: rail.width; y: rail.height - rail.longCut }
                PathLine { x: rail.width - rail.longCut; y: rail.height }
                PathLine { x: 0; y: rail.height }
            }
        }
        // The pill's mark: a short lit line where the rail leaves the bar.
        Rectangle { x: rail.width - 1; y: rail.join + rail.cut + 6; width: 1; height: 34; color: Theme.green; opacity: .7 * Understory.ease(.1, .3) }
        CedarAtmosphere {
            anchors.fill: parent
            active: root.requested && Config.saved.ambientIntensity > 0
            opacity: Config.saved.ambientIntensity * .6
        }
        UnderstoryRail {
            anchors.fill: parent
            active: root.requested
            outputName: root.modelData?.name || ""
        }
    }
}
