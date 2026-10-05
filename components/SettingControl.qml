import QtQuick
import QtQuick.Layouts
import ".."
SettingRow {
    id: root
    required property var spec
    property string highlightKey: ""
    objectName: spec.key
    title: spec.label; description: spec.description
    highlighted: highlightKey===spec.key
    enabled: spec.key !== "idleLockSeconds" || (!Config.externalSession && !Config.externalIdle)
    function commit(value) { Config.set(spec.key,value); }
    StationToggle { visible: root.spec.type==="toggle"; Layout.fillWidth: true; checked: Config.saved[root.spec.key]===true; label:""; accessibleLabel:root.title; onToggled: value=>root.commit(value) }
    RowLayout {
        visible: root.spec.type==="slider"; Layout.fillWidth: true
        StationSlider { Accessible.name:root.title; Layout.fillWidth: true; from:root.spec.min ?? 0; to:root.spec.max ?? 1; stepSize:root.spec.step ?? .01; value:Number(Config.saved[root.spec.key]) || 0; onMoved: root.commit(Math.round(value*100)/100) }
        GlowText { text: Math.round(Number(Config.saved[root.spec.key])*(root.spec.factor || 1))+(root.spec.unit || ""); Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; color: Theme.teal }
    }
    StationField {
        visible: ["text","number"].includes(root.spec.type); Layout.fillWidth: true
        text: String(Config.saved[root.spec.key] ?? ""); placeholderText:root.spec.placeholder || ""
        onCommit: value => {
            if (root.spec.type==="number") { const n=Number(value); if (!isFinite(n) || n<root.spec.min || n>root.spec.max) { text=String(Config.saved[root.spec.key]);return; } root.commit(Math.round(n)); }
            else root.commit(value);
        }
    }
    StationCombo {
        visible: root.spec.type==="choice"; Layout.fillWidth: true
        model: root.spec.options || []; textRole:"label"
        currentIndex: model.findIndex(v=>v.value===Config.saved[root.spec.key])
        onActivated: root.commit(model[currentIndex].value)
    }
    StationCombo {
        visible: root.spec.type==="font"; Layout.fillWidth:true
        model: visible ? [...new Set([Config.saved[root.spec.key]].concat(Qt.fontFamilies()))] : []
        currentIndex: model.indexOf(Config.saved[root.spec.key])
        onActivated: root.commit(currentText)
    }
}
