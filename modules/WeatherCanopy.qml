import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    function timeLabel(value){return Config.formatTime(new Date("2000-01-01T"+value));}
    spacing:12
    GlowText {text:WeatherLocation.label || "Sky Watch";font.pixelSize:24;color:Theme.green}
    GlowText {text:Weather.temperature;font.pixelSize:42}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:Weather.condition;color:Theme.teal}
    GlowText {text:Weather.wind;color:Theme.muted}
    GlowText {text:(Weather.stale?"STALE · ":"")+"Open-Meteo · "+Weather.updated;color:Weather.stale?Theme.amber:Theme.muted}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:Weather.sunrise?"Sunrise · "+root.timeLabel(Weather.sunrise):"Sunrise unavailable";color:Theme.muted}
    SettingsHeading {text:"Next hours"}
    Repeater {model:Weather.hours;SettingRow {required property var modelData;Layout.fillWidth:true;title:root.timeLabel(modelData.time);description:modelData.temperature+" · Rain "+modelData.rain+"%"}}
    StationButton {visible:Weather.configured;text:"Refresh";onClicked:Weather.refresh()}
    GlowText {visible:!Weather.configured;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"No forecast location. Choose one in Settings · Desktop · Weather.";color:Theme.muted}
}
