// MOCK — Trail Rewind canopy drop. Fixture data only; not wired to Forest.
// Rendered offscreen by tests/check_rewind_mock.py for design review.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../../components"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1000
        implicitHeight: 620
        color: Theme.background

        // ---- fixture trail: a day from 09:00 to 17:00 --------------------
        // kind: application | canopy | surface | settings | breadcrumb
        property var events: [
            { t: 9.23,  kind: "application", label: "kitty",                note: "" },
            { t: 9.31,  kind: "application", label: "Firefox",              note: "" },
            { t: 9.47,  kind: "canopy",      label: "Connections",          note: "Wi-Fi · home" },
            { t: 10.05, kind: "settings",    label: "Settings / Bar",       note: "" },
            { t: 10.42, kind: "application", label: "Obsidian",             note: "" },
            { t: 11.15, kind: "surface",     label: "Shield",               note: "posture check" },
            { t: 11.58, kind: "application", label: "kitty",                note: "" },
            { t: 12.40, kind: "breadcrumb",  label: "lunch — back at 1:30", note: "dropped by you" },
            { t: 13.32, kind: "application", label: "Firefox",              note: "" },
            { t: 13.55, kind: "canopy",      label: "Audio",                note: "Speakers · 40%" },
            { t: 14.10, kind: "application", label: "kitty",                note: "" },
            { t: 14.41, kind: "breadcrumb",  label: "debugging lid wake — s2idle loop", note: "dropped by you" },
            { t: 14.52, kind: "surface",     label: "Station",              note: "health sweep" },
            { t: 15.20, kind: "application", label: "Obsidian",             note: "" },
            { t: 15.48, kind: "canopy",      label: "Recent Trail",         note: "" },
            { t: 16.15, kind: "settings",    label: "Settings / Focus",     note: "" },
            { t: 16.44, kind: "surface",     label: "Focus",                note: "session · 25 min" },
            { t: 17.00, kind: "application", label: "kitty",                note: "" }
        ]
        // scrub position as an hour; step 2 moves it onto the breadcrumb
        property real scrubT: 14.41
        property bool empty: false
        // The day window is derived from the events, never hardcoded: wiring
        // swaps the fixture for Forest.trails rows (epoch `at`) unchanged.
        readonly property real dayStart: events.length ? Math.floor(Math.min.apply(null, events.map(e => e.t))) : 9
        readonly property real dayEnd: events.length ? Math.ceil(Math.max.apply(null, events.map(e => e.t))) : 17
        readonly property real daySpan: Math.max(1, dayEnd - dayStart)
        function frac(t) { return Math.max(0, Math.min(1, (t - dayStart) / daySpan)); }
        function kindColor(kind) {
            return kind === "application" ? Theme.teal
                 : kind === "canopy"      ? Theme.green
                 : kind === "surface"     ? Theme.strataAccent
                 : kind === "breadcrumb"  ? Theme.danger
                 : Theme.muted;
        }
        function kindName(kind) {
            return kind === "application" ? "Applications"
                 : kind === "canopy"      ? "Canopy"
                 : kind === "surface"     ? "Surfaces"
                 : kind === "breadcrumb"  ? "Breadcrumbs"
                 : "Settings";
        }
        function kindGlyph(kind) {
            return Theme.nerdGlyph(
                kind === "application" ? "󰀻" : kind === "canopy" ? "󰕰" : kind === "surface" ? "󰓅" : kind === "breadcrumb" ? "󰓹" : "󰒓",
                kind === "application" ? "A" : kind === "canopy" ? "C" : kind === "surface" ? "S" : kind === "breadcrumb" ? "!" : "·");
        }
        function hourLabel(t) {
            const h = Math.floor(t), m = Math.round((t - h) * 60);
            const h12 = ((h + 11) % 12) + 1;
            return h12 + ":" + (m < 10 ? "0" : "") + m + (h < 12 ? " AM" : " PM");
        }
        readonly property var selected: events.length ? events.reduce((best, e) => Math.abs(e.t - scrubT) < Math.abs(best.t - scrubT) ? e : best, events[0]) : null
        // Bindings must survive an empty trail (after lock, or trails off):
        // `sel` is a placeholder so card bindings never dereference null.
        readonly property var sel: selected || ({ t: dayStart, kind: "settings", label: "", note: "" })
        readonly property bool canReturn: !!selected && ["canopy", "settings", "surface"].includes(selected.kind)
        readonly property string neighborLine: {
            if (!selected || selected.kind !== "breadcrumb") return "";
            const i = events.indexOf(selected);
            const prev = events.slice(0, i).reverse().find(e => e.kind !== "breadcrumb");
            const next = events.slice(i + 1).find(e => e.kind !== "breadcrumb");
            if (!prev && !next) return "";
            if (!prev) return "Before " + next.label + " (" + hourLabel(next.t) + ") — the trail's first mark";
            if (!next) return "After " + prev.label + " (" + hourLabel(prev.t) + ") — the trail's latest mark";
            return "Between " + prev.label + " (" + hourLabel(prev.t) + ") and " + next.label + " (" + hourLabel(next.t) + ")";
        }

        Item {
            id: panel
            anchors.fill: parent

            ChamferFrame {
                anchors.fill: parent
                anchors.margins: 14
                cut: Theme.chamfer
                fill: Qt.alpha(Theme.strataFoundation, .96)
                stroke: Qt.alpha(Theme.teal, .18)
                topLine: true
            }

            ColumnLayout {
            anchors.fill: parent
            anchors.margins: 34
            spacing: 12

            // ---- header --------------------------------------------------
            GlowText { text: "FOREST / REWIND"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.teal }
            RowLayout {
                Layout.fillWidth: true
                GlowText { text: "TRAIL REWIND"; font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 5; color: Theme.text; Layout.fillWidth: true }
                GlowText { visible: !window.empty && window.events.length > 0; text: "TODAY · " + window.hourLabel(window.events[0].t) + " — " + window.hourLabel(window.events[window.events.length - 1].t); font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
            }
            GlowText {
                visible: !window.empty
                text: {
                    const crumbs = window.events.filter(e => e.kind === "breadcrumb").length;
                    return window.events.length + " events on the trail · " + crumbs + (crumbs === 1 ? " breadcrumb" : " breadcrumbs") + " dropped by you";
                }
                font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Item { Layout.fillWidth: true; implicitHeight: 1; Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.teal, .28) } }

            // ---- timeline -------------------------------------------------
            Item {
                id: timeline
                Layout.fillWidth: true
                Layout.preferredHeight: 108
                visible: !window.empty

                // hour ticks + labels, sized from the day's real span
                Repeater {
                    model: window.daySpan + 1
                    Item {
                        required property int index
                        readonly property real t: window.dayStart + index
                        x: window.frac(t) * timeline.width
                        anchors.top: parent.top
                        Rectangle { x: -0.5; width: 1; height: 8; color: Qt.alpha(Theme.muted, .35) }
                        GlowText {
                            anchors.top: parent.top; anchors.topMargin: 11
                            x: -width / 2
                            visible: index % 2 === 0
                            text: ((Math.floor(t) + 11) % 12 + 1) + (t < 12 ? "A" : "P")
                            font.pixelSize: 9; color: Theme.muted
                        }
                    }
                }

                // the fallen log: track
                Rectangle {
                    id: track
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 44
                    height: 6; radius: 3
                    color: Qt.alpha(Theme.strataMuted, .18)
                    Rectangle { // elapsed grain up to the scrubber
                        width: scrubber.x + 1; height: parent.height; radius: 3
                        color: Qt.alpha(Theme.teal, .35)
                    }
                }

                // event markers — bootprints on the log
                Repeater {
                    model: window.empty ? [] : window.events
                    Item {
                        required property var modelData
                        x: window.frac(modelData.t) * timeline.width
                        anchors.top: parent.top; anchors.topMargin: 40
                        Accessible.name: window.kindName(modelData.kind) + " at " + window.hourLabel(modelData.t)
                        readonly property bool sel: window.selected === modelData
                        Rectangle {
                            x: -4; y: 0; width: 8; height: 8; rotation: 45
                            color: sel ? window.kindColor(modelData.kind) : Qt.alpha(window.kindColor(modelData.kind), .75)
                            border.width: sel ? 2 : 0
                            border.color: Theme.text
                        }
                        Rectangle { // ring on the selected print
                            visible: sel
                            x: -8; y: -4; width: 16; height: 16; rotation: 45
                            color: "transparent"
                            border.width: 1; border.color: window.kindColor(modelData.kind)
                        }
                    }
                }

                // scrubber
                Item {
                    id: scrubber
                    x: window.frac(window.scrubT) * timeline.width
                    anchors.top: parent.top; anchors.topMargin: 30
                    width: 0
                    Accessible.name: "Trail position " + window.hourLabel(window.scrubT)
                    Accessible.role: Accessible.Slider
                    GlowText {
                        x: -implicitWidth / 2; y: -2
                        text: window.hourLabel(window.scrubT)
                        font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.ember
                    }
                    Rectangle { x: -0.5; y: 16; width: 1; height: 64; color: Theme.ember }
                    Rectangle { x: -5; y: 14; width: 10; height: 10; rotation: 45; color: Theme.ember }
                }
            }

            // ---- selected moment -----------------------------------------
            ChamferFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: 132
                visible: !window.empty && window.selected !== null
                cut: 8
                fill: Qt.alpha(Theme.strataFoundation, .6)
                stroke: Qt.alpha(window.kindColor(window.sel.kind), .4)
                RowLayout {
                    anchors.fill: parent; anchors.margins: 18; spacing: 18
                    ColumnLayout {
                        spacing: 2
                        GlowText { text: window.hourLabel(window.sel.t); font.pixelSize: 26; font.weight: Font.DemiBold; color: Theme.text }
                        GlowText { text: window.sel.kind.toUpperCase(); font.pixelSize: 9; font.letterSpacing: 1.6; color: window.kindColor(window.sel.kind) }
                    }
                    Item { Layout.preferredWidth: 1; Layout.fillHeight: true; Rectangle { width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .18) } }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        RowLayout {
                            spacing: 8
                            GlowText { text: window.kindGlyph(window.sel.kind); font.pixelSize: 15; color: window.kindColor(window.sel.kind) }
                            GlowText { text: window.sel.label; font.family: Theme.labelFont; font.pixelSize: 16; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        GlowText {
                            visible: window.sel.note !== ""
                            text: window.sel.note; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                        GlowText {
                            visible: window.neighborLine !== ""
                            text: window.neighborLine
                            font.pixelSize: 10; color: Theme.muted
                        }
                    }
                    // TrailCanopy semantics: canopy/settings/surface targets can be
                    // re-opened; applications and breadcrumbs are view-only.
                    Item {
                        Layout.preferredWidth: 132; Layout.preferredHeight: 40; Layout.alignment: Qt.AlignVCenter
                        opacity: window.canReturn ? 1 : .35
                        Accessible.name: window.canReturn ? "Return to " + window.sel.label : "Nothing to return to"
                        ChamferFrame { anchors.fill: parent; cut: 7; fill: Qt.alpha(Theme.teal, .10); stroke: Qt.alpha(Theme.teal, .5) }
                        GlowText { anchors.centerIn: parent; text: "RETURN TO"; font.pixelSize: 11; font.letterSpacing: 1.6; color: Theme.teal }
                    }
                }
            }

            // ---- legend + footer -----------------------------------------
            RowLayout {
                visible: !window.empty
                Layout.fillWidth: true; spacing: 16
                Repeater {
                    model: ["application", "canopy", "surface", "settings", "breadcrumb"]
                    RowLayout {
                        required property string modelData
                        spacing: 6
                        Rectangle { width: 7; height: 7; rotation: 45; color: window.kindColor(modelData) }
                        GlowText { text: window.kindName(modelData); font.pixelSize: 10; color: Theme.muted }
                    }
                }
                Item { Layout.fillWidth: true }
                GlowText { text: "← → SCRUB"; font.pixelSize: 9; font.letterSpacing: 1.4; color: Theme.muted }
            }
            GlowText {
                visible: !window.empty
                Layout.fillWidth: true
                text: "Rewind replays the trail; it never restores windows or state. The trail stays on this machine and clears on lock."
                font.pixelSize: 10; color: Theme.muted; wrapMode: Text.WordWrap
            }

            // ---- empty state ----------------------------------------------
            ColumnLayout {
                visible: window.empty
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.alignment: Qt.AlignHCenter
                Item { Layout.fillHeight: true }
                GlowText { Layout.alignment: Qt.AlignHCenter; text: Theme.nerdGlyph("󰓹", "·"); font.pixelSize: 30; color: Theme.muted }
                GlowText { Layout.alignment: Qt.AlignHCenter; text: "No trail under today's leaves yet."; font.pixelSize: Theme.normal; color: Theme.muted }
                GlowText { Layout.alignment: Qt.AlignHCenter; text: "Turn on Remember Trails and your navigation starts a line you can rewind."; font.pixelSize: Theme.small; color: Theme.muted }
                Item { Layout.fillHeight: true }
            }
        }
        }

        // ---- capture steps ------------------------------------------------
        property int step: 0
        property var fullEvents: events
        Timer {
            interval: 300; running: !Quickshell.env("CEDAR_MOCK_LIVE"); repeat: true
            onTriggered: {
                const dir = Quickshell.env("CEDAR_SCREENSHOT_DIR");
                if (window.step === 0) {
                    window.scrubT = 14.41;
                    panel.grabToImage(r => r.saveToFile(dir + "/rewind-breadcrumb.png"));
                } else if (window.step === 1) {
                    window.scrubT = 10.42;
                    panel.grabToImage(r => r.saveToFile(dir + "/rewind-application.png"));
                } else if (window.step === 2) {
                    // A real day is sparse: Policy.trail caps at 24 rows and
                    // dedups consecutive same-key entries.
                    window.events = [window.fullEvents[2], window.fullEvents[7], window.fullEvents[16]];
                    window.scrubT = 9.6;
                    panel.grabToImage(r => r.saveToFile(dir + "/rewind-sparse.png"));
                } else if (window.step === 3) {
                    window.empty = true;
                    panel.grabToImage(r => r.saveToFile(dir + "/rewind-empty.png"));
                } else {
                    console.log("PASS: Trail Rewind mock — 4 renders");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
