import QtQuick
import QtQuick.Layouts
import ".."

// One protection: a label, what it is doing in plain words, who provides it,
// a status pill, and room for the control beneath. The state names come from
// Shield: on | off | warn | fail | unavailable | working. A chamfered frame in
// the Core pill's silhouette; the lit edge is the only decoration. `reveal`
// lets a page stagger cards in on its own entrance clock.
ChamferFrame {
    id: root
    property string label: ""
    property string state: "off"
    property string value: ""
    property string detail: ""
    property string reason: ""
    property bool highlighted: false
    property bool recommended: false
    property real reveal: 1
    // Interactive cards open their detail view; the frame answers hover, press and focus.
    property bool interactive: false
    signal opened()
    default property alias controls: slot.data
    readonly property color tone: state === "on" ? Theme.green : state === "warn" ? Theme.amber : state === "fail" ? Theme.ember : state === "working" ? Theme.teal : Theme.muted
    readonly property string word: ({ on: "Active", off: "Off", warn: "Check", fail: "Failed", unavailable: "Unavailable", working: "Working" })[state] || state
    readonly property bool lit: pressArea.containsMouse || activeFocus
    implicitHeight: column.implicitHeight + 32
    cut: 9
    opacity: reveal
    scale: .97 + .03 * reveal
    fill: pressArea.pressed ? Qt.alpha(Theme.elevated, .95) : lit ? Theme.elevated : Qt.alpha(Theme.surface, .85)
    stroke: activeFocus ? Theme.green : Qt.alpha(tone, pressArea.containsMouse ? .6 : state === "on" || state === "warn" || state === "fail" ? .4 : .18)
    strokeWidth: activeFocus ? Theme.focusWidth : 1
    line: state === "on" || state === "warn" || state === "fail"
    lineColor: tone
    lineFraction: .55
    Accessible.role: interactive ? Accessible.Button : Accessible.Grouping
    Accessible.name: label + ": " + value + (recommended ? ", recommended" : "")
    MouseArea { id: pressArea; anchors.fill: parent; enabled: root.interactive; hoverEnabled: root.interactive; cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: { root.forceActiveFocus(); root.opened(); } }
    Keys.onPressed: event => { if (root.interactive && (event.key === Qt.Key_Return || event.key === Qt.Key_Space)) { root.opened(); event.accepted = true; } }
    activeFocusOnTab: interactive
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            GlowText { text: root.label.toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
            GlowText { visible: root.recommended; text: "RECOMMENDED"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.teal }
            StatusPill { text: root.word; tone: root.tone }
        }
        GlowText { text: root.value; font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); font.weight: Font.DemiBold; color: root.state === "unavailable" ? Theme.muted : Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        GlowText { visible: root.detail !== ""; text: root.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        GlowText { visible: root.interactive; text: "Open →"; font.pixelSize: 10; font.letterSpacing: 1.2; color: root.lit ? root.tone : Theme.muted; Layout.alignment: Qt.AlignRight }
        GlowText { visible: root.reason !== ""; text: root.reason; font.pixelSize: Theme.small; color: root.state === "fail" ? Theme.ember : Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        ColumnLayout { id: slot; Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8 }
    }
}
