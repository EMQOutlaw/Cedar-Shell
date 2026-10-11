import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR AI's content: a station rail and three pages. Session is the
// conversation: the goal, then the two agents taking turns down a spine,
// the running agent's tool activity beneath the latest turn, and a line for
// the person to step in. Sessions lists what was recorded and reopens one;
// Settings holds the checkout, the permission mode, the round limit and who
// speaks first. Depth follows Shield: window level 0, chamfered frames level
// 1, rows level 2.
//
// Motion: the shared entrance clock (the Field Station pattern); a new turn
// settles in on its own short beat; the working dot breathes through Breath
// and stops with Motion.active. Reduced Motion and test mode show the settled
// view on the first frame.
FocusScope {
    id: root
    signal closed()
    property string page: "session"
    readonly property bool sidebar: width >= 860
    readonly property var pages: [["session", "Session", "◈"], ["sessions", "Sessions", "◷"], ["settings", "Settings", "⚙"]]
    function navigate(id) { page = id; }
    function agentTone(agent) { return agent === "claude" ? Theme.amber : agent === "codex" ? Theme.teal : Theme.green; }
    function agentName(agent) { return agent === "claude" ? "Claude" : agent === "codex" ? "Codex" : "You"; }
    function when(at) {
        const stamp = typeof at === "number" ? at : Date.parse(at);
        if (!stamp) return "";
        const diff = Math.max(0, Date.now() - stamp), m = Math.floor(diff / 60000);
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Qt.formatDateTime(new Date(stamp), Config.clock24 ? "d MMM HH:mm" : "d MMM h:mm ap");
    }
    readonly property string stateWord: Relay.running ? "Live" : Relay.finished === "done" ? "Done" : Relay.finished === "rounds" ? "Paused" : Relay.finished === "error" ? "Failed" : Relay.finished === "stopped" ? "Stopped" : Relay.turns.length ? "Rest" : "Ready"
    readonly property color stateTone: Relay.running ? Theme.green : Relay.finished === "done" ? Theme.success : Relay.finished === "error" ? Theme.danger : Relay.finished === "rounds" ? Theme.warning : Theme.inactive
    readonly property bool hasSession: Relay.running || Relay.turns.length > 0 || Relay.sessionDir !== ""
    // Turns, hand-offs between the agents and the person's messages, oldest first.
    readonly property var entries: Relay.turns.map(t => Object.assign({ kind: "turn" }, t))
        .concat(Relay.relays.map(r => ({ kind: "relay", agent: r.sender, receiver: r.receiver, text: "", at: r.at, round: r.round, done: false })))
        .concat(Relay.humanMessages.map(h => ({ kind: "human", agent: "human", text: h.text, at: h.at, round: 0, done: false })))
        .sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
    readonly property string pairLabel: Relay.preferredAgents === "claude" ? "CLAUDE ALONE" : Relay.preferredAgents === "codex" ? "CODEX ALONE" : "CLAUDE · CODEX"
    readonly property string unitWord: Relay.soloSession ? "TURN" : "ROUND"

    // ---------------------------------------------------------- entrance
    property real reveal: 1
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    function beat(order, span = .4) { return ease(.06 * order, span); }
    function enter(duration) {
        entrance.stop();
        if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; }
        entrance.duration = duration;
        reveal = 0;
        entrance.start();
    }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    function consumeRequest() { if (Relay.requestedPage) { navigate(Relay.requestedPage); Relay.requestedPage = ""; } }
    Connections { target: Relay; function onRequestedPageChanged() { root.consumeRequest(); } }
    Component.onCompleted: { consumeRequest(); enter(1050); }
    onPageChanged: enter(700)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier) { root.closed(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3 && event.modifiers & Qt.ControlModifier) { root.navigate(root.pages[event.key - Qt.Key_1][0]); event.accepted = true; }
    }

    // ------------------------------------------------------- vocabulary
    component Frame: ChamferFrame {
        property int order: 0
        property int padding: 20
        default property alias content: frameBody.data
        cut: 10
        fill: Qt.alpha(Theme.surface, .88)
        stroke: Qt.alpha(Theme.teal, .16)
        topLine: true
        topLineColor: Theme.teal
        implicitHeight: frameBody.implicitHeight + padding * 2
        opacity: root.beat(order)
        transform: Translate { y: 6 * (1 - root.beat(order)) }
        ColumnLayout { id: frameBody; anchors { left: parent.left; right: parent.right; top: parent.top; margins: padding } spacing: 10 }
    }
    component PageTitle: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        default property alias actions: actionRow.data
        Layout.fillWidth: true
        spacing: 12
        RowLayout {
            Layout.fillWidth: true; spacing: 16
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                opacity: root.ease(0, .45)
                transform: Translate { y: 6 * (1 - root.ease(0, .45)) }
                GlowText { text: title.toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 3 + 6 * (1 - root.ease(0, .6)); color: Theme.text }
                GlowText { visible: subtitle !== ""; text: subtitle; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            RowLayout { id: actionRow; spacing: 8; opacity: root.ease(.1, .4); Layout.alignment: Qt.AlignTop }
        }
        Item {
            Layout.fillWidth: true; implicitHeight: 1
            Rectangle {
                width: parent.width * root.ease(.08, .5); height: 1; color: Qt.alpha(Theme.teal, .28)
                Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 120); height: 1; color: Theme.green; opacity: .8 * (1 - root.ease(.5, .4)) }
            }
        }
    }
    component Reading: ColumnLayout {
        property string label: ""
        property string value: ""
        property color valueTone: Theme.text
        property int order: 0
        spacing: 2
        opacity: root.beat(order, .35)
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + value
        GlowText { text: label.toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        GlowText { text: value; font.family: Theme.labelFont; font.pixelSize: Math.round(17 * Theme.fontScale); font.weight: Font.DemiBold; color: valueTone; Layout.fillWidth: true; elide: Text.ElideRight }
    }
    // A multi-line field in the Station family: the goal, and the line to the agents.
    component Composer: TextArea {
        id: area
        property string placeholder: ""
        signal submitted()
        Layout.fillWidth: true
        placeholderText: placeholder
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        color: Theme.text
        placeholderTextColor: Qt.alpha(Theme.muted, .65)
        selectionColor: Theme.border
        selectedTextColor: Theme.text
        font.family: Theme.dataFont
        font.pixelSize: 12
        leftPadding: 12; rightPadding: 12; topPadding: 10; bottomPadding: 10
        background: Rectangle { radius: 6; color: Qt.alpha(Theme.teal, .035); border.width: 1; border.color: area.activeFocus ? Theme.teal : Qt.alpha(Theme.teal, .18) }
        Keys.onPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { area.submitted(); event.accepted = true; }
        }
    }
    // One turn down the spine: the agent's dot and name, the round, the text, how it ended.
    component TurnRow: Item {
        id: turn
        required property var modelData
        required property int index
        property bool last: false
        readonly property color tone: root.agentTone(modelData.agent)
        Layout.fillWidth: true
        implicitHeight: turnBody.implicitHeight + 18
        opacity: root.beat(2 + Math.min(index, 8) * .5, .35)
        readonly property bool handoff: modelData.kind === "relay"
        Rectangle { visible: !turn.last; x: 4; y: 16; width: 1; height: parent.height - 16; color: Qt.alpha(Theme.teal, .18) }
        // A hand-off is drawn as the spine itself passing the reply along: a small arrow where a dot would be.
        Rectangle { visible: !turn.handoff; x: 0; y: 10; width: 9; height: 9; radius: 4.5; color: turn.modelData.kind === "human" ? Theme.green : turn.tone }
        Text { visible: turn.handoff; x: 0; y: 6; width: 9; horizontalAlignment: Text.AlignHCenter; text: "↓"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; color: Qt.alpha(Theme.teal, .7) }
        ColumnLayout {
            id: turnBody
            x: 22; y: 4; width: parent.width - 22; spacing: 6
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                GlowText { text: root.agentName(turn.modelData.agent).toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.6; color: turn.modelData.kind === "human" ? Theme.green : turn.tone }
                GlowText { visible: turn.handoff; text: "→"; font.pixelSize: 10; color: Theme.muted }
                GlowText { visible: turn.handoff; text: root.agentName(turn.modelData.receiver || "").toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.6; color: root.agentTone(turn.modelData.receiver || "") }
                GlowText { visible: turn.handoff; text: "reply handed over, read by " + root.agentName(turn.modelData.receiver || "") + " next"; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                GlowText { visible: turn.modelData.kind === "turn"; text: root.unitWord + " " + turn.modelData.round; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                Item { visible: !turn.handoff; Layout.fillWidth: true }
                StatusPill { visible: turn.modelData.kind === "turn"; text: turn.modelData.done ? "Done" : "Next"; tone: turn.modelData.done ? Theme.success : Theme.teal }
                GlowText { text: root.when(turn.modelData.at); font.pixelSize: Theme.small; color: Theme.muted }
            }
            TextEdit {
                visible: !turn.handoff
                Layout.fillWidth: true
                text: turn.modelData.text
                textFormat: TextEdit.PlainText
                readOnly: true; selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.family: Theme.dataFont; font.pixelSize: Theme.small
                selectionColor: Theme.border; selectedTextColor: Theme.text
            }
        }
    }

    // One plan window: a label, a thin bar in the pill's language, the percent. Amber past 80, ember past 95.
    component PlanBar: RowLayout {
        id: bar
        property string label: ""
        property real fraction: 0
        readonly property color tone: fraction >= .95 ? Theme.ember : fraction >= .8 ? Theme.amber : Theme.teal
        Layout.fillWidth: true; spacing: 8
        Accessible.role: Accessible.StaticText
        Accessible.name: label + " window " + Math.round(fraction * 100) + " percent used"
        GlowText { text: bar.label; font.pixelSize: Theme.small; color: Theme.muted; Layout.preferredWidth: 44 }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 3; radius: 1.5; color: Qt.alpha(Theme.teal, .14)
            Rectangle { width: parent.width * Math.max(0, Math.min(1, bar.fraction)); height: parent.height; radius: 1.5; color: bar.tone; Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.transition } } }
        }
        GlowText { text: Math.round(bar.fraction * 100) + "%"; font.pixelSize: Theme.small; color: bar.tone; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
    }
    // Which model and effort one agent runs: the tool's own default, or a choice it lists.
    component ModelPicker: ColumnLayout {
        id: picker
        property string agent: "claude"
        readonly property bool isClaude: agent === "claude"
        readonly property string currentModel: isClaude ? Relay.claudeModel : Relay.codexModel
        readonly property string currentEffort: isClaude ? Relay.claudeEffort : Relay.codexEffort
        readonly property var listed: isClaude ? Relay.claudeModels : Relay.codexModels
        readonly property var chosenEntry: listed.find(m => m.id === picker.currentModel) || null
        readonly property var efforts: isClaude ? Relay.claudeEfforts : (chosenEntry && chosenEntry.efforts && chosenEntry.efforts.length ? chosenEntry.efforts : Relay.codexEfforts)
        readonly property string defaultLabel: isClaude ? "Default" : "Default" + (Relay.codexDefault.model ? " · " + Relay.codexDefault.model : "")
        readonly property string defaultEffortLabel: "Default" + (!isClaude && Relay.codexDefault.effort ? " · " + Relay.codexDefault.effort : "")
        Layout.fillWidth: true; spacing: 6
        RowLayout { spacing: 10
            GlowText { text: root.agentName(picker.agent).toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.6; color: root.agentTone(picker.agent) }
            GlowText { text: "MODEL"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted } }
        ChoiceChips {
            Layout.fillWidth: true
            options: [{ value: "", label: picker.defaultLabel }].concat(picker.listed.map(m => ({ value: m.id, label: m.label })))
            current: picker.currentModel; accessibleLabel: root.agentName(picker.agent) + " model"; enabled: !Relay.running
            onChosen: value => { Config.set(picker.isClaude ? "relayClaudeModel" : "relayCodexModel", value); if (!picker.isClaude) Config.set("relayCodexEffort", ""); }
        }
        GlowText { text: "EFFORT"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        ChoiceChips {
            Layout.fillWidth: true
            options: [{ value: "", label: picker.defaultEffortLabel }].concat(picker.efforts.map(e => ({ value: e, label: e === "xhigh" ? "Extra high" : e.charAt(0).toUpperCase() + e.slice(1) })))
            current: picker.currentEffort; accessibleLabel: root.agentName(picker.agent) + " effort"; enabled: !Relay.running
            onChosen: value => Config.set(picker.isClaude ? "relayClaudeEffort" : "relayCodexEffort", value)
        }
        GlowText { visible: !picker.isClaude && !picker.listed.length && Relay.ready; text: "Codex has not listed its models yet; run codex once so it fills its model cache, then Look again under Tools."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }

    // ------------------------------------------------------------ navigation
    component NavButton: StationButton {
        id: nav
        required property var modelData
        readonly property bool current: root.page === modelData[0]
        checked: current
        accent: Theme.green
        implicitHeight: root.sidebar ? 38 : 32
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        padding: root.sidebar ? 12 : 8
        Layout.fillWidth: root.sidebar
        onClicked: root.navigate(modelData[0])
        Accessible.name: modelData[1] + (current ? ", current page" : "")
        background: ChamferFrame {
            cut: 7
            fill: nav.current ? Qt.alpha(Theme.green, .06) : nav.down ? Qt.alpha(Theme.teal, .1) : nav.hovered ? Qt.alpha(Theme.teal, .05) : Theme.transparent
            stroke: nav.visualFocus ? Theme.green : nav.current ? Qt.alpha(Theme.green, .4) : nav.hovered ? Qt.alpha(Theme.teal, .3) : Theme.transparent
            strokeWidth: nav.visualFocus ? 2 : 1
            line: nav.current; lineColor: Theme.green; lineFraction: .5
        }
        contentItem: RowLayout {
            spacing: 10
            Text { visible: root.sidebar; text: nav.modelData[2]; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 13; color: nav.current ? Theme.green : Theme.muted; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter }
            Text { text: nav.modelData[1]; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: nav.current ? Theme.green : Theme.text; Layout.fillWidth: root.sidebar; elide: Text.ElideRight }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            visible: root.sidebar
            Layout.fillHeight: true; Layout.preferredWidth: 212
            color: Qt.alpha(Theme.surface, .7)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .12) }
            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true; Layout.bottomMargin: 14; spacing: 10
                    // The mark: two dots on one line, the pair at work; one dot when an agent works alone.
                    Item {
                        implicitWidth: 30; implicitHeight: 36
                        Rectangle { visible: Relay.preferredAgents !== "codex"; x: Relay.solo ? 11 : 4; y: 13; width: 9; height: 9; radius: 4.5; color: Theme.amber; opacity: .9 }
                        Rectangle { visible: !Relay.solo; x: 13; y: 17; width: 8; height: 1; color: Qt.alpha(Theme.teal, .6) }
                        Rectangle { visible: Relay.preferredAgents !== "claude"; x: Relay.solo ? 11 : 19; y: 13; width: 9; height: 9; radius: 4.5; color: Theme.teal; opacity: .9 }
                    }
                    ColumnLayout { spacing: 0
                        GlowText { text: "CEDAR AI"; font.pixelSize: 12; font.letterSpacing: 2.6; color: Theme.teal }
                        GlowText { text: root.pairLabel; font.pixelSize: 9; font.letterSpacing: 1.8; color: Theme.muted } }
                }
                Repeater { model: root.pages.slice(0, 2); NavButton {} }
                Item { Layout.fillHeight: true }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.bottomMargin: 10; spacing: 8
                    StatusPill { text: root.stateWord; tone: root.stateTone }
                    GlowText { visible: Relay.running; text: root.unitWord + " " + Math.max(1, Relay.currentRound) + (Relay.rounds > 0 ? " OF " + Relay.rounds : " · UNTIL DONE"); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                    GlowText { text: Relay.headline; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    // Claude's plan windows, from its last run; Codex's CLI gives no plan reading.
                    ColumnLayout {
                        visible: !!Relay.limits.claude
                        Layout.fillWidth: true; Layout.topMargin: 6; spacing: 3
                        GlowText { text: "CLAUDE PLAN"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                        PlanBar { label: "5-hour"; fraction: Relay.limits.claude ? Relay.limits.claude.fiveHour : 0 }
                        PlanBar { label: "Week"; fraction: Relay.limits.claude ? Relay.limits.claude.sevenDay : 0 }
                        GlowText { text: Relay.limits.claude && Relay.limits.claude.at ? "as of " + root.when(Relay.limits.claude.at) : ""; font.pixelSize: 9; color: Theme.muted }
                    }
                }
                Repeater { model: root.pages.slice(2); NavButton {} }
                GlowText { text: Branding.content.identity || ""; font.pixelSize: 9; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.topMargin: 8 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0
            RowLayout {
                visible: !root.sidebar
                Layout.fillWidth: true; Layout.margins: 12; spacing: 6
                Repeater { model: root.pages; NavButton {} }
                Item { Layout.fillWidth: true }
                StatusPill { text: root.stateWord; tone: root.stateTone }
            }
            Flickable {
                id: scroll
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: body.implicitHeight + 56
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Loader {
                    id: body
                    x: 28; y: 28; width: scroll.width - 56
                    sourceComponent: ({ session: session, sessions: sessionsPage, settings: settings })[root.page] || session
                }
                // A new turn lands at the bottom; follow it while the conversation is live.
                function follow() { if (Relay.running && contentHeight > height) contentY = contentHeight - height; }
                Connections { target: Relay; function onTurnsChanged() { Qt.callLater(scroll.follow); } function onActivityChanged() { Qt.callLater(scroll.follow); } }
            }
        }
    }

    // ---------------------------------------------------------------- session
    Component {
        id: session
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "CEDAR AI"
                subtitle: Relay.subline
                StationButton { visible: Relay.running; text: "Stop"; hint: "End the session after the running turn; the transcript is kept"; accent: Theme.ember; onClicked: Relay.stop() }
                StationButton { visible: !Relay.running && root.hasSession; text: "New goal"; hint: "Clear the view; the recorded session stays under Sessions"; onClicked: Relay.clear() }
            }
            GlowText { visible: Relay.ready && !Relay.available; text: "CEDAR AI needs " + Relay.missing + " on PATH. Install " + (Relay.missing.indexOf("and") >= 0 ? "them" : "it") + ", then open this window again."; color: Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            // The goal, until a session exists; then its compact header.
            Frame {
                visible: !root.hasSession
                order: 1
                Layout.fillWidth: true
                SectionMark { text: "GOAL" }
                Composer {
                    id: goalField
                    placeholder: Relay.solo ? "What should " + Relay.agentName(Relay.preferredAgents) + " work on?" : "What should Claude and Codex work on together?"
                    Layout.minimumHeight: 96
                    enabled: Relay.available && !Relay.running
                    onSubmitted: if (text.trim()) Relay.start(text)
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout { spacing: 6
                        GlowText { text: "AGENTS"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                        ChoiceChips { options: [{ value: "both", label: "Both" }, { value: "claude", label: "Claude" }, { value: "codex", label: "Codex" }]; current: Relay.preferredAgents; accessibleLabel: "Which agents work on the goal"; enabled: !Relay.running; onChosen: value => Config.set("relayAgents", value) } }
                    ColumnLayout { spacing: 6
                        GlowText { text: "ACCESS"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                        ChoiceChips { options: [{ value: "read", label: "Read" }, { value: "edit", label: "Edit" }, { value: "full", label: "Full" }]; current: Relay.preferredMode; accessibleLabel: "What the agents may do"; enabled: !Relay.running; onChosen: value => Config.set("relayMode", value) } }
                    ColumnLayout { spacing: 6
                        GlowText { text: Relay.solo ? "TURNS" : "ROUNDS"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                        ChoiceChips { options: [{ value: 0, label: "Until done" }, { value: 2, label: "2" }, { value: 4, label: "4" }, { value: 6, label: "6" }, { value: 10, label: "10" }]; current: Relay.rounds; accessibleLabel: "Rounds before pausing"; enabled: !Relay.running; onChosen: value => Config.set("relayRounds", value) } }
                    Item { Layout.fillWidth: true }
                    StationButton { text: "Start"; accent: Theme.green; checked: true; enabled: Relay.available && !Relay.running && goalField.text.trim() !== ""; hint: (Relay.solo ? Relay.agentName(Relay.preferredAgents) + " works turn after turn until it says done" : "Claude and Codex take turns until both say done") + " (Ctrl+Enter)"; onClicked: Relay.start(goalField.text) }
                }
                GlowText { text: (Relay.solo ? Relay.agentName(Relay.preferredAgents) + " works alone, turn after turn, as long as the goal takes." : "Claude and Codex share the goal and the checkout: they take turns, each reply is handed to the other, and each opens by acknowledging what the other just said.") + "  " + (Relay.preferredMode === "read" ? "Read: they may look but not change anything." : Relay.preferredMode === "edit" ? "Edit: files, git log/diff/add/commit, python and node inside the checkout." : "Full: no sandbox at all.") + "  Working in " + Relay.effectiveRepo + "."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                // Which model and effort each agent runs, for the agents in play.
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; implicitHeight: 1; color: Qt.alpha(Theme.teal, .12) }
                GridLayout {
                    Layout.fillWidth: true; columns: root.width < 900 ? 1 : 2; columnSpacing: 24; rowSpacing: 12
                    ModelPicker { visible: Relay.preferredAgents !== "codex"; agent: "claude"; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                    ModelPicker { visible: Relay.preferredAgents !== "claude"; agent: "codex"; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                }
            }
            Frame {
                visible: root.hasSession
                order: 1
                Layout.fillWidth: true
                topLineColor: root.stateTone
                stroke: Qt.alpha(root.stateTone, .22)
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "GOAL" }
                    Item { Layout.fillWidth: true }
                    StatusPill { text: Relay.soloSession ? Relay.agentName(Relay.agentsUsed) + " alone" : "Claude + Codex"; tone: Relay.soloSession ? root.agentTone(Relay.agentsUsed) : Theme.green }
                    StatusPill { visible: Relay.agentsUsed !== "codex" && Relay.modelLabel("claude") !== "default"; text: "Claude " + Relay.modelLabel("claude"); tone: Theme.amber }
                    StatusPill { visible: Relay.agentsUsed !== "claude" && Relay.modelLabel("codex") !== "default"; text: "Codex " + Relay.modelLabel("codex"); tone: Theme.teal }
                    StatusPill { text: Relay.mode; tone: Relay.mode === "full" ? Theme.warning : Theme.teal }
                    GlowText { visible: Relay.sessionName !== ""; text: Relay.sessionName.toUpperCase(); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted; elide: Text.ElideMiddle; Layout.maximumWidth: 260 } }
                GlowText { text: Relay.goal; font.family: Theme.labelFont; font.pixelSize: Math.round(17 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: Relay.repo; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
                // What this session has used so far, as each tool reports it.
                RowLayout {
                    visible: !!Relay.usage.claude || !!Relay.usage.codex
                    Layout.fillWidth: true; Layout.topMargin: 4; spacing: 24
                    Reading { visible: !!Relay.usage.claude; label: "Claude used"; value: Relay.usageLine("claude"); order: 2 }
                    Reading { visible: !!Relay.usage.codex; label: "Codex used"; value: Relay.usageLine("codex"); order: 2 }
                    Item { Layout.fillWidth: true }
                }
            }
            // The conversation (level 2 rows down a spine).
            Frame {
                visible: root.hasSession
                order: 2
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "CONVERSATION" }
                    Item { Layout.fillWidth: true }
                    GlowText { text: Relay.turns.length + (Relay.turns.length === 1 ? " TURN" : " TURNS"); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Repeater {
                        model: root.entries
                        TurnRow { last: index === root.entries.length - 1 && !Relay.busy }
                    }
                }
                // The running agent: its dot breathes, its tool activity trails beneath.
                Item {
                    visible: Relay.busy
                    Layout.fillWidth: true
                    implicitHeight: liveBody.implicitHeight + 12
                    Rectangle { x: 0; y: 10; width: 9; height: 9; radius: 4.5; color: root.agentTone(Relay.currentAgent); opacity: .45 + .55 * pulse.value }
                    Breath { id: pulse; running: Relay.busy && Motion.active; from: 0; to: 1; rise: 900; fall: 1300 }
                    ColumnLayout {
                        id: liveBody
                        x: 22; y: 4; width: parent.width - 22; spacing: 4
                        RowLayout { spacing: 10
                            GlowText { text: root.agentName(Relay.currentAgent).toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.6; color: root.agentTone(Relay.currentAgent) }
                            GlowText { text: root.unitWord + " " + Relay.currentRound; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                            GlowText { text: (Relay.activity.length ? "working" : "thinking") + (!Relay.soloSession && Relay.relays.length ? ", reading " + root.agentName(Relay.currentAgent === "claude" ? "codex" : "claude") + "'s reply" : ""); font.pixelSize: Theme.small; color: Theme.muted } }
                        Repeater {
                            model: Relay.activity.slice(-8)
                            GlowText { required property var modelData; text: modelData.text; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        }
                    }
                }
                GlowText { visible: !Relay.turns.length && !Relay.busy && Relay.running; text: "Starting the first turn…"; font.pixelSize: Theme.small; color: Theme.muted }
                GlowText { visible: Relay.error !== ""; text: Relay.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            // The person's line in: delivered with the next turn while live; picks the session back up when paused.
            Frame {
                visible: root.hasSession && (Relay.running || (Relay.sessionDir !== "" && Relay.finished !== ""))
                order: 3
                Layout.fillWidth: true
                SectionMark { text: Relay.running ? "STEP IN" : "PICK IT BACK UP"; tone: Theme.green }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Composer {
                        id: sayField
                        placeholder: Relay.running ? "A message for " + (Relay.soloSession ? Relay.agentName(Relay.agentsUsed) : "both agents") + ", delivered with the next turn" : "What should " + (Relay.soloSession ? Relay.agentName(Relay.agentsUsed) : "they") + " do next? Leave empty to continue as planned"
                        Layout.minimumHeight: 44
                        enabled: Relay.available
                        onSubmitted: { if (Relay.running) { if (Relay.say(text)) text = ""; } else { Relay.resume(Relay.sessionDir, text); text = ""; } }
                    }
                    StationButton { text: Relay.running ? "Send" : "Continue"; accent: Theme.green; checked: !Relay.running; enabled: Relay.running ? sayField.text.trim() !== "" : true; hint: Relay.running ? "Delivered as \"From the human\" with the next turn (Ctrl+Enter)" : (Relay.rounds > 0 ? "Resume this session for another " + Relay.rounds + " rounds" : "Resume this session until it is done"); onClicked: sayField.submitted() }
                }
                GlowText { visible: Relay.running; text: (Relay.soloSession ? "Your message is read before the next turn." : "Your message outranks whatever the other agent asked for.") + " Stop ends the session after the running turn."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }

    // --------------------------------------------------------------- sessions
    Component {
        id: sessionsPage
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Sessions"
                subtitle: Relay.sessions.length ? Relay.sessions.length + (Relay.sessions.length === 1 ? " recorded session" : " recorded sessions") + " under " + Relay.sessionsRoot : "Nothing recorded yet. Every session keeps a transcript, both agents' session ids and the raw event stream."
                StationButton { text: "Refresh"; hint: "Read the session folder again"; onClicked: Relay.refreshSessions() }
            }
            Frame {
                order: 1
                Layout.fillWidth: true
                padding: 14
                Repeater {
                    model: Relay.sessions
                    AbstractButton {
                        id: srow
                        required property var modelData
                        required property int index
                        readonly property color tone: modelData.finished === "done" ? Theme.success : modelData.finished === "error" ? Theme.danger : modelData.finished === "rounds" ? Theme.warning : Theme.inactive
                        Layout.fillWidth: true
                        implicitHeight: 44
                        leftPadding: 8; rightPadding: 8
                        hoverEnabled: true; activeFocusOnTab: true
                        enabled: !Relay.running
                        opacity: root.beat(1 + Math.min(index, 10) * .5, .35)
                        Accessible.name: modelData.goal
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: { Relay.load(modelData.dir); root.navigate("session"); }
                        background: Rectangle {
                            radius: Theme.controlRadius
                            color: srow.down ? Qt.alpha(Theme.teal, .12) : srow.hovered ? Qt.alpha(Theme.teal, .06) : Theme.transparent
                            border.width: srow.visualFocus ? Theme.focusWidth : 0; border.color: Theme.green
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            Rectangle { width: 8; height: 8; radius: 4; color: srow.tone }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                GlowText { text: srow.modelData.goal; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                GlowText { text: (srow.modelData.started || "").replace(/^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2}).*$/, "$1-$2-$3 $4:$5") + " · " + srow.modelData.mode + " · " + srow.modelData.turns + (srow.modelData.turns === 1 ? " turn" : " turns"); font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                            StatusPill { text: srow.modelData.finished || "open"; tone: srow.tone }
                            GlowText { text: "→"; font.pixelSize: Theme.small; color: Theme.teal; opacity: srow.hovered || srow.visualFocus ? 1 : .25 }
                        }
                    }
                }
                GlowText { visible: !Relay.sessions.length; text: "No sessions yet. Give the agents a goal on the Session page."; font.pixelSize: Theme.small; color: Theme.muted }
                GlowText { visible: Relay.running; text: "A session is running; it finishes or stops before another can be opened."; font.pixelSize: Theme.small; color: Theme.muted }
            }
        }
    }

    // --------------------------------------------------------------- settings
    Component {
        id: settings
        ColumnLayout {
            spacing: 22
            PageTitle { title: "Settings"; subtitle: "Where the agents work, what they may do, and how long they go before pausing." }
            Frame {
                order: 1
                Layout.fillWidth: true
                SectionMark { text: "CHECKOUT" }
                GlowText { text: "The repository both agents work in. Empty means the shell's own checkout."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                StationField { Layout.fillWidth: true; text: Config.saved.relayRepo; placeholderText: Relay.defaultRepo; enabled: !Relay.running; onCommit: value => Config.set("relayRepo", value.trim()) }
            }
            Frame {
                order: 2
                Layout.fillWidth: true
                SectionMark { text: "AGENTS" }
                GlowText { text: "WHO WORKS"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                ChoiceChips { options: [{ value: "both", label: "Both" }, { value: "claude", label: "Claude" }, { value: "codex", label: "Codex" }]; current: Relay.preferredAgents; accessibleLabel: "Which agents work on the goal"; enabled: !Relay.running; onChosen: value => Config.set("relayAgents", value) }
                GlowText { text: "Both: Claude and Codex share the goal and the checkout, take turns, and each reply is handed to the other, who acknowledges it before going on. Claude or Codex: that agent works alone, turn after turn."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: "ACCESS"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.topMargin: 4 }
                ChoiceChips { options: [{ value: "read", label: "Read" }, { value: "edit", label: "Edit" }, { value: "full", label: "Full" }]; current: Relay.preferredMode; accessibleLabel: "What the agents may do"; enabled: !Relay.running; onChosen: value => Config.set("relayMode", value) }
                GlowText { text: "Read lets them look. Edit adds file changes and git log, diff, add and commit, python and node, inside the checkout. Full removes every sandbox: Claude skips permission prompts and Codex bypasses its sandbox."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: "ROUNDS BEFORE PAUSING"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.topMargin: 4 }
                ChoiceChips { options: [{ value: 0, label: "Until done" }, { value: 2, label: "2" }, { value: 4, label: "4" }, { value: 6, label: "6" }, { value: 10, label: "10" }, { value: 16, label: "16" }]; current: Relay.rounds; accessibleLabel: "Rounds before pausing"; enabled: !Relay.running; onChosen: value => Config.set("relayRounds", value) }
                GlowText { text: "Until done lets a session run as long as the work takes; a turn has no time limit either, and Stop always ends it. A number pauses after that many rounds so you can look before continuing."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: "SPEAKS FIRST"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.topMargin: 4 }
                ChoiceChips { options: [{ value: "claude", label: "Claude" }, { value: "codex", label: "Codex" }]; current: Relay.first; accessibleLabel: "Which agent opens each round"; enabled: !Relay.running && !Relay.solo; onChosen: value => Config.set("relayFirst", value) }
            }
            Frame {
                order: 3
                Layout.fillWidth: true
                SectionMark { text: "MODELS" }
                GlowText { text: "Which model and effort each agent runs. Default is whatever the tool itself is set to; Claude's aliases name its latest models, Codex's list comes from its own model cache. A session keeps the models it started with when picked back up."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GridLayout {
                    Layout.fillWidth: true; columns: root.width < 900 ? 1 : 2; columnSpacing: 24; rowSpacing: 12
                    ModelPicker { agent: "claude"; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                    ModelPicker { agent: "codex"; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                }
            }
            Frame {
                order: 4
                Layout.fillWidth: true
                SectionMark { text: "TOOLS" }
                GridLayout { columns: root.width < 640 ? 1 : 2; columnSpacing: 20; rowSpacing: 8; Layout.fillWidth: true
                    Reading { label: "Claude Code"; value: Relay.tools.claude || (Relay.ready ? "Not found" : "—"); valueTone: Relay.tools.claude ? Theme.text : Theme.warning; order: 4 }
                    Reading { label: "Codex CLI"; value: Relay.tools.codex || (Relay.ready ? "Not found" : "—"); valueTone: Relay.tools.codex ? Theme.text : Theme.warning; order: 5 } }
                GlowText { text: "PLAN USAGE"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.topMargin: 4 }
                ColumnLayout {
                    visible: !!Relay.limits.claude
                    Layout.fillWidth: true; spacing: 4
                    GlowText { text: "CLAUDE"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.amber }
                    PlanBar { label: "5-hour"; fraction: Relay.limits.claude ? Relay.limits.claude.fiveHour : 0 }
                    PlanBar { label: "Week"; fraction: Relay.limits.claude ? Relay.limits.claude.sevenDay : 0 }
                    GlowText { text: Relay.limits.claude && Relay.limits.claude.at ? "Reported by Claude Code " + root.when(Relay.limits.claude.at) + "; it reports again on every turn." : ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
                GlowText { visible: !Relay.limits.claude; text: "Claude Code reports its 5-hour and weekly plan windows on every turn; the first session will fill this in."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: "Codex CLI reports the tokens each turn used, shown with the session, but no plan window; see its own /status for that."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                RowLayout { StationButton { text: "Look again"; onClicked: Relay.probe() } }
            }
            Frame {
                order: 5
                Layout.fillWidth: true
                SectionMark { text: "KEYBOARD" }
                GridLayout { columns: 2; columnSpacing: 20; rowSpacing: 8
                    Keycap { keys: "SUPER + SHIFT + A" } GlowText { text: "Open CEDAR AI"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "CTRL + ENTER" } GlowText { text: "Start the goal, or send your message"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "CTRL + 1" } GlowText { text: "Session, through Ctrl+3 for Settings"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "ESCAPE" } GlowText { text: "Close the window; a running session keeps going"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "CTRL + W" } GlowText { text: "Close CEDAR AI"; font.pixelSize: Theme.small; color: Theme.muted } }
            }
            Frame {
                order: 6
                Layout.fillWidth: true
                SectionMark { text: "ABOUT" }
                GlowText { text: "CEDAR AI runs Claude Code and Codex CLI headless, one at a time, in the same checkout. Each keeps its own session, so both remember the whole conversation and their own work. Whatever one writes as its final reply is handed to the other as the next message, and the conversation shows each hand-off. Either agent can also work alone. Neither commits or pushes unless the goal says so. The same relay is `cedar-ai` in a terminal; sessions are shared between the two."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
}
