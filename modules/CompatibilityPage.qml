import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    spacing: 16
    property bool diagnostics: false
    property bool showHistory: false
    property string confirming: ""
    property string migration: ""
    Component.onCompleted: Compatibility.refresh()
    GlowText { text: "DESKTOP ENVIRONMENT"; font.family: Theme.labelFont; font.pixelSize: 22; color: Theme.text }
    GlowText { text: "Switch the shell. Keep your Hyprland configuration."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    ChamferFrame {
        Layout.fillWidth: true; implicitHeight: summary.implicitHeight + 32
        fill: Qt.alpha(Theme.surface, .88); stroke: Qt.alpha(Theme.teal, .3); cut: 10
        ColumnLayout {
            id: summary; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            GlowText { text: "Current shell: " + (Compatibility.status.health?.healthy ? "CEDAR" : Compatibility.detection.activeShells.join(", ") || "Unknown"); color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { text: "Hyprland: " + (Compatibility.detection.compositor.active ? "Active" : "Not verified") + " · Startup: " + (Compatibility.status.login ? "CEDAR enabled" : "Existing startup preserved"); color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { text: Compatibility.status.health?.healthy ? "Shell IPC and desktop health verified" : Compatibility.status.health?.reason || "Reading desktop health…"; color: Compatibility.status.health?.healthy ? Theme.success : Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Repeater {
                model: Compatibility.detection.matches || []
                GlowText { required property var modelData; text: modelData.name + " · " + modelData.compatibility + " · " + Object.keys(modelData.states).filter(k => modelData.states[k]).join(", "); font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
    Flow {
        Layout.fillWidth: true; spacing: 8
        StationButton { text: Compatibility.options.login ? "Startup: at login" : "Startup: this session"; enabled: !Compatibility.busy; onClicked: { Compatibility.setOption("bindings", false); Compatibility.setOption("trailwatch", false); Compatibility.setOption("login", !Compatibility.options.login); } }
        StationButton { text: Compatibility.options.bindings ? "Free shortcuts: include" : "Shortcuts: preserve"; enabled: !Compatibility.busy; onClicked: { Compatibility.setOption("login", false); Compatibility.setOption("trailwatch", false); Compatibility.setOption("bindings", !Compatibility.options.bindings); } }
    }
    Flow {
        Layout.fillWidth: true; spacing: 8
        StationButton { text: "Refresh"; enabled: !Compatibility.busy; onClicked: Compatibility.refresh() }
        StationButton { text: "Preview migration"; enabled: !Compatibility.busy; onClicked: { root.confirming = ""; Compatibility.preview(); } }
        StationButton { text: "Restore original shell"; enabled: !Compatibility.busy && Compatibility.status.stage !== "not active"; onClicked: { root.migration = ""; root.confirming = "rollback"; } }
        StationButton { text: "Repair CEDAR"; enabled: !Compatibility.busy && Compatibility.status.stage === "kept"; onClicked: root.confirming = "restart" }
        StationButton { text: "Migration history"; onClicked: root.showHistory = !root.showHistory }
        StationButton { text: root.diagnostics ? "Hide diagnostics" : "Diagnostics & conflicts"; onClicked: root.diagnostics = !root.diagnostics }
    }
    GlowText { visible: Compatibility.busy; text: "Inspecting desktop evidence…"; color: Theme.muted }
    GlowText { visible: Compatibility.error !== ""; text: Compatibility.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    GlowText { visible: Compatibility.message !== ""; text: Compatibility.message; color: Theme.teal; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    ColumnLayout {
        visible: Compatibility.plan !== null; Layout.fillWidth: true; spacing: 8
        GlowText { text: "MIGRATION PREVIEW"; color: Theme.teal }
        Repeater {
            model: Compatibility.plan?.actions || []
            GlowText { required property var modelData; text: modelData.classification + " · " + modelData.target + "\n" + modelData.description; color: modelData.classification === "Requires manual intervention" ? Theme.warning : Theme.text; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        StationButton { text: "Apply reviewed migration"; enabled: !Compatibility.busy && Compatibility.plan !== null && Compatibility.plan.blocked.length === 0; onClicked: root.confirming = "migrate" }
    }
    ColumnLayout {
        visible: root.confirming !== ""; Layout.fillWidth: true
        GlowText { text: root.confirming === "rollback" ? "Restore the recorded original shell? Later edits will be preserved or reported as conflicts." : root.confirming === "restart" ? "Restart the managed CEDAR shell and recheck its health? No configuration reset." : "Apply this exact preview? The terminal remains open for authentication and recovery messages."; color: Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        RowLayout {
            StationButton { text: "Confirm"; enabled: !Compatibility.busy; onClicked: { Compatibility.run(root.confirming, root.migration); root.confirming = ""; } }
            StationButton { text: "Cancel"; onClicked: root.confirming = "" }
        }
    }
    ColumnLayout {
        visible: root.showHistory; Layout.fillWidth: true
        GlowText { text: "BACKUPS & MIGRATION HISTORY"; color: Theme.teal }
        GlowText { visible: (Compatibility.status.history || []).length === 0; text: "No compatibility migrations recorded. Older sessions retain their own recovery journals."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Repeater {
            model: Compatibility.status.history || []
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                GlowText { text: modelData.id + " · " + modelData.stage; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: modelData.error !== ""; text: modelData.error; color: Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                StationButton { text: "Review restoration"; enabled: modelData.stage !== "restored" && !Compatibility.busy; onClicked: { root.migration = modelData.id; root.confirming = "rollback"; } }
            }
        }
    }
    ColumnLayout {
        visible: root.diagnostics; Layout.fillWidth: true
        GlowText { text: "DEPENDENCIES & OWNERSHIP"; color: Theme.teal }
        Repeater { model: Compatibility.detection.dependencies || []; GlowText { required property var modelData; text: modelData.command + ": " + (modelData.available ? "available" : "missing"); color: modelData.available ? Theme.muted : Theme.warning } }
        GlowText { text: "Occupied shortcuts preserve the existing action. Reassign CEDAR action IDs below, or use null to skip an action. Example: {\"launcher\": \"SUPER + ALT + L\", \"terminal\": null}. Super+C/X/V remain application-local."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        TextArea { id: assignments; Layout.fillWidth: true; implicitHeight: 90; text: "{}"; color: Theme.text; selectByMouse: true; wrapMode: TextEdit.Wrap; background: Rectangle { color: Theme.surface } }
        StationButton { text: "Preview shortcut choices"; enabled: !Compatibility.busy; onClicked: { Compatibility.setOption("login", false); Compatibility.setOption("trailwatch", false); Compatibility.assign(assignments.text); } }
        GlowText { text: "If restoration reports edited files, compare the private journal with your current configuration. CEDAR never resolves that conflict by overwriting your changes."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        TextArea { Layout.fillWidth: true; implicitHeight: 260; readOnly: true; wrapMode: TextEdit.Wrap; text: JSON.stringify({evidence: Compatibility.detection, preview: Compatibility.plan, history: Compatibility.status.history}, null, 2); color: Theme.text; font.pixelSize: 11; selectByMouse: true; background: Rectangle { color: Theme.surface } }
    }
}
