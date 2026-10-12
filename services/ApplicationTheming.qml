pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
Singleton {
    id: root
    property string lastError: ""
    property var preferences: ({})
    readonly property bool enabled: preferences.enabled === true && preferences.mode !== "independent" && !Config.testMode
    readonly property string configPath: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string statePath: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    function schedule() { if (enabled) debounce.restart(); }
    FileView {
        path: root.configPath + "/cedar/application-theming.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.preferences = JSON.parse(text()); } catch (_) { root.preferences = ({}); } root.schedule(); }
        onLoadFailed: root.preferences = ({})
    }
    FileView {
        path: root.configPath + "/cedar/theme.json"
        watchChanges: true; printErrors: false
        onFileChanged: { reload(); root.schedule(); }
    }
    FileView {
        path: root.configPath + "/cedar/desktop.json"
        watchChanges: true; printErrors: false
        onFileChanged: { reload(); if (root.preferences.wallpaper) root.schedule(); }
    }
    FileView {
        path: root.preferences.mode === "external" ? (root.preferences.externalSource || "") : ""
        watchChanges: true; printErrors: false
        onFileChanged: { reload(); root.schedule(); }
    }
    FileView {
        path: (Quickshell.env("CEDAR_ADAPTER") === "omarchy" || Quickshell.env("CEDAR_OMARCHY_SESSION") === "1") ? root.statePath + "/omarchy/current/background" : ""
        preload: false; watchChanges: true; printErrors: false
        onFileChanged: { if (root.preferences.wallpaper) root.schedule(); }
    }
    Timer { id: debounce; interval: 750; onTriggered: request.send({action:"sync"}) }
    ServiceRequest {
        id: request; script: "scripts/application_theming.py"; timeoutMs: 90000
        onResult: root.lastError = ""
        onFailed: message => root.lastError = message
    }
}
