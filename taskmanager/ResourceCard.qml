import QtQuick
import QtQuick.Layouts
import Cedar.TaskManager
Rectangle {
    id: card
    property string title: ""
    property string value: "Unavailable"
    property string detail: ""
    property var samples: []
    property real ceiling: 100
    property color accent: Task.style.teal
    implicitHeight: 200
    color: Task.style.surface
    radius: Task.style.radius
    border.color: Task.style.border
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 8
        Text { textFormat: Text.PlainText; text: card.title.toUpperCase(); color: Task.style.muted; font.family: Task.style.mono; font.pixelSize: 12; font.letterSpacing: 1 }
        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: card.value; color: Task.style.text; font.family: Task.style.font; font.pixelSize: 28 * (Task.style.fontScale || 1); elide: Text.ElideRight }
        HistoryGraph { Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 35; samples: card.samples; color: card.accent; maximum: card.ceiling }
        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: card.detail; color: Task.style.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
    }
}
