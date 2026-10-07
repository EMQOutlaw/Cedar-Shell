pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "components/SettingsSchema.js" as SettingsSchema
import "components/Compass.js" as Compass

// Defaults plus the settings panel's saved overrides. Saved values live in
// ~/.config/cedar/settings.json (XDG_CONFIG_HOME respected); the file is
// optional, hot-reloaded, and written only when a setting changes.
Singleton {
    id: root
    // 1: components + bar; 2: HUD; 3: complete shell.
    readonly property int stage: Math.max(1, Math.min(3, Number(Quickshell.env("CEDAR_STAGE") || Quickshell.env("FOXFIRE_STAGE") || 3)))
    readonly property bool testMode: (Quickshell.env("CEDAR_TEST") || Quickshell.env("FOXFIRE_TEST")) === "1"
    readonly property bool omarchyIntegration: Quickshell.env("CEDAR_ADAPTER") === "omarchy" || Quickshell.env("CEDAR_OMARCHY_SESSION") === "1"
    // Opt-in Trailwatch on Omarchy: the session helper sets this only after the
    // user chose it; the handoff itself happens after a verified lock cycle.
    readonly property bool trailwatchLock: omarchyIntegration && Quickshell.env("CEDAR_OMARCHY_LOCK") === "trailwatch"
    readonly property bool externalSession: (Quickshell.env("CEDAR_EXTERNAL_LOCK") === "1" || omarchyIntegration) && !trailwatchLock
    readonly property bool externalIdle: Quickshell.env("CEDAR_EXTERNAL_IDLE") === "1"
    readonly property bool managedSession: Quickshell.env("CEDAR_MANAGED_SESSION") === "1" || externalSession || omarchyIntegration
    readonly property string lockStatePath: Quickshell.env("CEDAR_LOCK_STATE") || stateDir + "/lock-state.json"
    readonly property bool externalBackground: Quickshell.env("CEDAR_BACKGROUND") === "external" || omarchyIntegration
    readonly property bool authOnly: Quickshell.env("CEDAR_AUTH_ONLY") === "1"
    readonly property bool localOnly: saved.localOnly || Quickshell.env("CEDAR_LOCAL_ONLY") === "1"
    function imageSource(value) {
        const source=String(value || "");
        if (/^https?:/i.test(source)) return !localOnly && saved.remoteArtwork ? source : "";
        if (/^(file:|qrc:|image:|data:)/i.test(source) || source.startsWith("/")) return source;
        return "";
    }
    readonly property string home: Quickshell.env("HOME")
    readonly property string settingsDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/cedar"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/cedar"
    readonly property string settingsPath: settingsDir + "/settings.json"
    readonly property alias saved: saved
    property string persistenceMessage:""

    // Legacy custom commands remain explicit user overrides. New app selections
    // store desktop IDs and launch through GIO, never through command concatenation.
    readonly property var terminal: appArgv("terminal", saved.terminal, ["python3", Quickshell.shellPath("scripts/desktop_runtime.py"), "launch", "terminal"])
    readonly property var browser: appArgv("browser", saved.browser, ["xdg-open", "https://duckduckgo.com"])
    readonly property var editor: appArgv("editor", saved.editor, ["python3", Quickshell.shellPath("scripts/desktop_runtime.py"), "launch", "editor"])
    readonly property var files: appArgv("files", saved.files, ["xdg-open", home])
    // The launchers' web search; unknown ids fall back to Compass's first engine.
    readonly property string searchEngine: Compass.engine(saved.searchEngine).id
    // Saved coordinates override the optional automatic weather location service.
    readonly property string latitude: saved.latitude.trim()
    readonly property string longitude: saved.longitude.trim()
    readonly property string locationName: saved.locationName.trim() || "Your ridge"
    readonly property string temperatureUnit: saved.temperatureUnit === "celsius" ? "celsius" : "fahrenheit"
    readonly property string brightnessDevice: saved.brightnessDevice.trim() // empty selects brightnessctl's default backlight
    readonly property string diskPath: saved.diskPath.trim() || home
    readonly property int idleLockSeconds: isFinite(saved.idleLockSeconds) ? Math.max(0, Math.round(saved.idleLockSeconds)) : 600
    readonly property bool clock24: saved.clock24
    readonly property string dateStyle: ["month-first", "day-first", "iso"].includes(saved.dateStyle) ? saved.dateStyle : "month-first"
    function formatDate(date, compact = false) {
        const formats = compact ? {"month-first": "MMM d", "day-first": "d MMM", "iso": "MM-dd"}
                                : {"month-first": "MMMM d, yyyy", "day-first": "d MMMM yyyy", "iso": "yyyy-MM-dd"};
        return (saved.showWeekday ? Qt.formatDateTime(date, compact ? "ddd" : "dddd") + ", " : "") + Qt.formatDateTime(date, formats[dateStyle]);
    }
    function barClock(date) { return (saved.barShowDate ? formatDate(date, true) + "  " : "") + formatTime(date); }
    readonly property string timeFormat: clock24 ? "HH:mm" : "h:mm AP"
    function formatTime(date) { return Qt.formatDateTime(date, timeFormat); }
    function timeDigits(date) { return formatTime(date).split(" ")[0]; }
    readonly property string pamService: Quickshell.env("CEDAR_PAM_SERVICE") || (omarchyIntegration ? "omarchy-lock-password" : "login")
    readonly property string pamDirectory: "/etc/pam.d"

    readonly property string canonicalBarStyle: saved.barStyle === "foxfire" ? "cedar" : saved.barStyle
    readonly property string barStyle: ["cedar", "floating", "minimal", "islands", "center", "split"].includes(canonicalBarStyle) ? canonicalBarStyle : "cedar"
    readonly property bool barDetached: ["floating", "islands", "center", "split"].includes(barStyle)
    readonly property bool barIslands: ["islands", "center", "split"].includes(barStyle)
    readonly property int barHeight: Math.max(40, Math.min(72, saved.barHeight))
    readonly property real barOpacity: Math.max(0.1, Math.min(1, saved.barOpacity))
    readonly property int barRadius: Math.max(0, Math.min(30, saved.barRadius))
    readonly property int barSpacing: Math.max(0, Math.min(20, saved.barSpacing))
    readonly property int barMargin: Math.max(0, Math.min(32, saved.barMargin))
    readonly property real panelOpacity: Math.max(.88, Math.min(1,saved.panelOpacity))
    readonly property int panelRadius: Math.max(0,Math.min(28,saved.panelRadius))
    function moduleEnabled(name) { return !saved.hiddenBarModules.includes(name); }
    function setModule(name,enabled) { saved.hiddenBarModules=enabled ? saved.hiddenBarModules.filter(n=>n!==name) : [...new Set(saved.hiddenBarModules.concat([name]))]; }
    function resetBar() {
        saved.barStyle = "cedar"; saved.barHeight = 44; saved.barOpacity = 0.94;
        saved.barRadius = 16; saved.barSpacing = 6; saved.barMargin = 12; saved.hiddenBarModules = [];
    }

    function appArgv(role, legacy, fallback) {
        const target = saved.applicationTargets[role];
        if (target && target.kind === "desktop-entry" && typeof target.id === "string")
            return ["python3", Quickshell.shellPath("scripts/default_apps.py"), "--launch", target.id];
        return argv(legacy, fallback);
    }
    function argv(text, fallback) {
        const line = String(text || "").trim();
        return line ? line.split(/\s+/) : fallback;
    }
    // Settings that other local processes may change over `settings set`.
    // Anything that launches commands, reaches the network, stores location,
    // or weakens the lock screen stays with the Settings panel and the file.
    readonly property var ipcProtected: ["applicationTargets", "terminal", "browser", "editor", "files", "localOnly", "weatherEnabled", "weatherAutomatic", "remoteArtwork", "latitude", "longitude", "locationName", "brightnessDevice", "diskPath", "idleLockSeconds", "lockPrivacy", "lockMediaDetails", "lockAgendaDetails", "lockMediaControls", "clipboardHistory", "forestTrails", "whisperLedger"]
    function ipcSet(key, value) {
        if (!(key in saved)) return "unknown setting: " + key;
        if (ipcProtected.includes(key)) return "protected setting: " + key + " (use Settings)";
        if (ShellState.locked) return "locked";
        const current = saved[key];
        if (typeof current === "boolean") { if (value !== "true" && value !== "false") return "expected true or false"; set(key, value === "true"); }
        else if (typeof current === "number") { const n = Number(value); if (!isFinite(n)) return "expected a number"; set(key, n); }
        else if (typeof current === "string") set(key, String(value).slice(0, 1000));
        else return "unsupported setting type: " + key;
        return "ok";
    }
    function ipcGet(key) {
        if (!(key in saved)) return "unknown setting: " + key;
        if (ipcProtected.includes(key)) return "protected setting: " + key;
        return String(saved[key]);
    }
    function set(key, value) {
        if (!(key in saved) || saved[key] === value) return;
        if (key === "applicationTargets" && JSON.stringify(saved.applicationTargets) === JSON.stringify(value)) return;
        if (["terminal", "browser", "editor", "files"].includes(key)) {
            const targets = Object.assign({}, saved.applicationTargets);
            delete targets[key]; saved.applicationTargets = targets;
        }
        saved[key] = value;
    }
    function reset() {
        resetBar(); SettingsSchema.fields.forEach(f=>set(f.key,f.defaultValue));
        saved.mainDisplay="";
    }

    function savePreferences() {
        let document = {};
        try { document = JSON.parse(store.text() || "{}"); }
        catch (error) { persistenceMessage = "Preferences contain invalid JSON. Repair the file before saving."; return; }
        if (!document || typeof document !== "object" || Array.isArray(document)) return;
        const keys = ["applicationTargets", "localOnly", "weatherEnabled", "remoteArtwork", "terminal", "browser", "editor", "files", "latitude", "longitude", "locationName", "weatherAutomatic", "temperatureUnit", "brightnessDevice", "diskPath", "idleLockSeconds", "lockPrivacy", "lockMediaDetails", "lockAgendaDetails", "lockMediaControls", "reducedMotion", "doNotDisturb", "interfaceFont", "dataFont", "fontScale", "panelOpacity", "panelRadius", "ambientIntensity", "wallpaperMode", "wallpaperFolder", "desktopSignature", "notificationsEnabled", "notificationSeconds", "hiddenBarModules", "goFavorites", "searchEngine", "performanceMode", "canopyEnabled", "canopyPeek", "forestPulse", "forestEchoes", "forestWhispers", "whisperLedger", "whisperDevices", "whisperQuiet", "whisperBattery", "forestTrails", "clipboardHistory", "audioSpectrum", "coreEnabled", "coreMonitor", "coreVolume", "coreMedia", "coreNotifications", "coreScreenshots", "coreConnections", "corePower", "corePrivacy", "coreWorkspaces", "coreKeyboard", "coreClipboard", "coreWarnings", "coreTemperatureLimit", "coreDiskLimit", "mainDisplay", "clock24", "dateStyle", "showWeekday", "barShowDate", "barStyle", "barHeight", "barOpacity", "barRadius", "barSpacing", "barMargin"];
        keys.forEach(key => document[key] = saved[key]);
        store.setText(JSON.stringify(document, null, 2) + "\n");
    }
    Process { command: ["mkdir", "-p", "-m", "700", root.settingsDir, root.stateDir]; running: true }
    // Batch a preset/reset into one write so file reloads cannot restore an
    // intermediate snapshot over the remaining changes.
    Timer { id: saveTimer; interval: 100; onTriggered: root.savePreferences() }
    FileView {
        id: store
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: {
            if(saveTimer.running){saveTimer.stop();root.persistenceMessage="Preferences changed in another editor. Reloaded the file; repeat your last adjustment if needed.";}
            reload();
        }
        onAdapterUpdated: saveTimer.restart()
        JsonAdapter {
            id: saved
            property var applicationTargets: ({})
            property string terminal: ""
            property string browser: ""
            property string editor: ""
            property string files: ""
            property bool localOnly: true
            property bool weatherEnabled: false
            property bool remoteArtwork: false
            property bool weatherAutomatic: true
            property string latitude: ""
            property string longitude: ""
            property string locationName: ""
            property string temperatureUnit: "fahrenheit"
            property string brightnessDevice: ""
            property string diskPath: ""
            property int idleLockSeconds: 600
            property bool lockPrivacy: true
            property bool lockMediaDetails: false
            property bool lockAgendaDetails: false
            property bool lockMediaControls: false
            property bool reducedMotion: false
            property bool doNotDisturb: false
            property string interfaceFont: "Rajdhani"
            property string dataFont: "JetBrainsMono Nerd Font"
            property real fontScale: 1
            property real panelOpacity: .97
            property int panelRadius: 16
            property real ambientIntensity: .45
            property string wallpaperMode: "crop"
            property string wallpaperFolder: ""
            property bool desktopSignature: true
            property bool notificationsEnabled: true
            property int notificationSeconds: 7
            property var hiddenBarModules: []
            property var goFavorites: []
            property string searchEngine: "brave"
            property string performanceMode: "auto"
            property bool canopyEnabled:true
            property bool canopyPeek:true
            property bool forestPulse:true
            property bool forestEchoes:true
            property bool forestWhispers:true
            property string whisperLedger:"{}"
            property bool whisperDevices:true
            property bool whisperQuiet:true
            property bool whisperBattery:true
            property bool forestTrails:false
            property bool clipboardHistory:false
            property bool audioSpectrum:false
            property bool coreEnabled:true
            property string coreMonitor:""
            property bool coreVolume:true
            property bool coreMedia:true
            property bool coreNotifications:true
            property bool coreScreenshots:true
            property bool coreConnections:true
            property bool corePower:true
            property bool corePrivacy:true
            property bool coreWorkspaces:false
            property bool coreKeyboard:true
            property bool coreClipboard:false
            property bool coreWarnings:true
            property int coreTemperatureLimit:90
            property int coreDiskLimit:95
            property string mainDisplay: ""
            property bool clock24: true
            property string dateStyle: "month-first"
            property bool showWeekday: true
            property bool barShowDate: true
            property string barStyle: "cedar"
            property int barHeight: 44
            property real barOpacity: 0.94
            property int barRadius: 16
            property int barSpacing: 6
            property int barMargin: 12
        }
    }
    Binding { target: Theme; property: "labelFont"; value: Theme.resolveFont(saved.interfaceFont || "Rajdhani", "sans-serif") }
    Binding { target: Theme; property: "dataFont"; value: Theme.resolveFont(saved.dataFont || "JetBrainsMono Nerd Font", "monospace") }
    Binding { target: Theme; property: "fontScale"; value: Math.max(.85,Math.min(1.3,saved.fontScale)) }
    // Performance mode: the basics only. "auto" follows the power-saver profile
    // and a fullscreen focused window (how games run); "on" and "off" override.
    // It rides on Reduced Motion for every decorative loop and entrance, and
    // SystemStats drops its ambient pulse while it is active.
    readonly property string performanceMode: ["auto", "on", "off"].includes(saved.performanceMode) ? saved.performanceMode : "auto"
    readonly property bool powerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    property bool fullscreenFocused: false
    function readFullscreen() {
        const window = Hyprland.activeToplevel?.lastIpcObject;
        fullscreenFocused = !!window && Number(window.fullscreen) > 0;
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.readFullscreen(); }
        function onRawEvent(event) { if (event.name === "fullscreen") Hyprland.refreshToplevels(); }
    }
    Connections { target: Hyprland.activeToplevel; function onLastIpcObjectChanged() { root.readFullscreen(); } }
    readonly property bool performanceActive: performanceMode === "on" || (performanceMode === "auto" && (powerSaving || fullscreenFocused))
    readonly property string performanceReason: performanceMode === "on" ? "always on" : powerSaving ? "power-saver profile" : fullscreenFocused ? "fullscreen window" : ""
    Binding { target: Theme; property: "reducedMotion"; value: saved.reducedMotion || root.performanceActive }
}
