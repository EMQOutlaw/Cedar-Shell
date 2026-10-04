pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property string temperature: "—"
    property string condition: WeatherLocation.status
    property string feelsLike: "—"
    property string wind: ""
    property var rain: null
    property int code: -1
    property var updatedAt: null
    readonly property string updated: updatedAt ? Config.formatTime(updatedAt) : ""
    property var hours: []
    property string sunrise: ""
    property string sunset: ""
    property bool stale: false
    readonly property bool configured: !Config.localOnly && Config.saved.weatherEnabled && WeatherLocation.available
    function describe(code) {
        if (code === 0)
            return "Clear above the ridge";
        if (code <= 3)
            return "Clouds over the holler";
        if (code <= 48)
            return "Mist in the valley";
        if (code <= 67)
            return "Rain on the leaves";
        if (code <= 77)
            return "Snow on the mountain";
        if (code <= 82)
            return "Passing showers";
        if (code <= 86)
            return "Snow showers";
        return "Thunder beyond the ridge";
    }
    readonly property string query: WeatherLocation.latitude + "," + WeatherLocation.longitude + "," + Config.temperatureUnit
    onQueryChanged: {
        updatedAt = null;
        stale = false;
        temperature = "—";
        feelsLike = "—";
        wind = "";
        rain = null;
        code = -1;
        hours = [];
        sunrise = "";
        sunset = "";
        condition = configured ? "Waiting for weather" : WeatherLocation.status;
        refresh();
    }
    Connections { target: WeatherLocation; function onStatusChanged() { if (!root.configured) root.condition=WeatherLocation.status; } }
    function refresh() {
        if (configured && !fetch.running && !Config.testMode)
            fetch.running = true;
    }
    Process {
        id: fetch
        property string requestQuery: ""
        command: ["python3", Quickshell.shellPath("scripts/telemetry.py"), "weather", WeatherLocation.latitude, WeatherLocation.longitude, Config.temperatureUnit]
        onStarted: requestQuery = root.query
        onExited: if (requestQuery !== root.query)
            root.refresh()
        stdout: StdioCollector {
            onStreamFinished: {
                if (fetch.requestQuery !== root.query)
                    return;
                try {
                    const s = JSON.parse(text);
                    if (s.error)
                        throw new Error(s.error);
                    if (!Number.isFinite(s.current.temperature_2m) || !Number.isFinite(s.current.weather_code))
                        throw new Error("Missing weather");
                    root.temperature = Math.round(s.current.temperature_2m) + s.units.temperature_2m;
                    root.code = s.current.weather_code;
                    root.condition = root.describe(root.code);
                    root.feelsLike = Number.isFinite(s.current.apparent_temperature) ? Math.round(s.current.apparent_temperature) + s.units.temperature_2m : "—";
                    root.wind = Number.isFinite(s.current.wind_speed_10m) ? s.current.wind_speed_10m + " " + s.units.wind_speed_10m : "—";
                    root.updatedAt = new Date();
                    root.stale = false;
                    const times = s.hourly?.time || [], current = s.current.time || "";
                    const index = times.findIndex(t => t.slice(0, 13) === current.slice(0, 13));
                    root.rain = index >= 0 ? s.hourly.precipitation_probability[index] : null;
                    root.hours = times.map((t, i) => ({
                                stamp: t,
                                time: t.slice(11, 16),
                                temperature: Number.isFinite(s.hourly.temperature_2m[i]) ? Math.round(s.hourly.temperature_2m[i]) + s.units.temperature_2m : "—",
                                rain: s.hourly.precipitation_probability[i]
                            })).filter(h => h.stamp >= current).slice(0, 8);
                    root.sunrise = (s.daily?.sunrise?.[0] || "").slice(11, 16);
                    root.sunset = (s.daily?.sunset?.[0] || "").slice(11, 16);
                } catch (_) {
                    root.stale = true;
                    if (!root.updatedAt)
                        root.condition = "Weather unavailable";
                }
            }
        }
    }
    Timer {
        interval: 900000
        running: root.configured && !Config.testMode
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
