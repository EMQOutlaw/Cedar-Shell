pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".."

Singleton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null
    readonly property real volume: audio?.volume ?? 0
    readonly property bool muted: audio?.muted ?? false
    readonly property string label: !audio ? "No audio device" : muted ? "MUTED" : Math.round(volume * 100) + "%"
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var microphone: source?.audio ?? null
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream)
    PwObjectTracker { objects: [...root.outputs, ...root.inputs, ...root.streams] }
    function selectOutput(node) { Pipewire.preferredDefaultAudioSink = node; }
    function selectInput(node) { Pipewire.preferredDefaultAudioSource = node; }
    function setMicrophone(value) { if (microphone) microphone.volume=Math.max(0,Math.min(1,value)); }
    function toggleMicrophone() { if (microphone) microphone.muted=!microphone.muted; }
    function show() { ShellState.osd("VOLUME", volume, label); }
    function change(delta) {
        if (audio) { audio.muted = false; audio.volume = Math.max(0, Math.min(1, volume + delta/100)); }
        show();
    }
    function toggleMute() { if (audio) audio.muted = !audio.muted; show(); }
    function setVolume(value) { if (audio) { audio.muted = false; audio.volume = Math.max(0, Math.min(1, value)); } }
}
