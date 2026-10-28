import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property string provider: "google"
    property bool importing: false
    property string editingId: ""
    property string chosenColor: Theme.calendarColors[0]
    spacing: 10
    readonly property var providerNames: ({ google: "Google", proton: "Proton", nextcloud: "Nextcloud" })
    // Only a calendar's own address (not a public share link) needs an app password.
    readonly property bool needsLogin: provider === "nextcloud" && !importing && /\/remote\.php\/dav\/calendars\//.test(link.text)
    function clearForm() { link.text = ""; filePath.text = ""; username.text = ""; appPassword.text = ""; editingId = ""; }
    Connections {
        target: CalendarFeeds
        function onCompleted(action) { if (["connect", "replace", "import"].includes(action)) { root.clearForm(); label.text = ""; } }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.clearForm(); } }
    SectionMark { text: "CONNECTED CALENDARS"; tone: Theme.strataAccent }
    Repeater {
        model: CalendarFeeds.sources
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                Rectangle { width: 7; height: 7; radius: 3; color: parent.parent.modelData.color }
                GlowText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: parent.parent.modelData.name; color: Theme.strataText }
                GlowText { text: root.providerNames[parent.parent.modelData.provider] || "Calendar"; font.pixelSize: Theme.small; color: Theme.strataMuted }
            }
            GlowText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
                color: modelData.error ? Theme.amber : Theme.strataMuted
                text: !modelData.enabled ? "Hidden · refresh paused" : modelData.error || (modelData.kind === "import" ? "Imported snapshot · does not sync" : modelData.status === "offline" ? "Offline · showing saved events" : modelData.status === "stale" ? "Waiting for a refresh" : "Connected · read-only")
            }
            GlowText {
                visible: modelData.updatedAt > 0
                text: "Last updated " + Qt.formatDateTime(new Date(modelData.updatedAt), "MMM d, h:mm AP")
                color: Theme.strataMuted; font.pixelSize: Theme.small - 1
            }
            Flow {
                Layout.fillWidth: true; spacing: 6
                StrataButton { text: modelData.enabled ? "Hide" : "Show"; enabled: !CalendarFeeds.busy; onClicked: CalendarFeeds.request({ action: "toggle", id: modelData.id, enabled: !modelData.enabled }) }
                StrataButton { text: "Open calendar"; onClicked: if (!Config.testMode) Qt.openUrlExternally(modelData.webUrl) }
                StrataButton { text: "Replace link"; enabled: !CalendarFeeds.busy; onClicked: { root.editingId = modelData.id; root.provider = modelData.provider; root.importing = false; link.text = ""; link.forceActiveFocus(); } }
                StrataButton { text: "Disconnect"; enabled: !CalendarFeeds.busy; onClicked: CalendarFeeds.request({ action: "disconnect", id: modelData.id }) }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.strataGrain, .35) }
        }
    }
    SectionMark { text: root.editingId ? "REPLACE CALENDAR LINK" : "ADD A CALENDAR"; tone: Theme.strataAccent }
    // Three providers do not fit a narrow drop on one row; let them wrap.
    Flow {
        Layout.fillWidth: true; spacing: 6
        StrataButton { text: "Google Calendar"; checked: root.provider === "google"; enabled: !root.editingId; onClicked: { root.provider = "google"; link.text = ""; } }
        StrataButton { text: "Proton Calendar"; checked: root.provider === "proton"; enabled: !root.editingId; onClicked: { root.provider = "proton"; link.text = ""; } }
        StrataButton { text: "Nextcloud"; checked: root.provider === "nextcloud"; enabled: !root.editingId; onClicked: { root.provider = "nextcloud"; link.text = ""; } }
    }
    RowLayout {
        visible: !root.editingId
        StrataButton { text: "Connect by link"; checked: !root.importing; onClicked: root.importing = false }
        StrataButton { text: "Import .ics file"; checked: root.importing; onClicked: { root.importing = true; link.text = ""; } }
    }
    GlowText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.strataMuted
        text: root.importing ? "Import an exported calendar, including from Proton Free. This is a snapshot; import again to get later changes."
            : root.provider === "google" ? "Google Calendar → Settings → your calendar → Integrate calendar → Secret address in iCal format. Copy that address here."
            : root.provider === "nextcloud" ? "Nextcloud Calendar → your calendar's ⋯ menu → Share link, then Copy subscription link. Or, to keep it private, use Copy private link with your username and an app password from Settings → Security."
            : "Proton Calendar → Settings → Calendars → your calendar → Share with anyone → Create link. Choose Full view for titles, or Limited view for busy times. Creating a link requires a paid Proton plan."
    }
    StrataButton {
        text: "Open setup guide"
        onClicked: if (!Config.testMode) Qt.openUrlExternally(root.provider === "google" ? "https://support.google.com/calendar/answer/37648"
            : root.provider === "nextcloud" ? "https://docs.nextcloud.com/server/latest/user_manual/en/groupware/calendar.html"
            : "https://proton.me/support/share-calendar-via-link")
    }
    StrataField { id: label; visible: !root.editingId; Layout.fillWidth: true; placeholderText: "Calendar name, e.g. Personal or Work"; maximumLength: 80; Accessible.name: "Calendar name" }
    StrataField {
        id: link; visible: !root.importing; Layout.fillWidth: true; placeholderText: "Paste private calendar link"
        echoMode: TextInput.Password; maximumLength: 4096; Accessible.name: "Private calendar subscription link"
        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
    }
    StrataField { id: username; visible: root.needsLogin; Layout.fillWidth: true; placeholderText: "Nextcloud username"; maximumLength: 256; Accessible.name: "Nextcloud username" }
    StrataField {
        id: appPassword; visible: root.needsLogin; Layout.fillWidth: true; placeholderText: "Nextcloud app password"
        echoMode: TextInput.Password; maximumLength: 256; Accessible.name: "Nextcloud app password"
        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
    }
    StrataField { id: filePath; visible: root.importing; Layout.fillWidth: true; placeholderText: "Path to exported .ics file"; Accessible.name: "Calendar import file path" }
    RowLayout {
        visible: !root.editingId
        GlowText { text: "Color"; color: Theme.strataMuted; font.pixelSize: Theme.small }
        Repeater {
            model: Theme.calendarColors
            StrataButton { required property string modelData; text: root.chosenColor === modelData ? "●" : "○"; accent: modelData; checked: root.chosenColor === modelData; Accessible.name: "Calendar color " + modelData; onClicked: root.chosenColor = modelData }
        }
    }
    GlowText {
        visible: !root.importing
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.strataMuted
        text: root.needsLogin ? "Use an app password, not your login password, so you can revoke it in Nextcloud at any time. CEDAR saves it in a private file on this device. Events are read-only here."
            : "Anyone with this link can read the shared calendar. CEDAR saves it in a private file on this device. No calendar password is needed. Events are read-only here."
    }
    RowLayout {
        StrataButton {
            text: root.editingId ? "Save new link" : root.importing ? "Import calendar" : "Connect calendar"
            enabled: !CalendarFeeds.busy && (root.importing ? filePath.text.trim() !== "" : link.text.trim() !== "" && (!root.needsLogin || username.text.trim() !== "" && appPassword.text !== ""))
            onClicked: CalendarFeeds.request({ action: root.editingId ? "replace" : root.importing ? "import" : "connect", id: root.editingId,
                provider: root.provider, name: label.text, url: link.text, path: filePath.text, color: root.chosenColor,
                username: root.needsLogin ? username.text : "", password: root.needsLogin ? appPassword.text : "" })
        }
        StrataButton { visible: !!root.editingId; text: "Cancel"; onClicked: root.clearForm() }
    }
}
