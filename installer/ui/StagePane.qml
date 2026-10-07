import QtQuick
import QtQuick.Layouts
import "../.."
import "../../components"

// The right side: the current decision or stage. One page per stage, each
// built from the same few pieces: a section mark, a heading, a short line
// of explanation, rows, and one primary action. Technical information
// stays behind "Show technical details" and "View details".
Item {
    id: root
    property var model
    readonly property var facts: model.facts || ({})
    readonly property var plan: model.plan || ({})
    readonly property var env: model.environment
    readonly property bool motion: model.motion
    function mark(state) { return ({ pending: "○", running: "◌", complete: "✓", warning: "!", failed: "×", skipped: "–" })[state] || "○"; }
    function tone(state) { return state === "complete" ? Theme.success : state === "running" ? Theme.teal : state === "warning" ? Theme.warning : state === "failed" ? Theme.danger : Theme.inactive; }

    Loader {
        id: page
        anchors { fill: parent; leftMargin: 56; rightMargin: 56; topMargin: 48; bottomMargin: 40 }
        sourceComponent: { switch (root.model.stage) {
            case "welcome": return welcome; case "scan": return scan; case "environment": return environment; case "plan": return planPage;
            case "attention": return attention; case "interrupted": return interrupted; case "install": return install; case "error": return errorPage;
            case "finish": return finish; case "restored": return restored; } return welcome; }
        opacity: 0
        onSourceComponentChanged: { opacity = 0; fadeIn.restart(); }
        NumberAnimation { id: fadeIn; target: page; property: "opacity"; to: 1; duration: root.motion ? 220 : 0; easing.type: Easing.OutCubic }
        Component.onCompleted: fadeIn.restart()
    }

    component Heading: GlowText { Layout.fillWidth: true; font.family: Theme.labelFont; font.pixelSize: Math.round(30 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; wrapMode: Text.WordWrap; glow: true }
    component Lead: GlowText { Layout.fillWidth: true; font.pixelSize: Theme.normal; color: Theme.muted; wrapMode: Text.WordWrap; lineHeight: 1.25 }
    component Row_: RowLayout {
        property string glyph: "✓"
        property color glyphColor: Theme.success
        property string text: ""
        property bool quiet: false
        Layout.fillWidth: true; spacing: 12
        Text { text: parent.glyph; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 13; color: parent.glyphColor; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter }
        GlowText { text: parent.text; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: parent.quiet ? Theme.muted : Theme.text; font.pixelSize: Theme.normal }
    }
    component Primary: StationButton { accent: Theme.green; implicitHeight: 42; implicitWidth: contentItem.implicitWidth + 48; font.pixelSize: Math.round(15 * Theme.fontScale)
        background: Rectangle { radius: Theme.controlRadius; color: Qt.alpha(Theme.green, parent.down ? .3 : .16); border.color: Qt.alpha(Theme.green, .6) } }
    component Quiet: StationButton { accent: Theme.teal; opacity: .85 }

    // ------------------------------------------------------------ welcome
    Component {
        id: welcome
        Item {
            ColumnLayout {
                anchors.centerIn: parent; width: Math.min(520, parent.width); spacing: 10
                Text { Layout.alignment: Qt.AlignHCenter; text: "CEDAR"; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(54 * Theme.fontScale); font.weight: Font.Bold; font.letterSpacing: 12; color: Theme.green }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Contextual Environment & Desktop Automation Runtime"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 1.6; color: Theme.muted }
                GlowText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 26; text: root.model.updating ? "The newest CEDAR is ready to install." : "A complete environment for Hyprland."; font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); color: Theme.text }
                Primary { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 30; text: root.model.updating ? "Update CEDAR" : "Install CEDAR"; enabled: root.model.fixture || root.model.ready; onClicked: root.model.begin() }
                Quiet { Layout.alignment: Qt.AlignHCenter; text: root.model.showTechnical ? "Hide advanced" : "Advanced"; onClicked: root.model.showTechnical = !root.model.showTechnical }
                ColumnLayout {
                    visible: root.model.showTechnical; Layout.fillWidth: true; Layout.topMargin: 6; spacing: 4
                    StationToggle { Layout.fillWidth: true; label: "Start CEDAR in this session after installing"; description: "Off: install only, then cedar try when you are ready."; checked: root.model.options.session; onToggled: v => root.model.setOption("session", v) }
                    StationToggle { Layout.fillWidth: true; label: "Point the application-launcher shortcut at CEDAR Go"; checked: root.model.options.launcher; onToggled: v => root.model.setOption("launcher", v) }
                    StationToggle { Layout.fillWidth: true; label: "Use CEDAR Trailwatch as the locker"; description: "Only after a local password test and one real lock/unlock test."; checked: root.model.options.trailwatch; onToggled: v => root.model.setOption("trailwatch", v) }
                    StationToggle { Layout.fillWidth: true; label: "Also install the recommended fonts"; checked: root.model.options.fonts; onToggled: v => root.model.setOption("fonts", v) }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 36; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Existing Linux installation required"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; opacity: .8 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Your current files will be preserved"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; opacity: .8 }
                }
            }
            Text { anchors.bottom: parent.bottom; anchors.right: parent.right; text: "Installer " + root.model.version; visible: root.model.version !== ""; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; opacity: .6 }
        }
    }

    // --------------------------------------------------------------- scan
    Component {
        id: scan
        ColumnLayout {
            spacing: 10
            SectionMark { text: "SCAN" }
            Heading { text: "Scanning your system…" }
            Lead { text: "CEDAR looks before it changes anything: distribution, compositor, graphics, your existing desktop and the settings worth keeping." }
            Item { implicitHeight: 12 }
            Repeater {
                model: ["Distribution and packages", "Compositor and graphics", "Existing desktop environment", "Monitors, keyboard and applications", "Dependencies"]
                Row_ { required property string modelData; required property int index; text: modelData; glyph: root.model.busy ? (index === 0 ? "◌" : "○") : "✓"; glyphColor: root.model.busy ? Theme.teal : Theme.success }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // -------------------------------------------------------- environment
    Component {
        id: environment
        ColumnLayout {
            spacing: 10
            SectionMark { text: "EXISTING ENVIRONMENT" }
            Heading { text: "Your current environment" }
            GlowText { Layout.fillWidth: true; Layout.topMargin: 6; text: root.env.name || "Hyprland"; font.family: Theme.labelFont; font.pixelSize: Math.round(24 * Theme.fontScale); color: Theme.green }
            Lead { text: (root.env.stack || "") + (root.env.summary ? " · " + root.env.summary : "") }
            Lead { visible: (root.env.evidence || []).length > 0; text: "Detected from: " + (root.env.evidence || []).join(", ") + "."; font.pixelSize: Theme.small }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 16; spacing: 32
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 6
                    SectionMark { text: "KEEP"; tone: Theme.green }
                    Repeater { model: root.env.keep || []; Row_ { required property string modelData; text: modelData } }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 6
                    SectionMark { text: "REPLACE"; tone: Theme.amber }
                    Repeater { model: (root.env.replace || []).length ? root.env.replace : ["Nothing: no conflicting shell or daemon is running"]; Row_ { required property string modelData; text: modelData; glyph: "●"; glyphColor: Theme.amber } }
                }
            }
            Lead { Layout.topMargin: 10; text: root.env.adapter ? "Your original configuration will be backed up before anything changes." : "Automatic session handoff for " + (root.env.name || "this environment") + " is not validated yet. CEDAR installs beside it and opens as a preview; your current shell keeps running." }
            Item { Layout.fillHeight: true }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } Primary { text: "Review Migration"; onClicked: root.model.toPlan() } }
        }
    }

    // --------------------------------------------------------------- plan
    Component {
        id: planPage
        ColumnLayout {
            spacing: 8
            SectionMark { text: "INSTALLATION PLAN" }
            Heading { text: "CEDAR Installation Plan" }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentHeight: planColumn.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: planColumn
                    width: parent.width; spacing: 6
                    Repeater {
                        model: [["SYSTEM", (root.plan.system || []).map(r => ({ text: r.text, state: r.state }))], ["MIGRATION", (root.plan.migration || []).map(t => ({ text: t, state: "ok" }))], ["CEDAR", (root.plan.cedar || []).map(t => ({ text: t, state: "ok" }))]]
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true; Layout.topMargin: 10; spacing: 5
                            SectionMark { text: modelData[0] }
                            Repeater { model: modelData[1]; Row_ { required property var modelData; text: modelData.text; glyph: modelData.state === "warn" ? "!" : modelData.state === "info" ? "·" : "✓"; glyphColor: modelData.state === "warn" ? Theme.amber : modelData.state === "info" ? Theme.muted : Theme.success } }
                        }
                    }
                    Repeater {
                        model: (root.plan.attention || []).filter(a => a.severity !== "stop")
                        Row_ { required property var modelData; Layout.topMargin: 6; text: modelData.title + " — " + modelData.detail; glyph: "!"; glyphColor: Theme.amber }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.topMargin: 12; spacing: 2
                        SectionMark { text: "OPTIONS" }
                        StationToggle { Layout.fillWidth: true; visible: !!root.env.adapter; label: "Start CEDAR in this session"; description: "Keep it after a health check and enable it at login; cedar restore returns your previous desktop."; checked: root.model.options.session; onToggled: v => root.model.setOption("session", v) }
                        StationToggle { Layout.fillWidth: true; visible: root.env.adapter === "hyprland" || root.env.adapter === "noctalia"; label: "Point the application-launcher shortcut at CEDAR Go"; checked: root.model.options.launcher; onToggled: v => root.model.setOption("launcher", v) }
                        StationToggle { Layout.fillWidth: true; visible: !!root.env.adapter; label: "Use CEDAR Trailwatch as the locker"; description: "After a local password test and one real lock/unlock test."; checked: root.model.options.trailwatch; onToggled: v => root.model.setOption("trailwatch", v) }
                        StationToggle { Layout.fillWidth: true; visible: (root.facts.wallpapers || []).length > 0; label: "Point CEDAR at your wallpaper library"; checked: root.model.options.wallpapers; onToggled: v => root.model.setOption("wallpapers", v) }
                        StationToggle { Layout.fillWidth: true; visible: (root.facts.compositor || {}).name === "hyprland"; label: "Use CEDAR’s keybinds (Caelestia layout)"; description: "Super+T terminal, Super+W browser, Super+Q close, Super+1…0 workspaces, Super+N Quick Controls, Super+L lock. Loaded through CEDAR’s journaled Hyprland loader; your other bindings stay."; checked: !!root.model.options.keybinds; onToggled: v => root.model.setOption("keybinds", v) }
                        StationToggle { Layout.fillWidth: true; label: "Also install the recommended fonts"; description: "Readable fallbacks are used otherwise."; checked: root.model.options.fonts; onToggled: v => root.model.setOption("fonts", v) }
                    }
                    ExpandableDetails {
                        Layout.fillWidth: true; Layout.topMargin: 8; label: "Show technical details"
                        Repeater {
                            model: root.facts.technical || []
                            RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 12
                                Text { text: modelData.label; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 150 }
                                GlowText { text: modelData.value; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; font.pixelSize: Theme.small } }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 12
                            Text { text: "Backup destination"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 150 }
                            GlowText { text: root.plan.backupDestination || ""; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; font.pixelSize: Theme.small } }
                        RowLayout { visible: (root.plan.packages || []).length > 0; Layout.fillWidth: true; spacing: 12
                            Text { text: "Packages"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 150 }
                            GlowText { text: (root.plan.packages || []).join(", ") + ((root.plan.packageNotes || []).length ? "\n" + root.plan.packageNotes.join("\n") : ""); Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small } }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 8
                Quiet { text: "Back"; onClicked: root.model.toEnvironment() }
                Item { Layout.fillWidth: true }
                StatusPill { visible: root.model.busy; text: "Updating plan"; tone: Theme.teal }
                Primary { text: "Install CEDAR"; enabled: !root.model.busy && !root.plan.blocked; onClicked: root.model.install() }
            }
        }
    }

    // ---------------------------------------------------------- attention
    Component {
        id: attention
        ColumnLayout {
            spacing: 10
            SectionMark { text: "ATTENTION"; tone: Theme.amber }
            Heading { text: "CEDAR needs attention before installation" }
            Repeater {
                model: (root.plan.attention || []).filter(a => a.severity === "stop")
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; Layout.topMargin: 10; spacing: 4
                    GlowText { Layout.fillWidth: true; text: modelData.title; font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); color: Theme.amber; wrapMode: Text.WordWrap }
                    Lead { text: modelData.detail }
                    Quiet { visible: modelData.learn !== ""; text: "Learn more"; onClicked: Qt.openUrlExternally(modelData.learn) }
                }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Quiet { text: "Cancel"; onClicked: root.model.quit() }
                Item { Layout.fillWidth: true }
                Quiet { text: "Adjust installation"; onClicked: root.model.toPlan() }
                Primary { text: "Check again"; onClicked: root.model.rescan() }
            }
        }
    }

    // -------------------------------------------------------- interrupted
    Component {
        id: interrupted
        ColumnLayout {
            spacing: 10
            SectionMark { text: "RESUME"; tone: Theme.amber }
            Heading { text: "Previous installation interrupted" }
            Lead { text: "CEDAR completed " + (root.model.previous ? root.model.previous.completed + " of " + root.model.previous.total : "some") + " stages" + (root.model.previous && root.model.previous.interruptedAt ? " and stopped at " + root.model.previous.interruptedAt : "") + ". Nothing will be run twice against a partly changed system: continue where it stopped, begin again, or put the previous system back." }
            Repeater {
                model: root.model.previous ? root.model.previous.operations : []
                Row_ { required property var modelData; text: modelData.title; glyph: root.mark(modelData.state === "running" ? "failed" : modelData.state); glyphColor: root.tone(modelData.state === "running" ? "failed" : modelData.state); quiet: modelData.state === "pending" }
            }
            Item { Layout.fillHeight: true }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                Primary { Layout.fillWidth: true; text: "Resume Installation"; onClicked: root.model.resume() }
                Quiet { Layout.fillWidth: true; text: "Start Over"; onClicked: root.model.startOver() }
                Quiet { Layout.fillWidth: true; text: "Restore Previous System"; accent: Theme.amber; onClicked: root.model.restore() }
            }
        }
    }

    // ------------------------------------------------------------ install
    Component {
        id: install
        ColumnLayout {
            spacing: 8
            SectionMark { text: "INSTALLING" }
            Heading { text: "Installing CEDAR" }
            Lead { text: root.model.current ? (root.model.current.detail || root.model.current.description) : root.model.operations.length ? "Finishing…" : "Preparing…" }
            ColumnLayout {
                Layout.fillWidth: true; Layout.topMargin: 12; spacing: 7
                Repeater {
                    model: root.model.operations
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 12
                        Text { text: root.mark(modelData.state); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 13; color: root.tone(modelData.state); Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
                               Behavior on color { enabled: root.motion; ColorAnimation { duration: 140 } } }
                        GlowText { text: modelData.title; font.family: Theme.labelFont; font.pixelSize: Math.round(16 * Theme.fontScale); font.weight: modelData.state === "complete" ? Font.DemiBold : Font.Normal; color: modelData.state === "pending" ? Theme.muted : Theme.text; Layout.preferredWidth: 150 }
                        GlowText { text: modelData.state === "running" ? (modelData.detail || "") : modelData.state === "skipped" || modelData.state === "warning" || modelData.state === "failed" ? (modelData.detail || modelData.error || "") : ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
            RowLayout {
                visible: root.model.password !== ""; Layout.fillWidth: true; Layout.topMargin: 8; spacing: 10
                Text { text: "!"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 13; color: Theme.amber }
                GlowText { text: root.model.password; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.amber; font.pixelSize: Theme.small }
            }
            Item { Layout.fillHeight: true }
            ExpandableDetails {
                Layout.fillWidth: true; label: "View details"; expanded: root.model.showDetails; onExpandedChanged: root.model.showDetails = expanded
                ListView {
                    Layout.fillWidth: true; implicitHeight: 160; clip: true
                    model: root.model.log
                    delegate: Text { required property var modelData; width: ListView.view.width; text: modelData.line; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; wrapMode: Text.WrapAnywhere }
                    onCountChanged: positionViewAtEnd()
                }
            }
        }
    }

    // -------------------------------------------------------------- error
    Component {
        id: errorPage
        ColumnLayout {
            spacing: 10
            SectionMark { text: "STOPPED"; tone: Theme.danger }
            Heading { text: "Installation stopped" }
            GlowText { Layout.fillWidth: true; text: (root.model.error.title || "A step") + " could not be completed."; font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); color: Theme.danger; wrapMode: Text.WordWrap }
            Lead { text: root.model.error.message || "" }
            Lead { Layout.topMargin: 6; text: root.model.error.preserved || "Your original configuration is still backed up. No existing desktop files were deleted." }
            Row_ { visible: (root.model.error.changedBefore || []).length > 0; text: "Completed before the stop: " + (root.model.error.changedBefore || []).join(", "); glyph: "·"; glyphColor: Theme.muted; quiet: true }
            Row_ { text: root.model.error.rolledBack ? "The failed step was rolled back." : "Nothing from the failed step needed rolling back."; glyph: "·"; glyphColor: Theme.muted; quiet: true }
            Row_ { visible: !!root.model.error.log; text: "Log: " + (root.model.error.log || ""); glyph: "·"; glyphColor: Theme.muted; quiet: true }
            Item { Layout.fillHeight: true }
            ExpandableDetails {
                Layout.fillWidth: true; label: "View log"
                ListView { Layout.fillWidth: true; implicitHeight: 140; clip: true; model: root.model.log
                    delegate: Text { required property var modelData; width: ListView.view.width; text: modelData.line; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted; wrapMode: Text.WrapAnywhere }
                    onCountChanged: positionViewAtEnd() }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Quiet { text: "Restore System"; accent: Theme.amber; onClicked: root.model.restore() }
                Item { Layout.fillWidth: true }
                Quiet { text: "Close"; onClicked: root.model.quit() }
                Primary { visible: root.model.error.resumable !== false; text: "Retry Step"; onClicked: root.model.retry() }
            }
        }
    }

    // ------------------------------------------------------------- finish
    Component {
        id: finish
        Item {
            ColumnLayout {
                anchors.centerIn: parent; width: Math.min(520, parent.width); spacing: 10
                readonly property var sessionOp: root.model.operations.find(o => o.id === "session") || ({})
                readonly property bool notStarted: !root.model.cedarRunning && sessionOp.state === "warning"
                Text { Layout.alignment: Qt.AlignHCenter; text: parent.notStarted ? "!" : "✓"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 44; color: parent.notStarted ? Theme.amber : Theme.green }
                Text { Layout.alignment: Qt.AlignHCenter; text: parent.notStarted ? "CEDAR IS INSTALLED" : "CEDAR IS READY"; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(28 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 4; color: Theme.text }
                Lead { Layout.topMargin: 6; horizontalAlignment: Text.AlignHCenter; text: root.model.cedarRunning ? "Your desktop has been installed, verified and is running now." : parent.notStarted ? "Installed and verified, but not started." : "Your desktop has been installed and verified." }
                GlowText { visible: parent.notStarted; Layout.fillWidth: true; Layout.topMargin: 6; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: (parent.sessionOp.detail || "").replace("CEDAR is installed but was not started: ", ""); color: Theme.amber; font.pixelSize: Theme.normal }
                ColumnLayout {
                    visible: (root.model.result.imports || []).length > 0; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 18; spacing: 5
                    SectionMark { text: "IMPORTED"; tone: Theme.green }
                    Repeater { model: root.model.result.imports || []; Row_ { required property string modelData; text: modelData } }
                }
                Repeater {
                    model: root.model.operations.filter(o => o.state === "warning" && o.id !== "session" && (o.detail || "") !== "")
                    Row_ { required property var modelData; Layout.topMargin: 8; text: modelData.detail; glyph: "!"; glyphColor: Theme.amber }
                }
                Lead { Layout.topMargin: 16; horizontalAlignment: Text.AlignHCenter; text: "Your previous environment was backed up" + (root.model.result.backup ? " to " + root.model.result.backup : "") + "." ; font.pixelSize: Theme.small }
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 26; spacing: 8
                    Primary { Layout.alignment: Qt.AlignHCenter; text: root.model.cedarRunning ? "Close" : !root.env.adapter ? "Close" : parent.parent.notStarted ? "Try starting CEDAR again" : "Start CEDAR"; onClicked: root.model.cedarRunning || !root.env.adapter ? root.model.quit() : root.model.startCedar() }
                    Quiet { visible: !root.model.cedarRunning && !!root.env.adapter; Layout.alignment: Qt.AlignHCenter; text: "Start Later"; onClicked: root.model.quit() }
                }
                Lead { visible: !root.model.cedarRunning && !root.env.adapter; Layout.topMargin: 10; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Theme.small; text: "Open the isolated preview with \"cedar preview\". Session handoff for " + (root.env.name || "this environment") + " is not validated yet." }
            }
        }
    }

    // ----------------------------------------------------------- restored
    Component {
        id: restored
        ColumnLayout {
            spacing: 10
            SectionMark { text: "RESTORED"; tone: Theme.teal }
            Heading { text: "Previous system restored" }
            Lead { text: "The files CEDAR copied were put back where they had not been edited since; CEDAR's program entry points were restored from their journals. Packages were left installed." }
            Row_ { text: "Session: " + (root.model.restoreReport.session || "not active"); glyph: "·"; glyphColor: Theme.muted }
            Row_ { text: "Program entry points: " + (root.model.restoreReport.program || ""); glyph: "·"; glyphColor: Theme.muted }
            Row_ { text: (root.model.restoreReport.files || []).length + " file(s) restored"; glyph: "✓" }
            Row_ { visible: (root.model.restoreReport.conflicts || []).length > 0; text: "Left alone because you edited them afterwards: " + (root.model.restoreReport.conflicts || []).join(", "); glyph: "!"; glyphColor: Theme.amber }
            Item { Layout.fillHeight: true }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } Primary { text: "Close"; onClicked: root.model.quit() } }
        }
    }
}
