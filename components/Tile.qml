import QtQuick
import QtQuick.Layouts
import ".."

// The quick-control tile: a state button with a mark, a label, a live value
// and a lit edge while on. Extracted from QuickControls so every surface
// (the drop, the rail, new postures like the Thicket) shares the one tile.
// Entrance is the caller's: pass `sweep` from a reveal clock (beat()).
StrataButton {
    id: tile
    property string mark: ""
    property string label: ""
    property string value: ""
    property bool on: false
    property real order: 0
    property real sweep: 1
    Layout.fillWidth: true; Layout.preferredWidth: 1
    implicitHeight: 60
    padding: 12
    opacity: sweep
    scale: .94 + .06 * sweep
    checked: on
    Accessible.name: label + ": " + value
    background: ChamferFrame {
        cut: Theme.strataCut
        fill: tile.on ? Qt.alpha(Theme.strataAccent, .06) : Qt.alpha(Theme.strataFoundation, .6)
        stroke: tile.visualFocus ? Theme.strataAccent : tile.on ? Qt.alpha(Theme.strataAccent, .45) : tile.hovered ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .14)
        strokeWidth: tile.visualFocus ? 2 : 1
        line: tile.on; lineColor: Theme.strataAccent; lineFraction: .6
    }
    contentItem: ColumnLayout {
        spacing: 3
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Text { visible: tile.mark !== ""; text: tile.mark; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 15; color: tile.on ? Theme.strataAccent : Theme.strataMuted }
            Text { Layout.fillWidth: true; text: tile.label; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); color: tile.on ? Theme.strataAccent : Theme.strataText; elide: Text.ElideRight }
            Rectangle { width: 5; height: 5; radius: 3; color: tile.on ? Theme.strataAccent : Theme.strataMuted; opacity: tile.on ? 1 : .5; Layout.alignment: Qt.AlignVCenter }
        }
        KineticLabel { Layout.fillWidth: true; height: implicitHeight; text: tile.value; transitionStyle: "resolve"; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted; elide: Text.ElideRight }
    }
}
