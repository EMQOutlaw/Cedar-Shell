import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings › Nursery: companion services planted into the shell. Each one
// describes itself with a descriptor in ~/.config/cedar/plugins.d/; this page
// shows what is running and offers the same first-time question the plugin's
// own setup asks — plant it at login, or leave it off. Off is the default.
ColumnLayout {
    id: root
    property bool active: false
    spacing: 16

    readonly property var plugins: Nursery.plugins
    readonly property int runningCount: plugins.filter(p => p.active).length
    readonly property int pendingCount: plugins.filter(p => p.setup_state === "pending").length

    function statusWord(p) {
        if (p.error) return "Unreadable";
        if (!p.installed) return "Not installed";
        if (p.active) return "Running";
        return "Stopped";
    }
    function statusLit(p) { return p.active === true; }

    GridLayout {
        Layout.fillWidth: true; columns: root.width < 600 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
        Readout {
            label: "Planted"; lit: root.plugins.length > 0; tone: Theme.teal
            value: root.plugins.length === 1 ? "1 companion" : root.plugins.length + " companions"
            detail: "Descriptors live in ~/.config/cedar/plugins.d/."
        }
        Readout {
            label: "Running"; lit: root.runningCount > 0
            value: String(root.runningCount)
            detail: root.runningCount ? "User services, active now." : "Nothing is running."
        }
        Readout {
            label: "Awaiting setup"; lit: root.pendingCount > 0; tone: root.pendingCount ? Theme.amber : Theme.green
            value: String(root.pendingCount)
            detail: root.pendingCount ? "A companion has never been asked; its question is below." : "Every companion has its answer."
        }
    }

    GlowText {
        visible: Nursery.error !== "" || Nursery.message !== ""
        text: Nursery.error || Nursery.message
        color: Nursery.error ? Theme.amber : Theme.teal
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
    }

    Repeater {
        model: root.plugins
        SettingsSurface {
            required property var modelData
            readonly property var plugin: modelData
            Layout.fillWidth: true; padding: 16
            accent: plugin.setup_state === "pending" ? Theme.amber : (plugin.active ? Theme.green : Theme.strataAccent)

            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Rectangle {
                        width: 7; height: 7; radius: 4
                        color: plugin.active ? Theme.green : (plugin.installed ? Theme.strataMuted : Theme.amber)
                        Layout.alignment: Qt.AlignVCenter
                    }
                    GlowText {
                        text: plugin.name || plugin.id
                        font.family: Theme.labelFont; font.pixelSize: Math.round(17 * Theme.fontScale); font.weight: Font.DemiBold
                        color: Theme.strataText
                    }
                    GlowText {
                        Layout.fillWidth: true
                        text: root.statusWord(plugin) + (plugin.unit ? " · " + plugin.unit : "")
                        color: plugin.active ? Theme.green : Theme.muted; font.pixelSize: Theme.small
                        elide: Text.ElideRight
                    }
                }
                GlowText {
                    visible: (plugin.tagline || "") !== ""
                    text: plugin.tagline || ""
                    color: Theme.muted; font.pixelSize: Theme.small
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
                GlowText {
                    visible: plugin.error !== undefined && plugin.error !== ""
                    text: plugin.error || ""
                    color: Theme.amber; font.pixelSize: Theme.small
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }

                // The first-time question, in the plugin's own words' stead:
                // plant it at login, or leave it off. Off is the default.
                SettingsSurface {
                    visible: plugin.setup_state === "pending"
                    Layout.fillWidth: true; padding: 12; accent: Theme.amber
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        GlowText {
                            text: "First time: plant " + (plugin.name || plugin.id) + " at login?"
                            color: Theme.amber; font.pixelSize: Theme.small; font.weight: Font.DemiBold
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                        GlowText {
                            text: "It stays off until you say otherwise — enabling starts it now and at every login; leaving off records the choice and asks never again."
                            color: Theme.muted; font.pixelSize: Theme.small
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 8
                            StationButton { text: "Enable at login"; accent: Theme.green; onClicked: Nursery.act("enable", plugin.id) }
                            StationButton { text: "Leave off"; onClicked: Nursery.act("disable", plugin.id) }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true; spacing: 8
                    visible: plugin.setup_state !== "pending" && plugin.error === undefined
                    StationButton {
                        visible: plugin.installed || (plugin.setup || "") !== ""
                        text: plugin.active ? "Stop and disable" : "Enable and start"
                        accent: plugin.active ? Theme.strataAccent : Theme.green
                        onClicked: Nursery.act(plugin.active ? "disable" : "enable", plugin.id)
                    }
                    StationButton {
                        visible: (plugin.dashboard || "") !== ""
                        text: "Open dashboard"
                        hint: plugin.dashboard_ok ? "reachable" : "not answering right now"
                        onClicked: Nursery.act("open", plugin.id)
                    }
                }
            }
        }
    }

    SettingsSection {
        visible: root.plugins.length === 0 && !Nursery.busy && Nursery.error === ""
        heading: "An empty Nursery"
        caption: "Nothing is planted yet. Companion services describe themselves with a small JSON descriptor in " + (Nursery.pluginsDir || "~/.config/cedar/plugins.d") + " — CEDAR Ai (`cedar-ai setup`) is the first."
    }

    GlowText {
        visible: Nursery.busy
        text: "Reading the Nursery…"
        color: Theme.muted; font.pixelSize: Theme.small
    }
}
