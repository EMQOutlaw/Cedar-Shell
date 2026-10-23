import QtQuick
import QtQuick.Layouts
import Cedar.TaskManager
Material {
    id: card
    property string title: ""
    property string value: "—"
    property string detail: ""
    property string context: ""
    property var samples: []
    property real ceiling: 100
    property bool warning: false
    implicitHeight: 150 * Math.max(1, TM.scale*.85)
    alert: warning
    grain: true
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 15; spacing: 5
        RowLayout {
            Layout.fillWidth: true
            TMText { text: card.title.toUpperCase(); technical: true; color: card.accent; font.letterSpacing: 1.1 }
            Item { Layout.fillWidth: true }
            TMText { Layout.maximumWidth: card.width*.6; text: card.context; technical: true; secondary: true }
        }
        TMText { Layout.fillWidth: true; text: card.value; technical: true; font.pixelSize: (card.value.length>16 ? 22 : 28) * TM.scale; font.letterSpacing: -1 }
        HistoryGraph { Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 22; samples: card.visible ? card.samples : []; color: card.accent; maximum: card.ceiling }
        TMText { Layout.fillWidth: true; text: card.detail; secondary: true; font.pixelSize: 12 * TM.scale; maximumLineCount: 2; wrapMode: Text.WordWrap }
    }
}
