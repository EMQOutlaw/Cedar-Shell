import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR Station's content: a rail and five pages. Health answers "is this
// desktop well" with the live readings, the services and the issues;
// Services, Issues, Log and Report sit one level deeper. The same station
// language as Shield: chamfered frames with the lit top edge, one shared
// entrance clock, nothing that loops. The CPU and memory traces draw only
// while the window is open, at SystemStats' instrument cadence.
FocusScope {
    id: root
    signal closed()
    property string page: "overview"
    readonly property bool sidebar: width >= 860
    readonly property var pages: [["overview", "Health", "✚"], ["services", "Services", "⚙"], ["issues", "Issues", "!"], ["log", "Log", "≡"], ["report", "Report", "▤"]]
    function navigate(id) { page = id; }
    function consumeRequest() { if (Station.requestedPage) { navigate(Station.requestedPage); Station.requestedPage = ""; } }
    Connections { target: Station; function onRequestedPageChanged() { root.consumeRequest(); } }
    readonly property string statusState: Station.status === "healthy" ? "on" : Station.status === "attention" ? "warn" : Station.status === "risk" ? "fail" : "working"
    readonly property color statusTone: statusState === "on" ? Theme.success : statusState === "warn" ? Theme.warning : statusState === "fail" ? Theme.danger : Theme.teal
    function severityTone(s) { return s === "critical" ? Theme.danger : s === "warning" ? Theme.warning : Theme.teal; }
    function serviceTone(status) { return status === "Healthy" ? Theme.success : status === "Failed" ? Theme.danger : status === "Unavailable" ? Theme.muted : Theme.warning; }
    function when(at) {
        const diff = Math.max(0, Date.now() - at), m = Math.floor(diff / 60000);
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : Math.floor(m / 60) + " h ago";
    }
    property string confirmRestart: ""

    property real reveal: 1
    function ease(start, span) { const t = Math.max(0, Math.min(1, (reveal - start) / span)); return 1 - Math.pow(1 - t, 3); }
    function beat(order, span = .4) { return ease(.06 * order, span); }
    function enter(duration) { entrance.stop(); if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; } entrance.duration = duration; reveal = 0; entrance.start(); }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    Component.onCompleted: { consumeRequest(); enter(1050); }
    onPageChanged: enter(700)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier)) { root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) { Station.refresh(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5 && event.modifiers & Qt.ControlModifier) { root.navigate(root.pages[event.key - Qt.Key_1][0]); event.accepted = true; }
    }

    component Frame: ChamferFrame {
        property int order: 0
        property int padding: 20
        default property alias content: frameBody.data
        cut: 10; fill: Qt.alpha(Theme.surface, .88); stroke: Qt.alpha(Theme.teal, .16)
        topLine: true; topLineColor: Theme.teal
        implicitHeight: frameBody.implicitHeight + padding * 2
        opacity: root.beat(order)
        transform: Translate { y: 6 * (1 - root.beat(order)) }
        ColumnLayout { id: frameBody; anchors { left: parent.left; right: parent.right; top: parent.top; margins: padding } spacing: 10 }
    }
    component PageTitle: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        default property alias actions: actionRow.data
        Layout.fillWidth: true; spacing: 12
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
        Item { Layout.fillWidth: true; implicitHeight: 1
            Rectangle { width: parent.width * root.ease(.08, .5); height: 1; color: Qt.alpha(Theme.teal, .28)
                Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 120); height: 1; color: Theme.green; opacity: .8 * (1 - root.ease(.5, .4)) } } }
    }
    // A live reading: label, value, an optional trace beneath that draws only while shown.
    component Metric: ColumnLayout {
        property string label: ""
        property string value: ""
        property string detail: ""
        property real trace: -1       // 0 … 1 to draw a trace, -1 for none
        property color valueTone: Theme.text
        property int order: 0
        Layout.fillWidth: true; spacing: 4
        opacity: root.beat(order, .35)
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + value + (detail ? ". " + detail : "")
        GlowText { text: label.toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        GlowText { text: value; font.family: Theme.labelFont; font.pixelSize: Math.round(21 * Theme.fontScale); font.weight: Font.DemiBold; color: valueTone; Layout.fillWidth: true; elide: Text.ElideRight }
        ActivityTrace { visible: trace >= 0; Layout.fillWidth: true; implicitHeight: 22; active: visible && Station.open; value: trace }
        GlowText { visible: detail !== ""; text: detail; font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
    }
    // One issue: what, why, verified, the action and whether it needs permission.
    component IssueCard: ChamferFrame {
        id: card
        required property var modelData
        required property int index
        property bool expanded: false
        Layout.fillWidth: true
        cut: 9
        implicitHeight: issueBody.implicitHeight + 32
        fill: Qt.alpha(Theme.surface, .85)
        stroke: Qt.alpha(root.severityTone(modelData.severity), .35)
        topLine: true; topLineColor: root.severityTone(modelData.severity); topLineFraction: .22
        opacity: root.beat(2 + index * .6, .4)
        ColumnLayout {
            id: issueBody
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8
            RowLayout { Layout.fillWidth: true; spacing: 10
                StatusPill { text: card.modelData.severity; tone: root.severityTone(card.modelData.severity) }
                GlowText { text: card.modelData.title; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                StationButton { text: card.expanded ? "Less" : "Details"; implicitHeight: 28; onClicked: card.expanded = !card.expanded } }
            GlowText { text: card.modelData.what; font.pixelSize: Theme.small; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GridLayout { visible: card.expanded; columns: 2; columnSpacing: 16; rowSpacing: 6; Layout.fillWidth: true
                GlowText { text: "WHY IT MATTERS"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                GlowText { text: card.modelData.why; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { text: "VERIFIED FROM"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                GlowText { text: card.modelData.verify; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
            RowLayout { Layout.fillWidth: true; spacing: 8
                StationButton { visible: !!card.modelData.action; text: root.confirmRestart === card.modelData.id ? "Confirm" : (card.modelData.action ? card.modelData.action.label : ""); accent: root.confirmRestart === card.modelData.id ? Theme.amber : Theme.teal; enabled: !Station.busy && (!card.modelData.privileged || Capabilities.canElevate); onClicked: { if (root.confirmRestart === card.modelData.id) { root.confirmRestart = ""; Station.act(card.modelData); } else root.confirmRestart = card.modelData.id; } }
                GlowText { visible: !!card.modelData.action; text: card.modelData.privileged ? (Capabilities.canElevate ? "Asks for permission through pkexec" : "Needs pkexec and an authentication agent") : "Runs as you; no privileges needed"; font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                GlowText { visible: !card.modelData.action; text: "No automatic action; CEDAR reports it."; font.pixelSize: 10; color: Theme.muted }
                StationButton { visible: root.confirmRestart === card.modelData.id; text: "Cancel"; implicitHeight: 28; onClicked: root.confirmRestart = "" } }
        }
    }
    component NavButton: StationButton {
        id: nav
        required property var modelData
        readonly property bool current: root.page === modelData[0]
        readonly property string badge: modelData[0] === "issues" && Station.ready && Station.issues.length ? String(Station.issues.length) : ""
        checked: current; accent: Theme.green
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
            Text { visible: root.sidebar && nav.badge !== ""; text: nav.badge; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1; color: root.statusTone }
        }
    }

    RowLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            visible: root.sidebar
            Layout.fillHeight: true; Layout.preferredWidth: 212
            color: Qt.alpha(Theme.surface, .7)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .12) }
            ColumnLayout {
                anchors { fill: parent; margins: 16 } spacing: 6
                RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 14; spacing: 10
                    ProgressArc { implicitWidth: 34; implicitHeight: 34; thickness: 2; ticks: false; value: Station.ready ? Station.healthyServices / Math.max(1, Station.services.length) : 0; accent: root.statusTone }
                    ColumnLayout { spacing: 0
                        GlowText { text: "STATION"; font.pixelSize: 12; font.letterSpacing: 2.6; color: Theme.teal }
                        GlowText { text: "CEDAR"; font.pixelSize: 9; font.letterSpacing: 1.8; color: Theme.muted } } }
                Repeater { model: root.pages; NavButton {} }
                Item { Layout.fillHeight: true }
                ColumnLayout { Layout.fillWidth: true; Layout.bottomMargin: 10; spacing: 8
                    StatusPill { text: Station.headline; tone: root.statusTone }
                    GlowText { visible: Station.readAt > 0; text: "READ " + root.when(Station.readAt).toUpperCase(); font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
                    GlowText { text: SettingsInfo.data.hostname || ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                GlowText { text: Branding.content.identity || ""; font.pixelSize: 9; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.topMargin: 8 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            RowLayout { visible: !root.sidebar; Layout.fillWidth: true; Layout.margins: 12; spacing: 6
                Repeater { model: root.pages; NavButton {} }
                Item { Layout.fillWidth: true }
                StatusPill { text: Station.headline; tone: root.statusTone } }
            Flickable {
                id: scroll
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: body.implicitHeight + 56
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Loader { id: body; x: 28; y: 28; width: scroll.width - 56; sourceComponent: ({ overview: overview, services: servicesPage, issues: issuesPage, log: logPage, report: reportPage })[root.page] || overview }
            }
        }
    }

    // --------------------------------------------------------------- overview
    Component {
        id: overview
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Health"; subtitle: Station.ready ? (Station.issues.length ? Station.subline + "." : "Nothing needs attention. Every reading below is live.") : "Reading services, units, the shell log and the sensors…"
                StationButton { text: Station.busy ? "Checking…" : "Check again"; hint: "Read everything again (Ctrl+R)"; enabled: !Station.busy; onClicked: Station.refresh() }
            }
            GridLayout {
                Layout.fillWidth: true; columns: root.width >= 820 ? 2 : 1; columnSpacing: 20; rowSpacing: 20
                Frame {
                    order: 1
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    topLineColor: root.statusTone; stroke: Qt.alpha(root.statusTone, .22)
                    padding: 24
                    RowLayout { Layout.fillWidth: true; spacing: 20
                        ProgressArc { implicitWidth: 120; implicitHeight: 120; thickness: 3; value: (Station.ready ? Station.healthyServices / Math.max(1, Station.services.length) : 0) * root.ease(.1, .6); accent: root.statusTone
                            ColumnLayout { anchors.centerIn: parent; spacing: 0
                                GlowText { Layout.alignment: Qt.AlignHCenter; text: Station.ready ? Station.healthyServices + "/" + Station.services.length : "—"; font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                                GlowText { Layout.alignment: Qt.AlignHCenter; text: "SERVICES"; font.pixelSize: 8; font.letterSpacing: 1.2; color: Theme.muted } } }
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            GlowText { text: Station.headline.toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 2 + 6 * (1 - root.ease(.3, .5)); color: root.statusTone; opacity: root.ease(.3, .4) }
                            GlowText { text: Station.subline; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            RowLayout { spacing: 16; Layout.topMargin: 6
                                Metric { label: "To fix"; value: Station.ready ? String(Station.criticalCount) : "—"; valueTone: Station.criticalCount ? Theme.danger : Theme.text; order: 4 }
                                Metric { label: "Warnings"; value: Station.ready ? String(Station.warningCount) : "—"; valueTone: Station.warningCount ? Theme.warning : Theme.text; order: 5 }
                                Metric { label: "Notices"; value: Station.ready ? String(Station.noticeCount) : "—"; order: 6 } } }
                    }
                    StationButton { visible: Station.issues.length > 0; text: "All issues →"; implicitHeight: 28; Layout.alignment: Qt.AlignRight; onClicked: root.navigate("issues") }
                }
                Frame {
                    order: 2
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    RowLayout { Layout.fillWidth: true
                        SectionMark { text: "LIVE READINGS" }
                        Item { Layout.fillWidth: true }
                        Rectangle { width: 6; height: 6; radius: 3; color: SystemStats.available ? Theme.green : Theme.muted }
                        GlowText { text: SystemStats.available ? "EVERY " + Math.round(SystemStats.fastCadence / 1000) + " S" : "WAITING"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                    GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 20; rowSpacing: 12
                        Metric { label: "Processor"; value: SystemStats.cpu >= 0 ? Math.round(SystemStats.cpu) + "%" : "—"; trace: SystemStats.cpu >= 0 ? SystemStats.cpu / 100 : -1; order: 3 }
                        Metric { label: "Memory"; value: SystemStats.ram >= 0 ? Math.round(SystemStats.ram * 100) + "%" : "—"; detail: SystemStats.memoryLabel; trace: SystemStats.ram >= 0 ? SystemStats.ram : -1; order: 4 }
                        Metric { label: "Disk"; value: SystemStats.disk >= 0 ? Math.round(SystemStats.disk * 100) + "% used" : "—"; detail: Config.saved.diskPath || "/"; valueTone: SystemStats.disk >= Config.saved.coreDiskLimit / 100 ? Theme.warning : Theme.text; order: 5 }
                        Metric { label: "Temperature"; value: SystemStats.temperature >= 0 ? Math.round(SystemStats.temperature) + " °C" : "—"; detail: "system sensor"; valueTone: SystemStats.temperature >= Config.saved.coreTemperatureLimit ? Theme.warning : Theme.text; order: 6 }
                        Metric { label: "GPU"; value: Station.data.gpu.available ? Station.data.gpu.utilization + "%" + (Station.data.gpu.temperature !== null && Station.data.gpu.temperature !== undefined ? " · " + Math.round(Station.data.gpu.temperature) + " °C" : "") : "No supported path"; detail: Station.data.gpu.available ? "via " + Station.data.gpu.source + ", read on open and Check again" : (Station.data.gpu.reason || ""); order: 7 }
                        Metric { label: "Uptime"; value: SystemStats.uptime; detail: "network " + (SystemStats.networkRate > 0 ? (SystemStats.networkRate / 1024).toFixed(0) + " KB/s" : "quiet"); order: 8 } }
                }
            }
            Frame {
                order: 3
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "SERVICES" }
                    Item { Layout.fillWidth: true }
                    StationButton { text: "All →"; implicitHeight: 28; onClicked: root.navigate("services") } }
                Repeater {
                    model: Station.services
                    RowLayout { required property var modelData; required property int index; Layout.fillWidth: true; spacing: 10; opacity: root.beat(5 + index * .4, .35)
                        Rectangle { width: 8; height: 8; radius: 4; color: root.serviceTone(modelData.status) }
                        GlowText { text: modelData.name; color: Theme.text; Layout.preferredWidth: 160; elide: Text.ElideRight }
                        GlowText { text: modelData.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                        StatusPill { text: modelData.status; tone: root.serviceTone(modelData.status) } }
                }
                GlowText { visible: !Station.services.length; text: SettingsInfo.busy ? "Reading…" : "Service health is unavailable."; color: Theme.muted; font.pixelSize: Theme.small }
            }
            Frame {
                order: 4
                Layout.fillWidth: true
                SectionMark { text: "SHELL COST" }
                GridLayout { Layout.fillWidth: true; columns: root.width >= 820 ? 3 : 1; columnSpacing: 20; rowSpacing: 12
                    Metric { label: "Resident memory"; value: Station.data.shellMemoryMb >= 0 ? Math.round(Station.data.shellMemoryMb) + " MB" : "—"; detail: "this process; helpers and the GPU driver's share not included"; order: 6 }
                    Metric { label: "Ambience"; value: VisualQuality.gaming ? "Gaming Mode" : VisualQuality.efficient ? "Performance mode" : Motion.active ? "Breathing" : "Resting"; detail: !VisualQuality.normal ? VisualQuality.reason : Theme.reducedMotion ? "Reduced Motion is on" : "pauses after " + Motion.restAfter + " s without input"; order: 7 }
                    Metric { label: "Sampling"; value: SystemStats.instrument ? "Instrument" : SystemStats.demanded ? "Ambient" : "Idle"; detail: "CPU and memory every " + Math.round(SystemStats.fastCadence / 1000) + " s while this window is open"; order: 8 } }
            }
            GlowText { visible: Station.error !== ""; text: Station.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    // --------------------------------------------------------------- services
    Component {
        id: servicesPage
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Services"; subtitle: "The system services CEDAR depends on, and every unit systemd reports failed. Restarting briefly interrupts what a service does."
                StationButton { text: Station.busy || SettingsInfo.busy ? "Checking…" : "Check again"; enabled: !Station.busy && !SettingsInfo.busy; onClicked: Station.refresh() }
            }
            Frame {
                order: 1
                Layout.fillWidth: true
                SectionMark { text: "CEDAR DEPENDS ON" }
                Repeater {
                    model: Station.services
                    ColumnLayout {
                        id: svc
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 4
                        opacity: root.beat(2 + index * .5, .35)
                        RowLayout { Layout.fillWidth: true; spacing: 10
                            Rectangle { width: 8; height: 8; radius: 4; color: root.serviceTone(svc.modelData.status) }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                GlowText { text: svc.modelData.name; color: Theme.text }
                                GlowText { text: svc.modelData.unit + " · " + (svc.modelData.user ? "user" : "system") + " · " + svc.modelData.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                            StatusPill { text: svc.modelData.status; tone: root.serviceTone(svc.modelData.status) }
                            StationButton { text: "Logs"; implicitHeight: 28; enabled: !Station.busy && svc.modelData.status !== "Unavailable"; onClicked: { Station.showLogs(svc.modelData.unit, svc.modelData.user); root.navigate("log"); } }
                            StationButton { text: root.confirmRestart === svc.modelData.unit ? "Confirm" : "Restart"; implicitHeight: 28; accent: root.confirmRestart === svc.modelData.unit ? Theme.amber : Theme.teal; enabled: !Station.busy && svc.modelData.status !== "Unavailable" && (svc.modelData.user || Capabilities.canElevate); onClicked: { if (root.confirmRestart === svc.modelData.unit) { root.confirmRestart = ""; Station.restart(svc.modelData.unit, svc.modelData.user); } else root.confirmRestart = svc.modelData.unit; } } }
                        RowLayout { visible: root.confirmRestart === svc.modelData.unit; Layout.fillWidth: true; Layout.leftMargin: 18; spacing: 8
                            GlowText { text: "Restart " + svc.modelData.name + "? It is briefly interrupted" + (svc.modelData.user ? "." : "; pkexec asks for permission."); color: Theme.amber; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            StationButton { text: "Cancel"; implicitHeight: 28; onClicked: root.confirmRestart = "" } }
                    }
                }
                GlowText { visible: !Station.services.length; text: "Service health is unavailable."; color: Theme.muted; font.pixelSize: Theme.small }
            }
            Frame {
                order: 2
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "FAILED UNITS"; tone: Station.data.failedUnits.length ? Theme.warning : Theme.teal }
                    Item { Layout.fillWidth: true }
                    GlowText { text: Station.data.failedUnits.length + " FAILED"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                Repeater {
                    model: Station.data.failedUnits
                    RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 10
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.danger }
                        ColumnLayout { Layout.fillWidth: true; spacing: 1
                            GlowText { text: modelData.unit; color: Theme.text }
                            GlowText { text: (modelData.user ? "user · " : "system · ") + modelData.sub + (modelData.description ? " · " + modelData.description : ""); font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                        StationButton { text: "Logs"; implicitHeight: 28; enabled: !Station.busy; onClicked: { Station.showLogs(modelData.unit, modelData.user); root.navigate("log"); } }
                        StationButton { text: "Reset"; implicitHeight: 28; hint: "systemctl reset-failed"; enabled: !Station.busy && (modelData.user || Capabilities.canElevate); onClicked: Station.resetFailed(modelData.unit, modelData.user) }
                        StationButton { text: "Restart"; implicitHeight: 28; enabled: !Station.busy && (modelData.user || Capabilities.canElevate); onClicked: Station.restart(modelData.unit, modelData.user) } }
                }
                GlowText { visible: !Station.data.failedUnits.length; text: Station.ready ? "No failed units, user or system." : "Reading…"; color: Theme.muted; font.pixelSize: Theme.small }
            }
            GlowText { visible: Station.message !== ""; text: Station.message; color: Theme.green; font.pixelSize: Theme.small }
            GlowText { visible: Station.error !== ""; text: Station.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    // ----------------------------------------------------------------- issues
    Component {
        id: issuesPage
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Issues"; subtitle: Station.ready ? (Station.issues.length ? "Each one says what happened, why it matters, what CEDAR verified, and what it can do." : "Nothing needs attention.") : "Reading…"
                StationButton { text: Station.updatesChecked ? "Check updates again" : "Check updates"; hint: "checkupdates: repository packages only"; enabled: !CoreService.actionBusy; onClicked: Station.checkUpdates() }
                StationButton { text: Station.busy ? "Checking…" : "Check again"; enabled: !Station.busy; onClicked: Station.refresh() }
            }
            Repeater { model: Station.issues; IssueCard {} }
            Frame { visible: Station.ready && !Station.issues.length; order: 2; Layout.fillWidth: true; topLineColor: Theme.success
                SectionMark { text: "ALL CLEAR"; tone: Theme.success }
                GlowText { text: "Services healthy, no failed units, a clean shell log since the last launch, every configuration file parsed, disk and temperature under their limits" + (Station.updates === 0 ? ", repository packages current." : "."); font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
            GlowText { visible: Station.error !== ""; text: Station.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    // -------------------------------------------------------------------- log
    Component {
        id: logPage
        ColumnLayout {
            spacing: 22
            PageTitle { title: "Log"; subtitle: "Issues the shell logged since its last launch, and a unit's recent journal when you ask for it. Common secrets and identifiers are redacted; review before sharing." }
            Frame {
                order: 1
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "SHELL LOG SINCE LAUNCH"; tone: Station.data.logIssues.length ? Theme.warning : Theme.teal }
                    Item { Layout.fillWidth: true }
                    GlowText { text: (Station.data.logPath || "").replace(Quickshell.env("HOME") || "", "~"); font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted } }
                Repeater {
                    model: Station.data.logIssues
                    RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 10
                        StatusPill { text: modelData.count + "×"; tone: modelData.kind === "load" ? Theme.danger : Theme.warning }
                        GlowText { text: modelData.line; font.pixelSize: Theme.small; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere } }
                }
                GlowText { visible: !Station.data.logIssues.length; text: Station.ready ? "Clean: no load failures or binding errors since the last launch." : "Reading…"; color: Theme.muted; font.pixelSize: Theme.small }
            }
            Frame {
                order: 2
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: Station.logsFor ? "JOURNAL · " + Station.logsFor.toUpperCase() : "JOURNAL" }
                    Item { Layout.fillWidth: true }
                    StationButton { visible: Station.logs !== ""; text: "Copy"; implicitHeight: 28; onClicked: Quickshell.clipboardText = Station.logs } }
                TextArea { visible: Station.logs !== ""; Layout.fillWidth: true; text: Station.logs; textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: Theme.text; font.family: Theme.dataFont; font.pixelSize: Theme.small
                    background: Rectangle { color: Theme.background; radius: 8; border.color: Qt.alpha(Theme.teal, .12) } }
                GlowText { visible: Station.logs === ""; text: "Choose Logs beside a service or a failed unit."; color: Theme.muted; font.pixelSize: Theme.small }
            }
        }
    }

    // ----------------------------------------------------------------- report
    Component {
        id: reportPage
        ColumnLayout {
            spacing: 22
            PageTitle {
                title: "Report"; subtitle: "A plain-text diagnostic report for troubleshooting: status, versions, services, readings, capabilities, failed units, log issues and configuration problems. Redacted by CEDAR; nothing is uploaded, you review it before copying."
                StationButton { text: Station.busy ? "Building…" : Station.report ? "Rebuild report" : "Build report"; accent: Theme.green; checked: true; enabled: !Station.busy; onClicked: Station.buildReport() }
            }
            Frame {
                order: 1
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "REVIEW" }
                    Item { Layout.fillWidth: true }
                    StationButton { visible: Station.report !== ""; text: "Copy diagnostic report"; onClicked: { Quickshell.clipboardText = Station.report; Station.message = "Diagnostic report copied."; } } }
                TextArea { visible: Station.report !== ""; Layout.fillWidth: true; text: Station.report; textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: Theme.text; font.family: Theme.dataFont; font.pixelSize: Theme.small
                    background: Rectangle { color: Theme.background; radius: 8; border.color: Qt.alpha(Theme.teal, .12) } }
                GlowText { visible: Station.report === ""; text: "Nothing built yet."; color: Theme.muted; font.pixelSize: Theme.small }
                GlowText { visible: Station.message !== ""; text: Station.message; color: Theme.green; font.pixelSize: Theme.small }
            }
        }
    }
}
