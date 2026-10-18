import QtQuick
import ".."

// The Field Notes toolbar: one row or one column of tools docked to a side of
// the paper, on the pill's chamfered frame with its lit top edge. Every cell
// has the same size along the toolbar in both orientations, so its length does
// not change when it is docked to another side.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Item {
    id: root

    property string currentTool: "pen"
    property bool canUndo: false
    property bool canRedo: false
    property bool hasContent: false
    property bool clearArmed: false
    property real penWidth: 2.5
    property int sheetIndex: 0
    property int sheetCount: 1
    property bool canAddSheet: true
    // Paper side the toolbar is docked to; top and bottom lay it out horizontally.
    property string side: "right"
    property QtObject theme
    readonly property bool horizontal: side === "top" || side === "bottom"
    // Tooltips open toward the paper, where the board always has room for them.
    readonly property string tooltipSide: side === "right" ? "left"
        : side === "left" ? "right"
        : side === "top" ? "bottom" : "top"
    readonly property bool lastSheet: sheetIndex >= sheetCount - 1
    // Result of the last image export, shown on its button for a moment: "", "copied" or "failed".
    property string exportState: ""
    // What Ctrl+C puts on the clipboard: "path" or "image" (a setting).
    property string copyMode: "path"
    property string exportedMode: "path"
    // Faded away while the notes don't have keyboard focus (the board decides).
    // Pointing at the toolbar or holding its grip brings it straight back.
    property bool faded: false
    readonly property bool hovered: islandHover.hovered
    readonly property var penWidths: [1.5, 2.5, 4, 7]

    opacity: faded && !hovered && !gripDrag.active ? 0 : 1

    // Slow to leave, quick to return.
    Behavior on opacity {
        enabled: !Theme.reducedMotion
        NumberAnimation {
            duration: root.opacity > 0.5 ? Theme.sweep : Theme.transition
            easing.type: Easing.InOutQuad
        }
    }

    HoverHandler {
        id: islandHover
    }
    signal toolSelected(string tool)
    signal undoRequested()
    signal redoRequested()
    signal clearRequested()
    signal penWidthRequested(real width)
    signal sheetRequested(int index)
    signal newSheetRequested()
    signal copyImageRequested()
    signal settingsRequested()
    signal closeRequested()
    // Grip drag in scene coordinates; the board decides where the toolbar docks.
    signal gripMoved(real sceneX, real sceneY)
    signal gripReleased()

    // mode: what was copied, "path" or "image" (Ctrl+Shift+C copies the other one).
    function exportFinished(ok, mode) {
        exportedMode = mode || copyMode
        exportState = ok ? "copied" : "failed"
        exportTimer.restart()
    }

    function nextPenWidth() {
        for (var i = 0; i < penWidths.length; i++) {
            if (penWidths[i] > penWidth + 0.01)
                return penWidths[i]
        }
        return penWidths[0]
    }

    implicitWidth: grid.implicitWidth + 12
    implicitHeight: grid.implicitHeight + 12

    onHasContentChanged: {
        if (!hasContent)
            clearArmed = false
    }

    // One-shots: the export word dwells like an OSD; an armed Clear disarms itself.
    Timer {
        id: exportTimer
        interval: Theme.osdDuration
        onTriggered: root.exportState = ""
    }

    Timer {
        id: clearTimer
        interval: 2500
        onTriggered: root.clearArmed = false
    }

    // Shadow, then the frame. Siblings of the grid so nothing clips the tooltips.
    Rectangle {
        x: 3; y: 8
        width: parent.width; height: parent.height
        radius: root.theme.radius
        color: root.theme.shadowSoft
    }
    ChamferFrame {
        anchors.fill: parent
        cut: root.theme.cut * .75
        fill: root.theme.background
        stroke: root.theme.border
        topLine: true
    }

    component Divider: Item {
        width: root.horizontal ? 9 : 40
        height: root.horizontal ? 40 : 9

        Rectangle {
            anchors.centerIn: parent
            width: root.horizontal ? 1 : 18
            height: root.horizontal ? 18 : 1
            color: root.theme.divider
        }
    }

    component Button: NotesToolButton {
        theme: root.theme
        tooltipSide: root.tooltipSide
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        // One row when horizontal, one column when vertical.
        columns: root.horizontal ? children.length : 1
        spacing: 2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Item {
            id: grip

            width: root.horizontal ? 16 : 40
            height: root.horizontal ? 40 : 16

            Accessible.role: Accessible.Grip
            Accessible.name: "Drag to dock the toolbar"

            Repeater {
                model: 2

                Rectangle {
                    required property int index
                    x: root.horizontal ? (grip.width - 5) / 2 + index * 4 : (grip.width - 16) / 2
                    y: root.horizontal ? (grip.height - 16) / 2 : (grip.height - 5) / 2 + index * 4
                    width: root.horizontal ? 1 : 16
                    height: root.horizontal ? 16 : 1
                    color: gripHover.hovered || gripDrag.active ? root.theme.hoverIcon : root.theme.subtle
                }
            }

            HoverHandler {
                id: gripHover

                cursorShape: Qt.OpenHandCursor
            }

            DragHandler {
                id: gripDrag

                target: null
                cursorShape: Qt.ClosedHandCursor
                onCentroidChanged: {
                    if (active)
                        root.gripMoved(centroid.scenePosition.x, centroid.scenePosition.y)
                }
                onActiveChanged: {
                    if (!active)
                        root.gripReleased()
                }
            }
        }

        Button {
            text: "Select"
            icon: "󰆿"
            fallback: "SEL"
            shortcut: "V"
            selected: root.currentTool === "select"
            onActivated: root.toolSelected("select")
        }
        Button {
            text: "Pen"
            icon: "󰲶"
            fallback: "PEN"
            shortcut: "P"
            selected: root.currentTool === "pen"
            onActivated: root.toolSelected("pen")
        }
        Button {
            text: "Erase"
            icon: "󰇾"
            fallback: "ERS"
            shortcut: "E"
            selected: root.currentTool === "eraser"
            onActivated: root.toolSelected("eraser")
        }
        Button {
            text: "Text"
            icon: "󰊄"
            fallback: "TXT"
            shortcut: "T"
            selected: root.currentTool === "text"
            onActivated: root.toolSelected("text")
        }

        Divider {}

        Button {
            text: "Undo"
            icon: "󰕌"
            fallback: "↶"
            shortcut: "Ctrl+Z"
            enabled: root.canUndo
            onActivated: root.undoRequested()
        }
        Button {
            text: "Redo"
            icon: "󰑎"
            fallback: "↷"
            shortcut: "Ctrl+Y"
            enabled: root.canRedo
            onActivated: root.redoRequested()
        }

        Divider {}

        Button {
            text: "Previous sheet"
            icon: "󰅁"
            fallback: "‹"
            shortcut: "PgUp"
            enabled: root.sheetIndex > 0
            onActivated: root.sheetRequested(root.sheetIndex - 1)
        }
        Item {
            width: root.horizontal ? 34 : 40
            height: root.horizontal ? 40 : 34

            Text {
                anchors.centerIn: parent
                text: (root.sheetIndex + 1) + "/" + root.sheetCount
                color: root.theme.subtle
                font.family: Theme.dataFont
                font.pixelSize: 10
                font.letterSpacing: 1
                textFormat: Text.PlainText
            }
        }
        // On the last sheet, "next" becomes "new sheet".
        Button {
            text: root.lastSheet ? "New sheet" : "Next sheet"
            icon: root.lastSheet ? "󰐕" : "󰅂"
            fallback: root.lastSheet ? "+" : "›"
            shortcut: root.lastSheet ? "N" : "PgDn"
            enabled: !root.lastSheet || root.canAddSheet
            onActivated: {
                if (root.lastSheet)
                    root.newSheetRequested()
                else
                    root.sheetRequested(root.sheetIndex + 1)
            }
        }

        Divider {}

        Button {
            text: "Width " + root.penWidth.toFixed(1)
            dotSize: Math.min(16, 3 + root.penWidth * 1.3)
            shortcut: "[ ]"
            onActivated: root.penWidthRequested(root.nextPenWidth())
        }
        Button {
            text: root.exportState === "copied" ? (root.exportedMode === "image" ? "Image copied" : "Image path copied")
                : root.exportState === "failed" ? "Couldn't save the image"
                : root.copyMode === "image" ? "Copy image" : "Copy image path"
            icon: root.exportState === "copied" ? "󰄬" : "󰆏"
            fallback: root.exportState === "copied" ? "OK" : "CPY"
            shortcut: root.exportState === "" ? "Ctrl+C" : ""
            selected: root.exportState !== ""
            dangerous: root.exportState === "failed"
            forceTooltip: root.exportState !== ""
            onActivated: root.copyImageRequested()
        }
        Button {
            text: root.clearArmed ? "Click again to clear" : "Clear sheet"
            icon: "󰧧"
            fallback: "CLR"
            dangerous: true
            selected: root.clearArmed
            forceTooltip: root.clearArmed
            enabled: root.hasContent
            onActivated: {
                if (root.clearArmed) {
                    root.clearArmed = false
                    clearTimer.stop()
                    root.clearRequested()
                } else {
                    root.clearArmed = true
                    clearTimer.restart()
                }
            }
        }
        Button {
            text: "Field Notes settings"
            icon: "󰢻"
            fallback: "SET"
            shortcut: "Ctrl+,"
            onActivated: root.settingsRequested()
        }
        Button {
            text: "Close"
            icon: "󰅖"
            fallback: "×"
            shortcut: "Esc"
            onActivated: root.closeRequested()
        }
    }
}
