import QtQuick
import QtQuick.Layouts
import "../.."
import "../../components"

// The strong visual object on the left: your system as a card, with the
// desktop as layers. The current desktop is the base layer; a protected
// backup layer appears when the backup is made; a cedar-green layer settles
// over the system as installation progresses; check marks appear at
// verification; then everything is still. One sweep during the scan, one
// per transition, no loops.
Item {
    id: root
    property var model
    readonly property var facts: model.facts || ({})
    readonly property string stage: model.stage
    readonly property bool installing: stage === "install"
    readonly property bool finished: stage === "finish"
    readonly property bool motion: model.motion
    function state(id) { const op = (model.operations || []).find(o => o.id === id); return op ? op.state : "pending"; }
    function done(id) { return ["complete", "warning", "skipped"].includes(state(id)); }
    readonly property bool backedUp: done("backup") || finished
    readonly property real cedarFill: finished ? 1 : installing ? Math.max(0.06, model.progress) : 0
    readonly property bool verified: done("verify") || finished
    readonly property string distro: facts.distro ? facts.distro.name : "Your system"
    readonly property string gpu: facts.gpu ? facts.gpu.vendor + (facts.gpu.driver && facts.gpu.driver !== "unknown" ? " · " + facts.gpu.driver : "") : ""
    readonly property string compositor: facts.compositor && facts.compositor.name ? facts.compositor.name.charAt(0).toUpperCase() + facts.compositor.name.slice(1) + (facts.hyprlandVersion ? " " + facts.hyprlandVersion : "") : ""
    readonly property string storage: facts.disk && facts.disk.total ? (facts.disk.total / 1024 / 1024 / 1024 / 1024 >= 1 ? (facts.disk.total / 1024 / 1024 / 1024 / 1024).toFixed(1) + " TB" : Math.round(facts.disk.total / 1024 / 1024 / 1024) + " GB") + " · " + Math.round(facts.disk.free / 1024 / 1024 / 1024) + " GB free" : ""
    readonly property string environmentName: model.environment.name || "Current desktop"
    readonly property string version: model.version || facts.cedarVersion || ""

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.surface, .35) }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .1) }

    Item {
        id: object
        anchors.centerIn: parent
        width: Math.min(360, parent.width - 72); height: Math.min(460, parent.height - 96)
        Frame { anchors.fill: parent; cut: 18; fill: Qt.alpha(Theme.background, .7); stroke: Qt.alpha(root.finished ? Theme.green : Theme.teal, root.finished ? .55 : .25); line: root.finished; lineColor: Theme.green; lineFraction: .5 }
        // Scan sweep: one thin cedar line through the system while scanning.
        Rectangle {
            id: sweep
            x: 20; width: parent.width - 40; height: 1; color: Theme.teal; opacity: 0
            NumberAnimation { id: sweepMove; target: sweep; property: "y"; from: 24; to: object.height - 24; duration: root.motion ? 900 : 0; easing.type: Easing.InOutQuad }
            SequentialAnimation { id: sweepFade; NumberAnimation { target: sweep; property: "opacity"; to: .9; duration: 120 } PauseAnimation { duration: root.motion ? 660 : 0 } NumberAnimation { target: sweep; property: "opacity"; to: 0; duration: 180 } }
        }
        Connections { target: root.model; function onStageEntered(name) { if (name === "scan") { sweepMove.restart(); sweepFade.restart(); } } }
        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 6
            SectionMark { text: "SYSTEM"; tone: Theme.teal }
            GlowText { Layout.fillWidth: true; Layout.topMargin: 14; text: root.distro; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight; glow: true }
            GlowText { Layout.fillWidth: true; visible: root.compositor !== "" || root.gpu !== ""; text: [root.compositor, root.gpu].filter(s => s).join("   ·   "); font.pixelSize: Theme.small; color: Theme.muted; elide: Text.ElideRight }
            GlowText { Layout.fillWidth: true; visible: root.storage !== ""; text: root.storage; font.pixelSize: Theme.small; color: Theme.muted }
        }
        // Layers: current desktop, backup, CEDAR.
        ColumnLayout {
            id: layers
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 }
            spacing: 10
            Item {
                id: cedarLayer
                Layout.fillWidth: true; implicitHeight: 54
                Rectangle { anchors.fill: parent; radius: Theme.controlRadius; color: Qt.alpha(Theme.green, .05); border.color: Qt.alpha(Theme.green, root.cedarFill > 0 ? .4 : .14); Behavior on border.color { enabled: root.motion; ColorAnimation { duration: Theme.transition } } }
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * root.cedarFill; radius: Theme.controlRadius; color: Qt.alpha(Theme.green, .22)
                    Behavior on width { enabled: root.motion; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    GlowText { text: "CEDAR" + (root.version ? " " + root.version : ""); font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); font.weight: Font.DemiBold; color: root.cedarFill > 0 ? Theme.green : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { visible: root.installing && !root.finished; text: Math.round(root.model.progress * 100) + "%"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 12; color: Theme.green }
                    Text { visible: root.verified; text: "✓"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 14; color: Theme.green }
                }
            }
            Item {
                id: backupLayer
                Layout.fillWidth: true; implicitHeight: root.backedUp ? 34 : 0; clip: true; opacity: root.backedUp ? 1 : 0
                Behavior on implicitHeight { enabled: root.motion; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: root.motion; NumberAnimation { duration: 240 } }
                Rectangle { anchors.fill: parent; radius: Theme.controlRadius; color: Qt.alpha(Theme.teal, .05); border.color: Qt.alpha(Theme.teal, .35) }
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    GlowText { text: "Backup"; font.pixelSize: Theme.small; color: Theme.teal; Layout.fillWidth: true }
                    Text { text: "PROTECTED"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.4; color: Theme.teal }
                }
            }
            Item {
                Layout.fillWidth: true; implicitHeight: 54
                Rectangle { anchors.fill: parent; radius: Theme.controlRadius; color: Qt.alpha(Theme.muted, .05); border.color: Qt.alpha(Theme.muted, .25) }
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        GlowText { text: root.environmentName; font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        GlowText { text: root.model.environment.stack || "Current desktop"; font.pixelSize: 11; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    Text { visible: root.verified; text: "✓"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 14; color: Theme.green }
                    Text { visible: !root.verified; text: root.installing || root.finished ? "KEPT" : "CURRENT"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.4; color: Theme.muted }
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 10
                text: root.finished ? "CEDAR READY" : root.installing ? "INSTALLING" : root.stage === "scan" ? "SCANNING" : root.stage === "error" ? "STOPPED" : root.stage === "restored" ? "RESTORED" : root.stage === "interrupted" ? "INTERRUPTED" : root.stage === "attention" ? "NEEDS ATTENTION" : "CEDAR READY TO INSTALL"
                textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 2.2
                color: root.finished ? Theme.green : root.stage === "error" || root.stage === "attention" ? Theme.amber : Theme.muted
            }
        }
    }
}
