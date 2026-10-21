import QtQuick
import QtQuick.Layouts
import Quickshell
import "installer/ui"
import "components"

// Run: qs -p installer-preview.qml
// Fixture mode never starts the installer engine or changes the desktop.
ShellRoot {
    settings.watchFiles: false
    InstallerModel {
        id: model
        fixture: true
        version: "1.15"
        facts: ({ distro: { name: "Your system" }, environment: { name: "CEDAR desktop" } })
    }
    FloatingWindow {
        id: window
        title: "CEDAR Update · Design preview"
        visible: true
        implicitWidth: 1120; implicitHeight: 770
        minimumSize: Qt.size(880, 650)
        color: Theme.background
        property bool playing: true
        property int tick: 0
        readonly property var fetchSteps: ["Find update source", "Check selected branch", "Fetch latest CEDAR", "Prepare source", "Review installer"]
        readonly property var installSteps: ["System backup", "Dependencies", "CEDAR runtime", "CEDAR shell", "Configuration", "Session", "Verification"]
        function advance() {
            const installing = tick >= fetchSteps.length;
            const step = installing ? tick - fetchSteps.length : tick;
            const titles = installing ? installSteps : fetchSteps;
            model.stage = tick >= fetchSteps.length + installSteps.length ? "finish" : installing ? "install" : "update";
            model.result = model.stage === "finish" ? { sessionState: "kept" } : {};
            model.operations = titles.map((title, i) => ({
                id: installing ? ["backup", "dependencies", "runtime", "shell", "migrate", "session", "verify"][i] : "preview-" + i,
                title: title, state: i < step ? "complete" : i === step ? "running" : "pending",
                detail: i < step ? "Complete" : i === step ? "Previewing this step…" : "", description: "", error: ""
            }));
            model.busy = model.stage !== "finish";
        }
        Component.onCompleted: advance()
        Timer {
            interval: 3200; repeat: true
            running: window.playing && model.stage !== "finish"
            onTriggered: { window.tick++; window.advance(); }
        }
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: toolbar.top }
            SystemVisual { id: visual; model: model; width: Math.round(parent.width * .44); anchors { left: parent.left; top: parent.top; bottom: parent.bottom } }
            StagePane { model: model; anchors { left: visual.right; right: parent.right; top: parent.top; bottom: parent.bottom } }
            // Keep the design preview on its scripted path, including finish actions.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        }
        Rectangle {
            id: toolbar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 50; color: Theme.surface
            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                Text { text: "DESIGN PREVIEW · Simulated progress"; color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                StationButton { text: model.prefersReducedMotion ? "Motion off" : "Motion on"; onClicked: model.prefersReducedMotion = !model.prefersReducedMotion }
                StationButton { text: window.playing ? "Pause" : "Play"; onClicked: window.playing = !window.playing }
                StationButton { text: "Replay"; onClicked: { window.tick = 0; window.advance(); window.playing = true; } }
            }
        }
    }
}
