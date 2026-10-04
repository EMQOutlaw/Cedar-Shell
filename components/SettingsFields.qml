import QtQuick
import QtQuick.Layouts
import ".."
import "SettingsSchema.js" as Schema
ColumnLayout {
    id: root
    required property string page
    property string highlightKey: ""
    readonly property var fields: Schema.fields.filter(f=>f.page===page)
    property bool advanced:highlightKey!=="" && fields.some(f=>f.key===highlightKey && f.group==="Advanced")
    spacing: 4
    Repeater {
        model: root.fields
        ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true; spacing: 4
            StationButton { visible:modelData.group==="Advanced"; text:root.advanced ? "▾ Advanced":"▸ Advanced"; onClicked:root.advanced=!root.advanced }
            GlowText { visible:modelData.group!=="Advanced" && (index===0 || modelData.group!==root.fields[index-1].group); text:modelData.group; color:Theme.teal; font.family:Theme.labelFont; font.pixelSize:20; Layout.topMargin:index===0 ? 8:24; Layout.leftMargin:12 }
            SettingControl { visible:modelData.group!=="Advanced" || root.advanced; Layout.fillWidth:true; spec:modelData; highlightKey:root.highlightKey }
        }
    }
}
