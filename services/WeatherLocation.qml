pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var detected: ({})
    property string error: ""
    property string searchMessage: ""
    property var results: []
    readonly property bool manual: Config.latitude !== "" || Config.longitude !== ""
    readonly property bool manualValid: Config.latitude !== "" && Config.longitude !== "" && Number.isFinite(Number(Config.latitude)) && Number.isFinite(Number(Config.longitude)) && Math.abs(Number(Config.latitude)) <= 90 && Math.abs(Number(Config.longitude)) <= 180
    readonly property bool automatic: !Config.localOnly && Config.saved.weatherEnabled && Config.saved.weatherAutomatic && !manual
    readonly property string latitude: manual ? (manualValid ? Config.latitude : "") : automatic && detected.latitude !== undefined ? String(detected.latitude) : ""
    readonly property string longitude: manual ? (manualValid ? Config.longitude : "") : automatic && detected.longitude !== undefined ? String(detected.longitude) : ""
    readonly property bool available: latitude !== "" && longitude !== ""
    readonly property string label: manualValid ? (Config.saved.locationName.trim() || "Saved location") : automatic && detected.name ? detected.name : "Your area"
    readonly property bool busy: lookup.running
    readonly property bool searching: cities.running
    readonly property string status: Config.localOnly ? "Local-only mode · external weather requests are off." : !Config.saved.weatherEnabled ? "Weather needs permission in External access." : manual ? (manualValid ? "Saved location · " + label : "Check your saved latitude and longitude.") : !automatic ? "Automatic location is off." : busy ? "Finding your approximate location…" : error ? error : available ? (detected.stale ? "Last known location · " : "Approximate location · ") + label : "Waiting for location…"
    function refresh(force=false) { if (automatic && !Config.testMode && !lookup.running) { error=""; lookup.send({action:"locate",force:force}); } }
    function search(query) { if (!Config.localOnly && Config.saved.weatherEnabled && !Config.testMode && !cities.running) { results=[];searchMessage="Searching…";cities.send({action:"search",query:query}); } }
    function select(place) {
        Config.set("locationName", place.name);
        Config.set("latitude", String(place.latitude));
        Config.set("longitude", String(place.longitude));
        results=[]; searchMessage="Location saved.";
    }
    function useAutomatic() {
        Config.set("latitude", ""); Config.set("longitude", ""); Config.set("locationName", "");
        Config.set("weatherAutomatic", true);
        Qt.callLater(()=>root.refresh(true));
    }
    onAutomaticChanged: Qt.callLater(()=>root.refresh())
    Component.onCompleted: Qt.callLater(()=>root.refresh())
    ServiceRequest {
        id: lookup; script:"scripts/weather_location.py"
        onResult: value => { if (root.automatic) { root.detected=value;root.error=""; } }
        onFailed: message => root.error=message
    }
    ServiceRequest {
        id: cities; script:"scripts/weather_location.py"
        onResult: value => {root.results=value.results || [];root.searchMessage=root.results.length ? "Choose a location below." : "No matching places. Try adding a region or country.";}
        onFailed: message => root.searchMessage=message
    }
    // Shared across all weather surfaces. The helper caches successful lookups
    // for a day and backs off failures, including across shell restarts.
    Timer { interval:1800000; repeat:true; running:root.automatic && !Config.testMode; onTriggered:root.refresh() }
}
