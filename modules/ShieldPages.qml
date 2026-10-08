import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// The Shield application's content: a station rail and five pages. Overview
// answers "how protected am I" in two seconds and says what to do next;
// Protections, Network, Activity and Settings sit one level deeper, with a
// detail view per protection. Depth: the window is level 0, the chamfered
// frames level 1, the cards and rows level 2.
//
// Motion: one shared entrance clock (the Field Station pattern). Every
// instrument eases off `reveal`: the title settles, the filament lights from
// the left, the mark's branches light outward, rows stagger in and the counts
// count up, about a second once per page. Reduced Motion and test mode show
// the settled view on the first frame. Nothing loops; the mark is static
// after a transition and the atmosphere behind the window never moves.
FocusScope {
    id: root
    signal closed()
    property string page: "overview"
    property string detail: ""           // a protection id while a detail view is open
    readonly property bool sidebar: width >= 860
    readonly property int columns: width < 1180 && !sidebar ? (width < 640 ? 1 : 2) : width < 1180 ? 1 : 2
    readonly property var pages: [["overview", "Overview", "◇"], ["protections", "Protections", "⬡"], ["network", "Network", "⌁"], ["activity", "Activity", "◷"], ["settings", "Settings", "◈"]]
    function navigate(id) { page = id; detail = ""; }
    function tone(state) { return state === "on" ? Theme.success : state === "warn" ? Theme.warning : state === "fail" ? Theme.danger : state === "working" ? Theme.teal : Theme.inactive; }
    function word(state) { return ({ on: "Active", off: "Off", warn: "Check", fail: "Failed", unavailable: "Unavailable", working: "Working" })[state] || state; }
    function when(at) {
        const diff = Math.max(0, Date.now() - at), m = Math.floor(diff / 60000);
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Qt.formatDateTime(new Date(at), Config.clock24 ? "d MMM HH:mm" : "d MMM h:mm ap");
    }
    readonly property string postureState: Shield.posture === "protected" ? "on" : Shield.posture === "attention" ? "warn" : Shield.posture === "risk" ? "fail" : "working"
    readonly property color postureTone: tone(postureState)
    readonly property string postureSentence: Shield.posture === "protected" ? "Your system is protected." : Shield.posture === "attention" ? "Your system needs attention." : Shield.posture === "risk" ? "Your system is at risk." : "Reading your protections…"
    // The first thing worth doing, or nothing: a failed protection first, then
    // the first recommended one that is off.
    readonly property var nextStep: Shield.ready ? (Shield.failed[0] || Shield.recommendedOff[0] || null) : null

    // ---------------------------------------------------------- entrance
    property real reveal: 1
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    // Each instrument settles a beat after the last; `order` sets the beat.
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
    function consumeRequest() { if (Shield.requestedPage) { navigate(Shield.requestedPage); Shield.requestedPage = ""; } }
    Connections { target: Shield; function onRequestedPageChanged() { root.consumeRequest(); } }
    Component.onCompleted: { consumeRequest(); enter(1050); }
    onPageChanged: enter(700)
    onDetailChanged: enter(700)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { if (root.detail) root.detail = ""; else root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier) { root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) { Shield.refresh(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5 && event.modifiers & Qt.ControlModifier) { root.navigate(root.pages[event.key - Qt.Key_1][0]); event.accepted = true; }
    }

    // ------------------------------------------------------- vocabulary
    // A level-1 frame in the Core pill's silhouette with the short lit line at
    // its top edge. Pages are built from these; nothing else is boxed.
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
    // The page's title: spaced capitals that settle in from a wider spread, a
    // line beneath, and the filament lighting from the left under both.
    component PageTitle: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        property string crumb: ""
        default property alias actions: actionRow.data
        Layout.fillWidth: true
        spacing: 12
        RowLayout {
            Layout.fillWidth: true; spacing: 16
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                opacity: root.ease(0, .45)
                transform: Translate { y: 6 * (1 - root.ease(0, .45)) }
                GlowText { visible: crumb !== ""; text: crumb; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.teal }
                GlowText { text: title.toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 3 + 6 * (1 - root.ease(0, .6)); color: Theme.text }
                GlowText { visible: subtitle !== ""; text: subtitle; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            RowLayout { id: actionRow; spacing: 8; opacity: root.ease(.1, .4); Layout.alignment: Qt.AlignTop }
        }
        Filament {}
    }
    component Filament: Item {
        Layout.fillWidth: true; implicitHeight: 1
        Rectangle {
            width: parent.width * root.ease(.08, .5); height: 1; color: Qt.alpha(Theme.teal, .28)
            Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 120); height: 1; color: Theme.green; opacity: .8 * (1 - root.ease(.5, .4)) }
        }
    }
    // One protection as a row: state dot, label, value, and a way in. Keyboard
    // reachable; the arrow appears on hover or focus.
    component ProtectionRow: AbstractButton {
        id: prow
        required property var modelData
        property int order: 0
        Layout.fillWidth: true
        implicitHeight: 34
        leftPadding: 8; rightPadding: 8
        hoverEnabled: true; activeFocusOnTab: true
        opacity: root.beat(order, .35)
        Accessible.name: modelData.label + ": " + modelData.value
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        onClicked: root.detail = modelData.id
        background: Rectangle {
            radius: Theme.controlRadius
            color: prow.down ? Qt.alpha(Theme.teal, .12) : prow.hovered ? Qt.alpha(Theme.teal, .06) : Theme.transparent
            border.width: prow.visualFocus ? Theme.focusWidth : 0; border.color: Theme.green
        }
        contentItem: RowLayout {
            spacing: 10
            Rectangle { width: 8; height: 8; radius: 4; color: root.tone(prow.modelData.state); opacity: prow.modelData.state === "on" ? 1 : .55 }
            GlowText { text: prow.modelData.label; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
            GlowText { text: prow.modelData.value; color: prow.modelData.state === "on" ? Theme.success : prow.modelData.state === "warn" ? Theme.warning : prow.modelData.state === "fail" ? Theme.danger : Theme.muted; font.pixelSize: Theme.small; elide: Text.ElideRight; Layout.maximumWidth: 240; horizontalAlignment: Text.AlignRight }
            GlowText { text: "→"; font.pixelSize: Theme.small; color: Theme.teal; opacity: prow.hovered || prow.visualFocus ? 1 : .25 }
        }
    }
    // A reading that leads somewhere: the Quick Controls tile, grown up.
    component Tile: StationButton {
        id: tile
        property string label: ""
        property string value: ""
        property string detail: ""
        property bool lit: false
        property int order: 0
        Layout.fillWidth: true
        implicitHeight: 96
        padding: 14
        opacity: root.beat(order)
        scale: .96 + .04 * root.beat(order)
        Accessible.name: label + ": " + value + (detail ? ". " + detail : "")
        background: ChamferFrame {
            cut: 8
            fill: tile.down ? Theme.elevated : tile.hovered ? Qt.alpha(Theme.elevated, .9) : Qt.alpha(Theme.surface, .9)
            stroke: tile.visualFocus ? Theme.green : tile.hovered ? Qt.alpha(tile.accent, .55) : Qt.alpha(tile.accent, .22)
            strokeWidth: tile.visualFocus ? 2 : 1
            line: tile.lit; lineColor: tile.accent; lineFraction: .5
        }
        contentItem: ColumnLayout {
            spacing: 2
            Text { text: tile.label.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
            Text { Layout.fillWidth: true; text: tile.value; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); font.weight: Font.DemiBold; color: tile.lit ? tile.accent : Theme.text; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; visible: text !== ""; text: tile.detail; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.muted; elide: Text.ElideRight }
        }
    }
    // A quiet reading that goes nowhere.
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
    // Activity as a timeline: a spine, one dot per observation, newest first.
    component Timeline: ColumnLayout {
        id: timeline
        property var entries: []
        property int startOrder: 0
        spacing: 0
        Repeater {
            model: timeline.entries
            Item {
                id: entry
                required property var modelData
                required property int index
                readonly property color kindTone: modelData.kind === "failure" ? Theme.danger : modelData.kind === "on" ? Theme.success : modelData.kind === "network" || modelData.kind === "profile" ? Theme.teal : modelData.kind === "action" ? Theme.green : Theme.muted
                Layout.fillWidth: true
                implicitHeight: entryRow.implicitHeight + 16
                opacity: root.beat(timeline.startOrder + index * .5, .35)
                Rectangle { visible: entry.index < timeline.entries.length - 1; x: 3; y: 14; width: 1; height: parent.height - 14; color: Qt.alpha(Theme.teal, .18) }
                Rectangle { x: 0; y: 9; width: 7; height: 7; radius: 4; color: entry.kindTone }
                RowLayout {
                    id: entryRow
                    x: 20; y: 4; width: parent.width - 20; spacing: 12
                    ColumnLayout { Layout.fillWidth: true; spacing: 2
                        GlowText { text: entry.modelData.title; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        GlowText { visible: text !== ""; text: entry.modelData.detail || ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
                    GlowText { text: root.when(entry.modelData.at); font.pixelSize: Theme.small; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                }
            }
        }
    }

    // ------------------------------------------------------------ navigation
    component NavButton: StationButton {
        id: nav
        required property var modelData
        readonly property bool current: root.page === modelData[0]
        readonly property string badge: modelData[0] === "protections" && Shield.ready ? Shield.onCount + "/" + Shield.countable : ""
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
            Text { visible: root.sidebar && nav.badge !== ""; text: nav.badge; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1; color: Theme.muted }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        // The rail (level 1), only when wide: the mark, the pages, the posture.
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
                    ShieldMark { compact: true; implicitWidth: 30; implicitHeight: 36; interactive: false; outline: Qt.alpha(root.postureTone, .6) }
                    ColumnLayout { spacing: 0
                        GlowText { text: "SHIELD"; font.pixelSize: 12; font.letterSpacing: 2.6; color: Theme.teal }
                        GlowText { text: "CEDAR"; font.pixelSize: 9; font.letterSpacing: 1.8; color: Theme.muted } }
                }
                Repeater { model: root.pages.slice(0, 4); NavButton {} }
                Item { Layout.fillHeight: true }
                // Posture at a glance, wherever you are in the app.
                ColumnLayout {
                    Layout.fillWidth: true; Layout.bottomMargin: 10; spacing: 8
                    StatusPill { text: Shield.ready ? Shield.headline : "Reading"; tone: root.postureTone }
                    GlowText { visible: Shield.ready && Shield.data.verifiedAt > 0; text: "VERIFIED " + root.when(Shield.data.verifiedAt * 1000).toUpperCase(); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                    RowLayout { spacing: 6; Layout.fillWidth: true
                        Rectangle { width: 6; height: 6; radius: 3; color: Shield.publicNetwork ? Theme.warning : Theme.teal }
                        GlowText { text: Shield.networkLabel; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                }
                Repeater { model: root.pages.slice(4); NavButton {} }
                GlowText { text: Branding.content.identity || ""; font.pixelSize: 9; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.topMargin: 8 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0
            // Tab strip when narrow.
            RowLayout {
                visible: !root.sidebar
                Layout.fillWidth: true; Layout.margins: 12; spacing: 6
                Repeater { model: root.pages; NavButton {} }
                Item { Layout.fillWidth: true }
                StatusPill { text: Shield.ready ? Shield.headline : "Reading"; tone: root.postureTone }
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
                    sourceComponent: root.detail ? detailPage : ({ overview: overview, protections: protections, network: network, activity: activity, settings: settings })[root.page] || overview
                }
            }
        }
    }

    // --------------------------------------------------------------- overview
    Component {
        id: overview
        ColumnLayout {
            spacing: 24
            PageTitle {
                title: "Shield"; subtitle: root.postureSentence
                StatusPill { text: Shield.ready ? "Protection " + Math.round(100 * Shield.onCount * root.beat(2, .6) / Math.max(1, Shield.countable)) + "%" : "Reading"; tone: root.postureTone }
                StationButton { text: Shield.busy ? "Checking…" : "Check again"; hint: "Read every protection again (Ctrl+R)"; enabled: !Shield.busy; onClicked: Shield.refresh() }
            }
            GridLayout {
                id: hero
                Layout.fillWidth: true
                readonly property bool wide: root.width >= 820
                columns: wide ? 2 : 1; columnSpacing: 20; rowSpacing: 20
                // The centrepiece (level 1): the shield, the posture, the count.
                Frame {
                    order: 1
                    Layout.preferredWidth: hero.wide ? Math.round((hero.width - hero.columnSpacing) * .44) : hero.width
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.fillHeight: true
                    Layout.minimumHeight: 440
                    topLineColor: root.postureTone
                    stroke: Qt.alpha(root.postureTone, .22)
                    padding: 24
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 10
                        ShieldMark {
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8
                            implicitWidth: 200; implicitHeight: 236
                            reveal: root.ease(.1, .7)
                            outline: Qt.alpha(root.postureTone, .5)
                        }
                        // One tick per protection, in the mark's order: the state at a glance.
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 4; spacing: 5
                            Accessible.role: Accessible.StaticText
                            Accessible.name: Shield.onCount + " of " + Shield.countable + " protections active"
                            Repeater {
                                model: Shield.protections
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: 12; height: 3; radius: 1.5
                                    color: root.tone(modelData.state)
                                    opacity: (modelData.state === "on" ? 1 : modelData.state === "unavailable" ? .25 : .7) * root.beat(3 + index * .3, .3)
                                }
                            }
                        }
                        GlowText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; text: Shield.headline.toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 2 + 6 * (1 - root.ease(.3, .5)); color: root.postureTone; opacity: root.ease(.3, .4) }
                        GlowText { Layout.alignment: Qt.AlignHCenter; text: Shield.subline; font.pixelSize: Theme.small; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 280; wrapMode: Text.WordWrap; opacity: root.ease(.4, .4) }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 10; spacing: 24
                            opacity: root.ease(.5, .4)
                            Reading { label: "Active"; value: Shield.ready ? Math.round(Shield.onCount * root.beat(6, .6)) + " of " + Shield.countable : "—"; valueTone: Theme.text; order: 6 }
                            Reading { label: "Network"; value: Shield.ready ? (Shield.publicNetwork ? "Public" : "Trusted") : "—"; valueTone: Shield.publicNetwork ? Theme.warning : Theme.text; order: 7 }
                            Reading { label: "Verified"; value: Shield.ready && Shield.data.verifiedAt > 0 ? root.when(Shield.data.verifiedAt * 1000) : "—"; order: 8 }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: hero.wide ? hero.width - hero.columnSpacing - Math.round((hero.width - hero.columnSpacing) * .44) : hero.width
                    spacing: 16
                    // What to do next, only while there is something to do.
                    Frame {
                        id: nextStepFrame
                        visible: !!root.nextStep
                        order: 2
                        Layout.fillWidth: true
                        readonly property var step: root.nextStep || ({ id: "", label: "", value: "", detail: "", reason: "", state: "off" })
                        readonly property color stepTone: step.state === "fail" ? Theme.danger : Theme.warning
                        topLineColor: stepTone
                        stroke: Qt.alpha(stepTone, .3)
                        padding: 18
                        RowLayout { Layout.fillWidth: true
                            SectionMark { text: nextStepFrame.step.state === "fail" ? "NEEDS FIXING" : "NEXT STEP"; tone: nextStepFrame.stepTone }
                            Item { Layout.fillWidth: true }
                            GlowText { visible: Shield.recommendedOff.length > 1; text: Shield.recommendedOff.length + " RECOMMENDED OFF"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                        GlowText { text: nextStepFrame.step.label + " · " + nextStepFrame.step.value; font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        GlowText { text: nextStepFrame.step.reason || nextStepFrame.step.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        RowLayout { spacing: 8; Layout.topMargin: 4
                            StationButton { visible: nextStepFrame.step.state !== "fail" && !!Shield.recommendedOff.length; text: Shield.busy ? "Working…" : "Turn on"; accent: Theme.green; checked: true; enabled: !Shield.busy; hint: "Runs the provider's own command, verified"; onClicked: Shield.applyRecommended() }
                            StationButton { text: "Open " + nextStepFrame.step.label; onClicked: root.detail = nextStepFrame.step.id } }
                    }
                    // The network and privacy protections as rows that open (level 2).
                    Frame {
                        order: 3
                        Layout.fillWidth: true
                        padding: 18
                        RowLayout { Layout.fillWidth: true
                            SectionMark { text: "PROTECTIONS" }
                            Item { Layout.fillWidth: true }
                            StationButton { text: "All " + Shield.protections.length + " →"; implicitHeight: 28; onClicked: root.navigate("protections") } }
                        Repeater {
                            model: ["firewall", "dns", "discovery", "wifi", "ipv6", "vpn"].map(id => Shield.protection(id)).filter(Boolean)
                            ProtectionRow { required property int index; order: 4 + index }
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 12
                        Tile { label: "Network"; value: Shield.ready ? (Shield.publicNetwork ? "Public" : "Trusted") : "—"; detail: Shield.networkLabel; accent: Shield.publicNetwork ? Theme.warning : Theme.teal; lit: Shield.publicNetwork; order: 9; hint: "Network profile and exposure"; onClicked: root.navigate("network") }
                        Tile { label: "Exposure"; value: Shield.exposure ? Shield.exposedCount + (Shield.exposedCount === 1 ? " service" : " services") : "Not scanned"; detail: Shield.exposure ? (Shield.exposedCount ? "visible to your network" : "Everything stays local") : ""; accent: Shield.exposedCount ? Theme.warning : Theme.teal; lit: Shield.exposedCount > 0; order: 10; hint: "What listens on your network"; onClicked: root.detail = "exposure" }
                    }
                }
            }
            GlowText { visible: Shield.error !== ""; text: Shield.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                opacity: root.beat(11)
                RowLayout { Layout.fillWidth: true; SectionMark { text: "RECENT ACTIVITY" } Item { Layout.fillWidth: true } StationButton { text: "All activity →"; implicitHeight: 28; visible: Shield.activity.length > 3; onClicked: root.navigate("activity") } }
                Timeline { Layout.fillWidth: true; entries: Shield.activity.slice(0, 3); startOrder: 12 }
                GlowText { visible: !Shield.activity.length; text: "Nothing observed yet. Shield records only what it sees: a protection changing, an action and its result, a network change."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }

    // ------------------------------------------------------------ protections
    Component {
        id: protections
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Protections"; subtitle: Shield.onCount + " of " + Shield.countable + " active · open a card for its controls and technical details"
                StationButton { text: Shield.busy ? "Checking…" : "Check again"; hint: "Read every protection again (Ctrl+R)"; enabled: !Shield.busy; onClicked: Shield.refresh() }
            }
            Repeater {
                model: Shield.groups
                ColumnLayout {
                    id: group
                    required property string modelData
                    required property int index
                    readonly property var rows: Shield.protections.filter(p => p.group === modelData)
                    Layout.fillWidth: true; spacing: 10
                    opacity: root.beat(1 + index * 2)
                    RowLayout { Layout.fillWidth: true
                        SectionMark { text: group.modelData.toUpperCase() }
                        Item { Layout.fillWidth: true }
                        GlowText { text: group.rows.filter(p => p.state === "on").length + " OF " + group.rows.filter(p => p.state !== "unavailable").length + " ACTIVE"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                    GridLayout {
                        Layout.fillWidth: true; columns: root.columns; columnSpacing: 12; rowSpacing: 12; uniformCellWidths: true
                        Repeater {
                            model: group.rows
                            ProtectionCard {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                                label: modelData.label; state: modelData.state; value: modelData.value; detail: modelData.provider; reason: ""
                                recommended: modelData.recommended
                                interactive: true
                                reveal: root.beat(2 + group.index * 2 + index * .5, .4)
                                onOpened: root.detail = modelData.id
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- detail view
    Component {
        id: detailPage
        ColumnLayout {
            readonly property var p: Shield.protection(root.detail) || Shield.protections[0]
            readonly property string id: p.id
            readonly property bool hasControls: !!({ firewall: 1, dns: 1, wifi: 1, ipv6: 1, discovery: 1, exposure: 1, lock: 1, idle: 1, local: 1, clipboard: 1, trails: 1 })[id]
            spacing: 20
            PageTitle {
                crumb: "PROTECTIONS / " + p.group.toUpperCase()
                title: p.label
                StationButton { text: "← Back"; hint: "Back to the list (Escape)"; onClicked: root.detail = "" }
            }
            Frame {
                order: 1
                Layout.fillWidth: true
                topLineColor: root.tone(p.state)
                stroke: Qt.alpha(root.tone(p.state), .25)
                padding: 24
                RowLayout {
                    Layout.fillWidth: true; spacing: 24
                    ShieldMark { Layout.alignment: Qt.AlignTop; compact: true; implicitWidth: 84; implicitHeight: 100; highlight: id; outline: Qt.alpha(root.tone(p.state), .5); reveal: root.ease(.1, .6) }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        RowLayout { spacing: 10
                            StatusPill { text: root.word(p.state); tone: root.tone(p.state) }
                            GlowText { visible: p.recommended; text: Shield.publicNetwork ? "RECOMMENDED ON PUBLIC NETWORKS" : "RECOMMENDED"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.teal } }
                        GlowText { text: p.value; font.family: Theme.labelFont; font.pixelSize: Math.round(24 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        GlowText { visible: p.detail !== ""; text: p.detail; font.pixelSize: Theme.normal; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        GlowText { visible: p.reason !== ""; text: p.reason; font.pixelSize: Theme.small; color: p.state === "fail" ? Theme.danger : Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true; columns: root.width < 640 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
                Frame { order: 2; Layout.fillWidth: true; padding: 14; Reading { label: "Provider"; value: p.provider || "—"; order: 2 } }
                Frame { order: 3; Layout.fillWidth: true; padding: 14; Reading { label: "On this network"; value: p.recommended ? "Recommended" : "Optional"; valueTone: p.recommended && (p.state === "off" || p.state === "warn") ? Theme.warning : Theme.text; order: 3 } }
                Frame { order: 4; Layout.fillWidth: true; padding: 14; Reading { label: "Verified"; value: Shield.data.verifiedAt ? root.when(Shield.data.verifiedAt * 1000) : "Not yet"; order: 4 } }
            }
            // Controls: each one enters a working state, the provider verifies, then the card says so.
            Frame {
                order: 5
                Layout.fillWidth: true
                SectionMark { text: "CONTROLS" }
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: ({ firewall: firewallControls, dns: dnsControls, wifi: wifiControls, ipv6: ipv6Controls, discovery: discoveryControls, exposure: exposureControls, lock: lockControls, idle: idleControls, local: localControls, clipboard: clipboardControls, trails: trailsControls })[id] || null
                }
                GlowText { visible: id === "vpn"; text: "VPN connections are managed from Connections on the bar; Shield only reports whether one is carrying your traffic."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: id === "wifi" && !(Shield.wifi && Shield.wifi.available && Shield.wifi.connection); text: Shield.wifi && Shield.wifi.available ? "The policy applies once a Wi-Fi network has been saved." : "No Wi-Fi device was found, so there is no address to make private."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: id === "dns" && !Shield.dnsSupported; text: "Encrypted DNS needs systemd-resolved behind NetworkManager; the current resolver does not support it."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: Shield.error !== ""; text: Shield.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            ExpandableDetails {
                Layout.fillWidth: true; label: "Technical details"
                opacity: root.beat(6)
                Repeater {
                    model: root.technical(id)
                    RowLayout { required property var modelData; Layout.fillWidth: true
                        GlowText { text: modelData[0]; font.pixelSize: Theme.small; color: Theme.muted; Layout.preferredWidth: 160 }
                        GlowText { text: modelData[1]; font.pixelSize: Theme.small; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere } }
                }
            }
        }
    }
    function technical(id) {
        const verified = Shield.data.verifiedAt ? ["Last verified", root.when(Shield.data.verifiedAt * 1000)] : null;
        const rows = ({
            firewall: Shield.firewall ? [["Provider", Shield.firewall.provider], ["Owner", Shield.firewall.owner], ["Unit", Shield.firewall.unit || "—"], ["Running", String(Shield.firewall.active)]].concat((Shield.firewall.providers || []).map(f => ["Installed", f.provider + " · " + (f.active ? "running" : "stopped") + (f.enabled ? " · at boot" : "") + (f.configured ? " · configured" : "")])) : [],
            dns: Shield.dns ? [["Resolver", Shield.dns.resolver], ["Link", Shield.dns.link || "—"], ["Servers", (Shield.dns.servers || []).join("  ") || "—"], ["Mode", Shield.dns.mode], ["Connection", Shield.dns.connection ? Shield.dns.connection.name + " · dns-over-tls " + Shield.dns.connection.dnsOverTls + " · ignore-auto-dns " + Shield.dns.connection.ignoreAutoDns : "—"], ["DNS-over-HTTPS", "not offered: neither resolved nor NetworkManager speaks it"]] : [],
            discovery: Shield.discovery ? [["Avahi", Shield.discovery.avahi ? "running" : "stopped"], ["resolved mDNS", String(Shield.discovery.mdns)], ["resolved LLMNR", String(Shield.discovery.llmnr)], ["Connection setting", "mdns " + Shield.discovery.setting.mdns + " · llmnr " + Shield.discovery.setting.llmnr]] : [],
            exposure: Shield.exposure ? [["Scanned", Shield.scannedAt ? root.when(Shield.scannedAt) : "—"], ["Localhost only", String(Shield.exposure.local)], ["This network", String(Shield.exposure.lan)], ["Every interface", String(Shield.exposure.all)]].concat(Shield.exposure.listeners.filter(l => l.scope !== "local").slice(0, 40).map(l => [l.proto.toUpperCase() + " " + l.port, l.bind + (l.process ? " · " + l.process : "") + (l.scope === "all" ? " · every interface" : " · this network")])) : [],
            wifi: Shield.wifi ? [["Device", Shield.wifi.device || "—"], ["Profile", Shield.wifi.connection || "—"], ["cloned-mac-address", Shield.wifi.raw || "(default)"]] : [],
            ipv6: Shield.ipv6 ? [["ipv6.ip6-privacy", Shield.ipv6.setting || "—"], ["Kernel use_tempaddr", Shield.ipv6.kernel || "—"], ["Effective", Shield.ipv6.effective || "—"]] : [],
            vpn: [["Active VPNs", String((Network.data.status?.vpns || []).map(v => v.name).join(", ") || "none")]],
            lock: [["Setting", "lockPrivacy = " + Config.saved.lockPrivacy]], idle: [["Setting", "idleLockSeconds = " + Config.idleLockSeconds]],
            local: [["Setting", "localOnly = " + Config.localOnly]], clipboard: [["Setting", "clipboardHistory = " + Config.saved.clipboardHistory]], trails: [["Setting", "forestTrails = " + Config.saved.forestTrails]]
        })[id] || [];
        return verified ? rows.concat([verified]) : rows;
    }
    Component { id: firewallControls; ColumnLayout { spacing: 8
        StationToggle { Layout.fillWidth: true; label: Shield.firewallOn ? "Firewall on" : "Turn the firewall on"; description: Shield.firewall && Shield.firewall.available ? "Uses " + (Shield.firewallManager || "the installed manager") + "'s own command through pkexec; you will be asked for permission." : "Install ufw, firewalld or nftables, then check again."; checked: Shield.firewallOn; busy: Shield.working === "firewall"; enabled: !Shield.busy && !!Shield.firewall && Shield.firewall.available && Capabilities.canElevate; onToggled: Shield.setFirewall(!Shield.firewallOn) }
        GlowText { visible: Capabilities.ready && !Capabilities.canElevate; text: Capabilities.privilege.helper === "pkexec" ? "No authentication agent is registered, so permission cannot be asked for yet." : "pkexec is not installed, so the firewall cannot be changed from here."; color: Theme.warning; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap } } }
    Component { id: dnsControls; ColumnLayout { spacing: 8; visible: Shield.dnsSupported
        GlowText { text: "PROVIDER"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        ChoiceChips { options: [{ value: "cloudflare", label: "Cloudflare" }, { value: "quad9", label: "Quad9" }, { value: "mullvad", label: "Mullvad" }]; current: Config.saved.shieldDnsProvider; accessibleLabel: "DNS-over-TLS provider"; enabled: !Shield.busy; onChosen: value => Config.set("shieldDnsProvider", value) }
        GlowText { text: "MODE"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted; Layout.topMargin: 4 }
        RowLayout { spacing: 6
            StationButton { text: "Strict"; hint: "DNS-over-TLS only; never falls back to plain DNS"; checked: Shield.dns && Shield.dns.mode === "strict"; enabled: !Shield.busy; onClicked: Shield.setDns("strict") }
            StationButton { text: "Opportunistic"; hint: "Tries TLS first, falls back when it fails"; checked: Shield.dns && Shield.dns.mode === "opportunistic"; enabled: !Shield.busy; onClicked: Shield.setDns("opportunistic") }
            StationButton { text: "Off"; hint: "Back to the network's own DNS"; checked: Shield.dns && Shield.dns.mode === "off"; enabled: !Shield.busy; onClicked: Shield.setDns("off") } }
        GlowText { text: Shield.dns && Shield.dns.mode === "strict" ? "Strict never falls back to plain DNS, so a network that blocks TLS on port 853 will fail lookups until you switch." : "Opportunistic keeps lookups working everywhere but can fall back to plain DNS without telling you."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } } }
    Component { id: wifiControls; GridLayout { columns: root.width < 640 ? 1 : 2; columnSpacing: 6; rowSpacing: 6; visible: !!Shield.wifi && Shield.wifi.available && !!Shield.wifi.connection
        Repeater { model: [["stable", "Stable private", "One private address, kept for this network"], ["random", "Randomized", "A different private address as NetworkManager allows"], ["hardware", "Hardware", "The physical interface address"], ["default", "System default", "Whatever NetworkManager's default is"]]
            StationButton { required property var modelData; Layout.fillWidth: true; text: modelData[1]; hint: modelData[2]; checked: Shield.wifiPolicy === modelData[0]; enabled: !Shield.busy; onClicked: Shield.setWifiPolicy(modelData[0]) } } } }
    Component { id: ipv6Controls; StationToggle { label: Shield.ipv6 && Shield.ipv6.active ? "Temporary addresses on" : "Use temporary addresses"; description: "NetworkManager's ipv6.ip6-privacy on the active connection, reapplied without dropping the link."; checked: !!Shield.ipv6 && Shield.ipv6.active; busy: Shield.working === "ipv6"; enabled: !Shield.busy && !!Shield.ipv6 && Shield.ipv6.available; onToggled: Shield.setIpv6(!(Shield.ipv6 && Shield.ipv6.active)) } }
    Component { id: discoveryControls; StationToggle { label: Shield.discovery && Shield.discovery.answering ? "Answering name queries" : "Not answering name queries"; description: "mDNS and LLMNR on the active connection through NetworkManager; Avahi is stopped through pkexec when it is running."; checked: !!Shield.discovery && Shield.discovery.answering; busy: Shield.working === "discovery"; enabled: !Shield.busy && !!Shield.discovery && Shield.discovery.available; onToggled: Shield.setDiscovery(!(Shield.discovery && Shield.discovery.answering)) } }
    Component { id: exposureControls; ColumnLayout { spacing: 10
        GridLayout { columns: root.width < 640 ? 1 : 3; columnSpacing: 12; rowSpacing: 8; Layout.fillWidth: true
            Reading { label: "Localhost only"; value: Shield.exposure ? String(Shield.exposure.local) : "—"; order: 5 }
            Reading { label: "This network"; value: Shield.exposure ? String(Shield.exposure.lan) : "—"; valueTone: Shield.exposure && Shield.exposure.lan ? Theme.warning : Theme.text; order: 6 }
            Reading { label: "Every interface"; value: Shield.exposure ? String(Shield.exposure.all) : "—"; valueTone: Shield.exposure && Shield.exposure.all ? Theme.warning : Theme.text; order: 7 } }
        GlowText { text: "Shield cannot close a port; the service that opened it owns it. The firewall decides who reaches it, and the list under Technical details names each one."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        RowLayout { StationButton { text: Shield.busy ? "Scanning…" : "Scan again"; enabled: !Shield.busy; onClicked: Shield.rescan() } StationButton { text: "Open Firewall →"; onClicked: root.detail = "firewall" } } } }
    Component { id: lockControls; StationToggle { label: "Hide details while locked"; description: "Media, events, reminders and device names stay off the lock screen."; checked: Config.saved.lockPrivacy; onToggled: Config.set("lockPrivacy", !Config.saved.lockPrivacy) } }
    Component { id: idleControls; ColumnLayout { spacing: 8
        GlowText { text: "LOCK AFTER"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        ChoiceChips { options: [{ value: 0, label: "Never" }, { value: 300, label: "5 min" }, { value: 600, label: "10 min" }, { value: 1800, label: "30 min" }]; current: Config.idleLockSeconds; accessibleLabel: "Lock after inactivity"; onChosen: value => Config.set("idleLockSeconds", value) }
        GlowText { visible: ![0, 300, 600, 1800].includes(Config.idleLockSeconds); text: "Currently " + Math.round(Config.idleLockSeconds / 60) + " min, set in Settings › Power."; font.pixelSize: Theme.small; color: Theme.muted } } }
    Component { id: localControls; StationToggle { label: "Local-only mode"; description: "No weather, location or artwork requests leave this computer."; checked: Config.saved.localOnly; onToggled: Config.set("localOnly", !Config.saved.localOnly) } }
    Component { id: clipboardControls; StationToggle { label: "Keep clipboard history"; description: "Off means nothing you copy is kept by CEDAR."; checked: Config.saved.clipboardHistory; onToggled: Config.set("clipboardHistory", !Config.saved.clipboardHistory) } }
    Component { id: trailsControls; StationToggle { label: "Record activity trails"; description: "Off means nothing you open is recorded."; checked: Config.saved.forestTrails; onToggled: Config.set("forestTrails", !Config.saved.forestTrails) } }

    // ---------------------------------------------------------------- network
    Component {
        id: network
        ColumnLayout {
            spacing: 22
            PageTitle { title: "Network"; subtitle: "The connection Shield is protecting, and what this network recommends." }
            Frame {
                order: 1
                Layout.fillWidth: true
                topLineColor: Shield.publicNetwork ? Theme.warning : Theme.teal
                padding: 24
                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    ColumnLayout { Layout.fillWidth: true; spacing: 4
                        GlowText { text: Shield.networkLabel; font.family: Theme.labelFont; font.pixelSize: Math.round(24 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        GlowText { text: (Shield.connection ? Shield.connection.type.replace("802-3-ethernet", "WIRED").replace("802-11-wireless", "WI-FI").toUpperCase() + (Shield.connection.device ? " · " + Shield.connection.device.toUpperCase() : "") : "NO ACTIVE CONNECTION"); font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted } }
                    StatusPill { text: Shield.publicNetwork ? "Public" : "Trusted"; tone: Shield.publicNetwork ? Theme.warning : Theme.success }
                }
                Filament {}
                Repeater {
                    model: ["firewall", "dns", "discovery", "wifi", "ipv6", "vpn"].map(id => Shield.protection(id)).filter(Boolean)
                    ProtectionRow { required property int index; order: 2 + index }
                }
            }
            Frame {
                order: 4
                Layout.fillWidth: true
                SectionMark { text: "NETWORK PROFILE" }
                GlowText { text: "Trusted asks for the firewall and the session protections. Public also recommends strict encrypted DNS, no discovery answers and temporary IPv6 addresses. The profile is remembered for this connection."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                RowLayout { Layout.fillWidth: true; spacing: 12
                    ChoiceChips { options: [{ value: "trusted", label: "Trusted" }, { value: "public", label: "Public" }]; current: Shield.profile; accessibleLabel: "Network profile"; enabled: !!Shield.connectionKey; onChosen: value => Shield.setProfile(value) }
                    Item { Layout.fillWidth: true }
                    StationButton { visible: Shield.recommendedOff.length > 0; text: Shield.busy ? "Working…" : "Apply recommended (" + Shield.recommendedOff.length + ")"; accent: Theme.green; checked: true; enabled: !Shield.busy; hint: "One verified step at a time, starting with the first"; onClicked: Shield.applyRecommended() } }
                GlowText { visible: Shield.recommendedOff.length > 0; text: "Will turn on, one at a time: " + Shield.recommendedOff.map(p => p.label).join(", ") + "."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: !Shield.connectionKey; text: "No active NetworkManager connection to attach a profile to."; font.pixelSize: Theme.small; color: Theme.muted }
            }
            Frame {
                order: 5
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "LOCAL EXPOSURE"; tone: Shield.exposedCount ? Theme.warning : Theme.teal }
                    Item { Layout.fillWidth: true }
                    GlowText { visible: Shield.scannedAt > 0; text: "SCANNED " + root.when(Shield.scannedAt).toUpperCase(); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                GridLayout { columns: root.width < 640 ? 1 : 3; columnSpacing: 12; rowSpacing: 8; Layout.fillWidth: true
                    Reading { label: "Localhost only"; value: Shield.exposure ? String(Shield.exposure.local) : "—"; order: 6 }
                    Reading { label: "This network"; value: Shield.exposure ? String(Shield.exposure.lan) : "—"; valueTone: Shield.exposure && Shield.exposure.lan ? Theme.warning : Theme.text; order: 7 }
                    Reading { label: "Every interface"; value: Shield.exposure ? String(Shield.exposure.all) : "—"; valueTone: Shield.exposure && Shield.exposure.all ? Theme.warning : Theme.text; order: 8 } }
                GlowText { visible: !Shield.exposure; text: "Not scanned yet."; font.pixelSize: Theme.small; color: Theme.muted }
                RowLayout { spacing: 8; StationButton { text: "View services →"; onClicked: root.detail = "exposure" } StationButton { text: Shield.busy ? "Scanning…" : "Scan again"; enabled: !Shield.busy; onClicked: Shield.rescan() } }
            }
        }
    }

    // --------------------------------------------------------------- activity
    Component {
        id: activity
        ColumnLayout {
            spacing: 22
            PageTitle { title: "Activity"; subtitle: "Only what Shield observed: a protection changing between two reads, an action and its result, a network or profile change. No invented events." }
            Frame {
                order: 1
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "OBSERVED" }
                    Item { Layout.fillWidth: true }
                    GlowText { text: Shield.activity.length + (Shield.activity.length === 1 ? " ENTRY" : " ENTRIES") + " · LAST 100 KEPT"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                Timeline { Layout.fillWidth: true; entries: Shield.activity; startOrder: 2 }
                GlowText { visible: !Shield.activity.length; text: "Nothing observed yet."; color: Theme.muted }
            }
        }
    }

    // --------------------------------------------------------------- settings
    Component {
        id: settings
        ColumnLayout {
            spacing: 22
            PageTitle { title: "Settings"; subtitle: "How Shield watches and which provider it prefers. Each protection's own switches live on its page." }
            Frame {
                order: 1
                Layout.fillWidth: true
                SectionMark { text: "WATCHING" }
                StationToggle { Layout.fillWidth: true; label: "Reassess when the network changes"; description: "One fresh read after a network change, even while this window is closed, so the Quick Controls tile and the activity log stay true."; checked: Config.saved.shieldWatchNetwork; onToggled: Config.set("shieldWatchNetwork", !Config.saved.shieldWatchNetwork) }
            }
            Frame {
                order: 2
                Layout.fillWidth: true
                SectionMark { text: "ENCRYPTED DNS" }
                GlowText { text: "The DNS-over-TLS provider used when encrypted DNS is turned on or applied as recommended."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                ChoiceChips { options: [{ value: "cloudflare", label: "Cloudflare" }, { value: "quad9", label: "Quad9" }, { value: "mullvad", label: "Mullvad" }]; current: Config.saved.shieldDnsProvider; accessibleLabel: "Preferred DNS-over-TLS provider"; onChosen: value => Config.set("shieldDnsProvider", value) }
            }
            Frame {
                order: 3
                Layout.fillWidth: true
                SectionMark { text: "KEYBOARD" }
                GridLayout { columns: 2; columnSpacing: 20; rowSpacing: 8
                    Keycap { keys: "CTRL + 1" } GlowText { text: "Overview, through Ctrl+5 for Settings"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "CTRL + R" } GlowText { text: "Check every protection again"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "ESCAPE" } GlowText { text: "Back from a detail view, then close"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "CTRL + W" } GlowText { text: "Close Shield"; font.pixelSize: Theme.small; color: Theme.muted }
                    Keycap { keys: "TAB" } GlowText { text: "Move between rows, cards and controls"; font.pixelSize: Theme.small; color: Theme.muted } }
            }
            Frame {
                order: 4
                Layout.fillWidth: true
                SectionMark { text: "ABOUT" }
                GlowText { text: "CEDAR Shield is a presentation over the services that own each protection: the firewall manager, systemd-resolved behind NetworkManager, the Wi-Fi profile, the kernel's socket tables and CEDAR's own settings. Closing this window or restarting the shell changes none of them. Nothing polls; Shield reads when it opens, when you ask, after an action and once after a network change."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
}
