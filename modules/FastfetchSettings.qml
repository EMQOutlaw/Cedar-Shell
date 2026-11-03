import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Settings › Fastfetch: the branded terminal readout, edited end to end.
// config.jsonc stays the source of truth; this page edits a draft model,
// live-previews the real readout (fastfetch runs with the candidate — the
// panel is a specimen of the terminal), and writes back on Save with the
// previous config kept as config.jsonc.bak. The Ryoku FastfetchPage pattern
// (live preview + grouped rows + a dirty/Save bar) in CEDAR's vocabulary.
ColumnLayout {
    id: root
    property string highlightKey: ""
    property bool active: false
    readonly property bool ready: Fastfetch.ready
    readonly property bool dirty: Fastfetch.dirty
    // Editing is frozen only while a draft-replacing request (get/save) runs;
    // previews leave editing live so a focused field is never silently reset.
    readonly property bool editable: root.ready && !Fastfetch.commitLock && !Fastfetch.saving
    readonly property bool wide: width > 980
    spacing: Theme.spaceLg
    Component.onCompleted: Fastfetch.refresh(true)
    // The navigation guard's "Discard and continue": drop the singleton's
    // draft outright. Safe while a preview runs (previews never touch the
    // draft). Refused while a save is in flight — the return value is the
    // contract: false keeps the navigation guard active so the user is asked
    // again instead of silently losing the edits the save is writing.
    function discard() {
        if (Fastfetch.saving) return false;
        Fastfetch.draft = Fastfetch.model ? JSON.parse(JSON.stringify(Fastfetch.model)) : null;
        Fastfetch.error = ""; Fastfetch.message = ""; Fastfetch.previewError = "";
        // the in-flight specimen is of the discarded draft: invalidate it and
        // preview the committed model instead
        Fastfetch.previewGeneration++;
        Fastfetch.previewText = "";  // never show an old specimen beside "matches config.jsonc"
        Fastfetch.requestPreview();
        return true;
    }

    component FCell: SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.minimumWidth: 0
    }

    GlowText {
        visible: !Fastfetch.installed
        text: "fastfetch is not installed, so there is no readout to edit. It comes from the Arch repositories (pacman -S fastfetch); CEDAR finds it on the next open or shell start."
        color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
    }
    GlowText { visible: Fastfetch.error !== ""; text: Fastfetch.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    GlowText { visible: Fastfetch.previewError !== ""; text: Fastfetch.previewError; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    GlowText { visible: Fastfetch.configError && Fastfetch.configErrorText !== ""; text: Fastfetch.configErrorText; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    GlowText { visible: Fastfetch.message !== ""; text: Fastfetch.message; color: Theme.teal; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }

    GridLayout {
        visible: Fastfetch.installed
        Layout.fillWidth: true
        columns: root.wide ? 2 : 1
        columnSpacing: Theme.spaceLg; rowSpacing: Theme.spaceLg

        FCell {
            heading: "The readout"; caption: "What fastfetch prints in a terminal, live. This panel runs the real fastfetch with your draft; line text is shown plain (terminal colours are the terminal's)."
            badge: Fastfetch.dirty ? "edited" : ""
            badgeColor: Theme.teal
            // The specimen: the real readout in mono. Terminal colour codes
            // are stripped — Text cannot render SGR sequences, and colour is
            // the terminal's to draw.
            SettingsSurface {
                Layout.fillWidth: true; padding: Theme.spaceMd
                ColumnLayout {
                    width: parent.width; spacing: 0
                    GlowText {
                        objectName: "fastfetchPreview"
                        Layout.fillWidth: true
                        text: Fastfetch.previewText !== "" ? Fastfetch.previewText.replace(/\x1b\[[0-9;]*m/g, "") : (Fastfetch.previewBusy ? "Running fastfetch…" : "The readout appears here.")
                        color: Fastfetch.previewText !== "" ? Theme.strataText : Theme.muted
                        font.family: Theme.dataFont; font.pixelSize: Theme.small
                        wrapMode: Text.WrapAnywhere
                    }
                    GlowText { visible: Fastfetch.previewBusy; text: "…"; color: Theme.muted; font.pixelSize: Theme.small }
                }
            }
            GlowText { visible: Fastfetch.previewText === "" && !Fastfetch.previewBusy; text: "Edit below; the specimen refreshes as you do."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        FCell {
            heading: "Emblem"; caption: "The art beside the readout: an ASCII art file, the built-in logo, or none. Image-emblem configs CEDAR cannot edit are kept exactly as they are."
            GlowText {
                visible: Fastfetch.draft?.logo?.kind === "other"
                Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.muted
                text: "This config uses the fastfetch logo type \"" + (Fastfetch.draft?.logo?.type || "") + "\", which CEDAR preserves but does not edit. Pick a kind below to take over."
            }
            SettingRow {
                Layout.fillWidth: true; title: "Kind"
                ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Emblem kind"; enabled: root.editable; options: [{value:"none",label:"None"},{value:"builtin",label:"Built-in"},{value:"ascii",label:"ASCII"}]; current: Fastfetch.draft?.logo?.kind || "builtin"; onChosen: value => Fastfetch.setLogo("kind", value) }
            }
            SettingRow {
                visible: Fastfetch.draft?.logo?.kind === "ascii"
                Layout.fillWidth: true; title: "File"; description: "Absolute path or ~/… to the ASCII art text file, printed as-is."
                StationField { Layout.fillWidth: true; enabled: root.editable; text: Fastfetch.draft?.logo?.source || ""; placeholderText: "~/Pictures/logo.txt"; Accessible.name: "Emblem file"; onCommit: value => Fastfetch.setLogo("source", value) }
            }
            SettingRow {
                visible: Fastfetch.draft?.logo?.kind === "ascii"
                Layout.fillWidth: true; title: "Width"; description: Math.round(logoWidth.value) + " columns."
                StationSlider { id: logoWidth; Layout.fillWidth: true; enabled: root.editable; from: 4; to: 80; stepSize: 1; value: Fastfetch.draft?.logo?.width ?? 28; Accessible.name: "Emblem width in columns"; onMoved: value => Fastfetch.setLogo("width", Math.round(value)) }
            }
            SettingRow {
                visible: Fastfetch.draft?.logo?.kind === "ascii"
                Layout.fillWidth: true; title: "Height"; description: Math.round(logoHeight.value) + " lines."
                StationSlider { id: logoHeight; Layout.fillWidth: true; enabled: root.editable; from: 2; to: 60; stepSize: 1; value: Fastfetch.draft?.logo?.height ?? 14; Accessible.name: "Emblem height in lines"; onMoved: value => Fastfetch.setLogo("height", Math.round(value)) }
            }
            SettingRow {
                visible: Fastfetch.draft?.logo?.kind === "ascii"
                Layout.fillWidth: true; title: "Padding"; description: Math.round(logoPad.value) + " blank columns before the art."
                StationSlider { id: logoPad; Layout.fillWidth: true; enabled: root.editable; from: 0; to: 20; stepSize: 1; value: Fastfetch.draft?.logo?.padding ?? 3; Accessible.name: "Emblem padding"; onMoved: value => Fastfetch.setLogo("padding", Math.round(value)) }
            }
        }
        FCell {
            heading: "Accent"; caption: "The colour of every readout label. Empty keeps fastfetch's own default."
            SettingRow {
                Layout.fillWidth: true; title: "Label colour"; description: "Hex (RRGGBB, with or without a leading #). The swatch in the readout shows it live."
                StationField { Layout.fillWidth: true; enabled: root.editable; text: Fastfetch.draft?.accent || ""; placeholderText: "RRGGBB"; Accessible.name: "Readout accent colour"; onCommit: value => Fastfetch.setAccent(value) }
            }
        }
        FCell {
            objectName: "fastfetchRows"
            heading: "Info rows"; caption: "The readout's lines. Add, reorder, relabel or remove. A row CEDAR cannot edit (a custom module, a configured colors row) is shown but locked and saved exactly as it is."
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spaceSm
                StationCombo {
                    id: addCombo; Layout.fillWidth: true
                    enabled: root.editable
                    model: {
                        const present = new Set((Fastfetch.draft?.rows || []).map(r => r.key));
                        return Fastfetch.catalog.filter(c => !present.has(c.key)).map(c => c.label);
                    }
                    Accessible.name: "Row to add"
                }
                StationButton { text: "Add"; enabled: root.editable && addCombo.currentText !== ""; onClicked: { const match = Fastfetch.catalog.find(c => c.label === addCombo.currentText); if (match) { Fastfetch.addRow(match.key); addCombo.currentIndex = -1; } } }
            }
            Repeater {
                model: Fastfetch.rows
                SettingRow {
                    id: rowHost
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    title: modelData.label
                    description: modelData.key
                    StationField {
                        Layout.preferredWidth: Theme.controlHeight * 4
                        enabled: root.editable && !modelData.fixed; text: modelData.label; placeholderText: modelData.key.toUpperCase()
                        Accessible.name: "Label for row " + modelData.key
                        onCommit: value => { const label = value.trim(); if (label !== "" && label !== modelData.label) Fastfetch.setRowLabel(rowHost.index, label); }
                    }
                    StationButton { iconOnly: true; text: Theme.nerdGlyph("", "↑"); hint: "Move up"; enabled: root.editable && rowHost.index > 0; onClicked: Fastfetch.moveRow(rowHost.index, -1) }
                    StationButton { iconOnly: true; text: Theme.nerdGlyph("", "↓"); hint: "Move down"; enabled: root.editable && rowHost.index < Fastfetch.rows.length - 1; onClicked: Fastfetch.moveRow(rowHost.index, 1) }
                    StationButton { iconOnly: true; text: "×"; hint: "Remove row"; enabled: root.editable; onClicked: Fastfetch.removeRow(rowHost.index) }
                }
            }
        }
        FCell {
            heading: "Save"; caption: "Writes config.jsonc (the previous file is kept as config.jsonc.bak next to it). fastfetch must run the candidate cleanly before CEDAR saves it."
            Layout.columnSpan: root.wide ? 2 : 1
            Flow {
                Layout.fillWidth: true; spacing: Theme.spaceSm
                StationButton { text: Fastfetch.saving ? "Saving…" : "Save to config.jsonc"; accent: Theme.green; checked: Fastfetch.dirty; enabled: Fastfetch.dirty && !Fastfetch.busy; onClicked: Fastfetch.save() }
                StationButton { text: "Revert edits"; enabled: Fastfetch.dirty && !Fastfetch.busy; onClicked: Fastfetch.revert() }
                GlowText { height: Theme.controlHeight; verticalAlignment: Text.AlignVCenter; text: Fastfetch.dirty ? (Fastfetch.previewBusy ? "Previewing…" : "Unsaved edits — the specimen above is the draft.") : "The readout matches config.jsonc."; color: Fastfetch.dirty ? Theme.teal : Theme.muted; font.pixelSize: Theme.small }
            }
            GlowText { visible: Fastfetch.configPath !== ""; text: Fastfetch.configPath; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }
}
