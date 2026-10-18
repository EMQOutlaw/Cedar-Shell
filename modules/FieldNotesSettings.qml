import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings › Field Notes: what the notebook is doing now, the actions that have
// no place on the paper, and the preferences from the schema.
ColumnLayout {
    id: root
    property string highlightKey: ""
    readonly property string savedWord: ({ SAVED: "Saved", EDITED: "Saving", READY: "Ready", LOADING: "Loading", RECOVERED: "Recovered", "NOT SAVED": "Not saved", UNLOADED: "Not loaded" })[FieldNotes.saveStatus] || FieldNotes.saveStatus
    function tilde(path) { return Config.home && path.indexOf(Config.home) === 0 ? "~" + path.slice(Config.home.length) : path; }
    spacing: 16

    GridLayout {
        Layout.fillWidth: true; columns: root.width < 600 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
        Readout {
            label: "Notes"; lit: FieldNotes.opened
            value: FieldNotes.opened ? "Open" : FieldNotes.loaded ? "Put away" : "Not loaded"
            detail: FieldNotes.opened ? "On " + (FieldNotes.screenName || "the focused display") + "." : "Super+Alt+N, the bar button or Applications opens them."
        }
        Readout {
            label: "Sheets"; lit: FieldNotes.sheets > 0; tone: Theme.teal
            value: FieldNotes.loaded ? FieldNotes.sheets + (FieldNotes.sheets === 1 ? " sheet" : " sheets") : "—"
            detail: FieldNotes.loaded ? "Sheet " + FieldNotes.sheet + " is open. A blank sheet is dropped when you leave it." : "The notebook loads with the shell."
        }
        Readout {
            label: "Saved"; lit: FieldNotes.saveStatus === "SAVED"; tone: FieldNotes.saveStatus === "NOT SAVED" ? Theme.amber : Theme.green
            value: root.savedWord
            detail: FieldNotes.saveStatus === "NOT SAVED" ? "The notes file could not be written; see the shell log." : "Atomic writes to " + root.tilde(FieldNotes.stateDir) + "/notes.json."
        }
    }

    SettingsSection {
        heading: "Board"
        caption: "The paper floats where you left it on each display. Everything around it is click-through."
        Flow {
            Layout.fillWidth: true; spacing: 8
            StationButton { text: FieldNotes.opened ? "Put the notes away" : "Open Field Notes"; onClicked: FieldNotes.toggle() }
            StationButton { text: "Center the board"; enabled: FieldNotes.loaded; onClicked: FieldNotes.center() }
            StationButton { text: "Open export folder"; hint: root.tilde(FieldNotes.exportDir); onClicked: FieldNotes.openExportFolder() }
        }
        GlowText {
            visible: FieldNotes.lastExport !== ""
            text: (FieldNotes.lastExportOk ? "Last copy: " : "Last copy failed: ") + root.tilde(FieldNotes.lastExport)
            color: FieldNotes.lastExportOk ? Theme.muted : Theme.amber
            Layout.fillWidth: true; elide: Text.ElideMiddle; font.pixelSize: Theme.small
        }
    }

    SettingsFields {
        page: "notes"; highlightKey: root.highlightKey; Layout.fillWidth: true
        captions: ({
            "Paper": "How the sheet sits and where its tools live.",
            "Drawing": "Pen and eraser feel. Press [ and ] for finer pen widths while drawing.",
            "Export": "Ctrl+C saves the sheet as it would print, without the save status or any selection, and copies it for pasting into a chat, an issue or an agent."
        })
    }
}
