import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
SettingsCard {
    objectName: "weatherLocation"
    title: "Weather location"
    StationToggle { Layout.fillWidth:true; label:"Local-only mode"; description:"Blocks CEDAR weather, location and remote artwork requests. Local desktop controls keep working."; checked:Config.saved.localOnly; onToggled:value=>Config.set("localOnly",value) }
    StationToggle { Layout.fillWidth:true; label:"Allow weather"; description:"Finds your approximate city from your public IP, then Open-Meteo receives those coordinates for forecasts every 15 minutes. City search sends your query only when you use it."; enabled:!Config.localOnly; checked:Config.saved.weatherEnabled; onToggled:value=>Config.set("weatherEnabled",value) }
    StationToggle { Layout.fillWidth:true; label:"Allow remote media artwork"; description:"Artwork URLs supplied by media players contact their hosts when shown. Off by default."; enabled:!Config.localOnly; checked:Config.saved.remoteArtwork; onToggled:value=>Config.set("remoteArtwork",value) }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:WeatherLocation.status; color:WeatherLocation.error ? Theme.amber : Theme.muted }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"Location comes from your public IP through IPWhois unless you choose a city below. VPNs can point to another region. Your IP is not saved by CEDAR."; color:Theme.muted }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:WeatherLocation.manual ? "Use automatic location" : "Detect again"; enabled:!Config.localOnly && Config.saved.weatherEnabled && !WeatherLocation.busy; onClicked:WeatherLocation.useAutomatic() }
        StationButton { text:"Turn off automatic location"; visible:Config.saved.weatherAutomatic; onClicked:Config.set("weatherAutomatic",false) }
    }
    StationField { id:city; Layout.fillWidth:true; placeholderText:"City or postal code"; Accessible.name:"Search weather location"; onAccepted:WeatherLocation.search(text) }
    StationButton { text:WeatherLocation.searching ? "Searching…" : "Find city"; enabled:!Config.localOnly && Config.saved.weatherEnabled && !WeatherLocation.searching && city.text.trim().length>=2; onClicked:WeatherLocation.search(city.text) }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; visible:text!==""; text:WeatherLocation.searchMessage; color:Theme.muted }
    Repeater {
        model:WeatherLocation.results
        StationButton { required property var modelData; Layout.fillWidth:true; text:modelData.name; onClicked:WeatherLocation.select(modelData) }
    }
    GlowText { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"City search: Open-Meteo / GeoNames"; color:Theme.muted; font.pixelSize:Theme.small }
}
