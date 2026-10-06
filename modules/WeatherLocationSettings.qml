import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
import "../components/SettingsSchema.js" as Schema
// Where Field Station's forecast comes from. Permissions live in Privacy.
SettingsSection {
    id: root
    objectName: "weatherLocation"
    property string highlightKey: ""
    property bool exact: highlightKey !== "" && ["locationName","latitude","longitude"].includes(highlightKey)
    function spec(key) { return Schema.fields.find(f => f.key === key); }
    readonly property bool allowed: !Config.localOnly && Config.saved.weatherEnabled
    heading: "Weather"
    badge: !allowed ? "Off" : WeatherLocation.automatic ? "Automatic" : Weather.configured ? "Saved place" : "No location"
    badgeColor: allowed && Weather.configured ? Theme.green : Theme.muted
    caption: allowed ? "Forecasts come from Open-Meteo for the place below." : "Weather is off. Turn off Local-only mode and allow Weather access in Privacy to use it."
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:WeatherLocation.status; color:WeatherLocation.error ? Theme.amber : Theme.text; font.pixelSize:Theme.small }
    SettingControl { Layout.fillWidth:true; enabled:root.allowed; spec:root.spec("weatherAutomatic"); highlightKey:root.highlightKey }
    StationButton { visible:Config.saved.weatherAutomatic; text:WeatherLocation.manual ? "Use automatic location instead of the saved city" : "Detect again"; enabled:root.allowed && !WeatherLocation.busy; onClicked:WeatherLocation.useAutomatic() }
    RowLayout {
        Layout.fillWidth:true; spacing:8
        StationField { id:city; Layout.fillWidth:true; enabled:root.allowed; placeholderText:"Choose a city or postal code"; Accessible.name:"Search weather location"; onAccepted:find.clicked() }
        StationButton { id:find; text:WeatherLocation.searching ? "Searching…" : "Find"; enabled:root.allowed && !WeatherLocation.searching && city.text.trim().length>=2; onClicked:WeatherLocation.search(city.text) }
    }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; visible:text!==""; text:WeatherLocation.searchMessage; color:Theme.muted; font.pixelSize:Theme.small }
    Flow {
        Layout.fillWidth:true; spacing:6
        Repeater {
            model:WeatherLocation.results
            StationButton { required property var modelData; text:modelData.name; onClicked:WeatherLocation.select(modelData) }
        }
    }
    SettingControl { Layout.fillWidth:true; spec:root.spec("temperatureUnit"); highlightKey:root.highlightKey }
    StationButton { text:root.exact ? "Hide exact coordinates" : "Enter exact coordinates"; checked:root.exact; onClicked:root.exact=!root.exact }
    Repeater {
        model:root.exact ? ["locationName","latitude","longitude"] : []
        SettingControl { required property string modelData; Layout.fillWidth:true; spec:root.spec(modelData); highlightKey:root.highlightKey }
    }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"City search: Open-Meteo / GeoNames"; color:Theme.muted; font.pixelSize:10 }
}
