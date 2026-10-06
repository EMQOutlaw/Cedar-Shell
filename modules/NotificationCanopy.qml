import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    spacing: 12
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }
    readonly property int count: NoticeStore.history.length
    // State pills and the two controls arrive first.
    Flow {
        Layout.fillWidth: true; spacing: 8
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        StatusPill { text: root.count === 0 ? "Quiet" : root.count + (root.count === 1 ? " notice" : " notices"); tone: root.count ? Theme.teal : Theme.muted }
        StatusPill { visible: Config.saved.doNotDisturb; text: "Do not disturb"; tone: Theme.amber }
        StationButton { text: "Clear history"; enabled: root.count > 0; onClicked: NoticeStore.clear() }
        StationButton { text: Config.saved.doNotDisturb ? "DND on" : "DND off"; checked: Config.saved.doNotDisturb; onClicked: Config.set("doNotDisturb", !Config.saved.doNotDisturb) }
    }
    GlowText { visible: root.count === 0; text: "No notifications in this session."; color: Theme.muted; opacity: root.beat(1) }
    SectionMark { visible: root.count > 0; text: "THIS SESSION"; opacity: root.beat(1) }
    Repeater {
        model: NoticeStore.history.slice(0, 60)
        // Each notice settles a beat after the last, with a rule that grows down
        // its side: teal for ordinary notices, ember for critical ones.
        RowLayout {
            id: entry
            required property var modelData
            required property int index
            readonly property var liveNotice: NoticeStore.live.find(n => n.id === modelData.id) || null
            readonly property real sweep: root.beat(2 + Math.min(index, 9), .4)
            readonly property color tone: modelData.critical ? Theme.ember : Theme.teal
            Layout.fillWidth: true
            spacing: 12
            opacity: sweep
            transform: Translate { y: 8 * (1 - entry.sweep) }
            Item {
                Layout.fillHeight: true
                implicitWidth: 3
                Rectangle { width: 2; height: parent.height * entry.sweep; color: entry.tone; opacity: entry.liveNotice ? .85 : .4 }
                Rectangle { x: -3; width: 8; height: parent.height * entry.sweep; color: entry.tone; opacity: entry.liveNotice ? .08 : .03 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    GlowText { Layout.fillWidth: true; text: entry.modelData.app; color: entry.tone; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.2; elide: Text.ElideRight }
                    GlowText { text: entry.modelData.timestamp ? Config.formatTime(new Date(entry.modelData.timestamp)) : entry.modelData.time; color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: 10 }
                }
                GlowText { Layout.fillWidth: true; text: entry.modelData.summary; wrapMode: Text.WordWrap; color: entry.modelData.critical ? Theme.ember : Theme.text }
                GlowText { Layout.fillWidth: true; visible: text !== ""; text: entry.modelData.body; wrapMode: Text.WordWrap; maximumLineCount: 6; elide: Text.ElideRight; color: Theme.muted }
                Flow {
                    Layout.fillWidth: true; spacing: 6
                    Repeater { model: entry.liveNotice?.actions || []; StationButton { required property var modelData; text: modelData.text; onClicked: modelData.invoke() } }
                    StationButton { text: entry.liveNotice ? "Dismiss" : "Remove"; onClicked: { NoticeStore.dismiss(entry.modelData.id); NoticeStore.history = NoticeStore.history.filter(n => n.id !== entry.modelData.id); } }
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; implicitHeight: 1; color: Theme.border; opacity: .6 }
            }
        }
    }
}
