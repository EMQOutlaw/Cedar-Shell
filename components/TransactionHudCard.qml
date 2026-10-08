import QtQuick
import QtQuick.Layouts
import ".."

// The preparation card for any transaction: a title in the pill's language,
// a heading, a progress filament that lights from the left as providers
// verify, one instrument row per step with a diamond marker and a
// spaced-capital state word, and a readout of what is ready. Gaming Mode,
// Desktop Profiles and Focus hand it their rows and words; it has no timers,
// no polling and no loops. The entrance (opacity 0 → 1, scale .96 → 1), the
// row stagger, the emblem's single pulse and the completion sweep are
// one-shot functional transitions gated on the user's Reduced Motion
// preference. Afterwards it is still.
Item {
    id: root
    property string title: "CEDAR"
    property var steps: []
    property bool settled: false
    property bool closing: false
    property bool leave: false
    property string heading: ""
    property string subtitle: ""        // a game's name, a profile's line; shown while not settled
    property string footer: ""
    property string count: ""
    property string countWord: ""
    property int failed: 0
    property real progress: 0
    property color accent: Theme.teal
    // Step ids whose "unavailable" means a provider is not installed rather than not available here.
    property var notInstalledIds: []
    implicitWidth: 480
    implicitHeight: frame.height + 14
    readonly property bool functional: !Config.saved.reducedMotion
    readonly property var rows: steps.filter(s => s.state !== "off")
    // The row delegates are keyed by step id and built once: a JS array model
    // that is reassigned on every state change would rebuild every row and
    // restart its entrance, so the ids only change when the set changes.
    property var rowIds: []
    function syncRows() { const ids = steps.filter(s => s.state !== "off").map(s => s.id); if (ids.join() !== rowIds.join()) rowIds = ids; }
    function rowFor(id) { return steps.find(s => s.id === id) || { id: id, hud: id, state: "pending", detail: "" }; }
    onStepsChanged: syncRows()
    readonly property real scaleFactor: Theme.fontScale
    property bool entered: false
    readonly property bool shown: entered && !closing
    opacity: shown ? 1 : 0
    scale: shown ? 1 : (entered ? .98 : .96)
    Behavior on opacity { enabled: root.functional; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on scale { enabled: root.functional; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: { syncRows(); Qt.callLater(() => root.entered = true); }
    onSettledChanged: if (settled) sweep.restart()
    onHeadingChanged: if (functional) headingFade.restart()

    function glyph(state) { return ({ pending: "○", applying: "◌", active: "✓", restored: "✓", failed: "!", unavailable: "–", observing: "◦" })[state] || "○"; }
    function tone(state) {
        return state === "active" || state === "restored" ? Theme.success : state === "applying" || state === "observing" ? Theme.teal
            : state === "failed" ? Theme.warning : Theme.inactive;
    }
    function word(row) {
        switch (row.state) {
        case "pending": return "WAITING";
        case "applying": return root.leave ? "RESTORING" : "APPLYING";
        case "active": return "READY";
        case "restored": return "RESTORED";
        case "failed": return root.leave ? "COULD NOT RESTORE" : "COULD NOT APPLY";
        case "unavailable": return root.notInstalledIds.includes(row.id) ? "NOT INSTALLED" : "NOT AVAILABLE";
        case "observing": return "WATCHING";
        }
        return "";
    }
    function aside(row) {
        if (row.state === "unavailable") return root.notInstalledIds.includes(row.id) ? "Not installed" : "Not available";
        if (row.state === "failed") return root.leave ? "Could not restore" : "Could not apply";
        if (row.state === "observing") return "Watching";
        return "";
    }
    function label(row) { return row.hud; }   // the state word beside the row says RESTORED; the name stays the name

    // Soft shadow: the same silhouette, a little larger and darker, no effects.
    ChamferFrame { anchors.fill: frame; anchors.margins: -6; cut: 15; fill: Qt.alpha(Theme.background, .42); stroke: Theme.transparent; strokeWidth: 0 }
    ChamferFrame {
        id: frame
        width: root.width; height: column.implicitHeight + 52
        cut: 14
        fill: Qt.alpha(Theme.surface, .965)
        stroke: Qt.alpha(root.accent, root.settled ? .55 : .3)
        line: true; lineColor: root.accent; lineFraction: root.settled ? .62 : .38; lineOpacity: root.settled ? .95 : .55
        Behavior on stroke { enabled: root.functional; ColorAnimation { duration: Theme.transition } }
        Behavior on lineFraction { enabled: root.functional; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        // The station's faint scan grid, painted once.
        Canvas {
            anchors.fill: parent; anchors.margins: 10
            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset(); c.strokeStyle = Theme.grid; c.lineWidth = 1;
                for (let y = 6; y < height; y += 6) { c.beginPath(); c.moveTo(0, y + .5); c.lineTo(width, y + .5); c.stroke(); }
            }
        }
        // The pill's short lit line at the top edge, and the completion sweep that runs along it once.
        Rectangle { x: frame.cut + 2; y: 0; width: 42; height: 2; color: root.accent; opacity: .9 }
        Rectangle {
            id: topSweep
            x: frame.cut + 2; y: 0; height: 1; width: 0; color: root.accent; opacity: .85
            NumberAnimation { id: sweep; target: topSweep; property: "width"; from: 0; to: frame.width - frame.cut - frame.longCut - 4; duration: root.functional ? 480 : 0; easing.type: Easing.OutCubic }
        }
        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 26 }
            spacing: 0
            // Title: emblem, spaced capitals, a filament either side.
            RowLayout {
                Layout.fillWidth: true; spacing: 14
                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.accent, .35) }
                Item {
                    id: emblem
                    implicitWidth: 22; implicitHeight: 22
                    Rectangle { anchors.centerIn: parent; width: 15; height: 15; rotation: 45; radius: 2; color: Qt.alpha(root.accent, .1); border.width: 1.5; border.color: root.accent }
                    Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: root.accent }
                    SequentialAnimation { id: pulse; running: root.functional && root.entered; NumberAnimation { target: emblem; property: "scale"; to: 1.3; duration: 160; easing.type: Easing.OutCubic } NumberAnimation { target: emblem; property: "scale"; to: 1; duration: 240; easing.type: Easing.OutCubic } }
                }
                Text { text: root.title; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * root.scaleFactor); font.weight: Font.DemiBold; font.letterSpacing: 4; color: root.accent }
                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.accent, .35) }
            }
            GlowText {
                id: headingText
                Layout.fillWidth: true; Layout.topMargin: 18
                text: root.heading; horizontalAlignment: Text.AlignHCenter; glow: true
                font.family: Theme.labelFont; font.pixelSize: Math.round(28 * root.scaleFactor); font.weight: Font.Bold
                color: Theme.text; elide: Text.ElideRight
                NumberAnimation { id: headingFade; target: headingText; property: "opacity"; from: .3; to: 1; duration: 180; easing.type: Easing.OutCubic }
            }
            GlowText {
                visible: root.subtitle !== "" && !root.settled
                Layout.fillWidth: true; Layout.topMargin: 2
                text: root.subtitle; horizontalAlignment: Text.AlignHCenter
                font.family: Theme.labelFont; font.pixelSize: Math.round(20 * root.scaleFactor); color: Theme.teal; elide: Text.ElideRight
            }
            // Progress filament: lit from the left as providers verify, a lantern at its head.
            Item {
                Layout.fillWidth: true; Layout.topMargin: 14; Layout.leftMargin: 6; Layout.rightMargin: 6
                implicitHeight: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Qt.alpha(Theme.teal, .18) }
                Rectangle {
                    id: lit
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(parent.width * root.progress); height: 2; radius: 1; color: root.accent
                    Behavior on width { enabled: root.functional; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: parent.width - 3; width: 6; height: 6; radius: 3; color: root.accent; visible: lit.width > 0 }
                }
            }
            // Instrument rows.
            ColumnLayout {
                Layout.fillWidth: true; Layout.topMargin: 16; Layout.leftMargin: 6; Layout.rightMargin: 6
                spacing: 0
                Repeater {
                    model: root.rowIds
                    Item {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property var step: root.rowFor(modelData)
                        readonly property color tone: root.tone(step.state)
                        readonly property bool done: step.state === "active" || step.state === "restored"
                        readonly property bool quiet: step.state === "unavailable" || step.state === "pending"
                        Layout.fillWidth: true; implicitHeight: 34
                        opacity: root.functional ? 0 : 1
                        Component.onCompleted: if (root.functional) reveal.start()
                        SequentialAnimation { id: reveal; PauseAnimation { duration: 60 + row.index * 45 } NumberAnimation { target: row; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic } }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(Theme.teal, .09); visible: row.index < root.rowIds.length - 1 }
                        // Marker: a diamond that fills as the row is verified.
                        Item {
                            id: marker
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18
                            Rectangle {
                                anchors.centerIn: parent; width: 11; height: 11; rotation: 45; radius: 1.5
                                color: row.done || row.step.state === "failed" ? row.tone : Qt.alpha(row.tone, row.step.state === "applying" ? .18 : 0)
                                border.width: 1.2; border.color: row.tone
                                Behavior on color { enabled: root.functional; ColorAnimation { duration: 160 } }
                                Behavior on border.color { enabled: root.functional; ColorAnimation { duration: 160 } }
                            }
                            Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 1.5; color: row.tone; visible: row.step.state === "applying" || row.step.state === "observing" }
                            Text { anchors.centerIn: parent; visible: row.step.state === "failed"; text: "!"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.bold: true; color: Theme.surface }
                        }
                        GlowText {
                            anchors { left: marker.right; leftMargin: 14; right: state.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: root.label(row.step); elide: Text.ElideRight
                            font.family: Theme.labelFont; font.pixelSize: Math.round(17 * root.scaleFactor); font.weight: row.done ? Font.DemiBold : Font.Normal
                            color: row.quiet ? Theme.muted : Theme.text
                            Behavior on color { enabled: root.functional; ColorAnimation { duration: 160 } }
                        }
                        Text {
                            id: state
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            text: root.word(row.step); textFormat: Text.PlainText
                            font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.6; color: row.tone; opacity: row.quiet ? .7 : 1
                            Behavior on color { enabled: root.functional; ColorAnimation { duration: 160 } }
                        }
                    }
                }
            }
            // Readout: the count large in the data face, the state word beside it.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 18; spacing: 12
                Text {
                    visible: !root.settled || root.failed > 0
                    text: root.count; textFormat: Text.PlainText
                    font.family: Theme.dataFont; font.pixelSize: Math.round(22 * root.scaleFactor); color: root.accent
                }
                Text {
                    text: root.countWord; textFormat: Text.PlainText
                    font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 2.4
                    color: root.settled ? root.accent : Theme.muted
                    Behavior on color { enabled: root.functional; ColorAnimation { duration: Theme.transition } }
                }
            }
        }
    }
}
