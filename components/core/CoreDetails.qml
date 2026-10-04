import QtQuick
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"

ColumnLayout {
    id: root
    property var activity: null
    spacing: 10
    GlowText {
        text: root.activity?.title || "The station is quiet"
        font.family: Theme.labelFont
        font.pixelSize: 23
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    GlowText {
        text: root.activity?.subtitle || "All activities will gather here."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
    GlowText {
        visible: root.activity?.type === "timer"
        text: CoreService.timer.completed ? "00:00" : Media.elapsed(CoreService.timer.remaining)
        color: Theme.green
        font.pixelSize: 34
        font.family: Theme.labelFont
    }
    GlowText {
        visible: root.activity?.type === "recording" && !!root.activity?.data.started
        text: Media.elapsed((CoreService.now - (root.activity?.data.started || CoreService.now)) / 1000)
        color: Theme.ember
        font.pixelSize: 30
        font.family: Theme.labelFont
    }
    Rectangle {
        visible: (root.activity?.progress ?? -1) >= 0
        Layout.fillWidth: true
        implicitHeight: 3
        radius: 1
        color: Theme.border
        Rectangle {
            width: parent.width * Math.max(0, root.activity?.progress ?? 0)
            height: parent.height
            color: Theme.teal
        }
    }
    GlowText {
        visible: !!root.activity?.source && root.activity.source !== "cedar"
        text: "From " + (root.activity?.source || "")
        color: Theme.muted
        font.pixelSize: Theme.small
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.activity?.actions || []
            StationButton {
                required property var modelData
                text: CoreService.confirmTrash === root.activity?.id && modelData.id === "trash-file" ? "Confirm Trash" : modelData.label
                enabled: !CoreService.actionBusy
                onClicked: CoreService.invoke(root.activity, modelData.id)
            }
        }
        StationButton {
            visible: CoreService.confirmTrash === root.activity?.id
            text: "Cancel"
            onClicked: CoreService.confirmTrash = ""
        }
    }
    GlowText {
        visible: root.activity?.type === "notification"
        text: NoticeStore.live.find(n => n.id === root.activity?.data.noticeId)?.body || ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.pixelSize: Theme.small
    }
}
