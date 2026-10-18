import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Settings › Dictation: Voxtype's state and its everyday settings, changed
// through Voxtype's own `config set` (scripts/dictation.py) and applied at
// once with a daemon restart. Anything not here stays in Voxtype's own TUI.
ColumnLayout {
    id: root
    property string highlightKey: ""
    readonly property bool ready: Dictation.installed && Dictation.configRead
    readonly property bool editable: ready && !Dictation.applying && !Dictation.downloading && !ShellState.locked
    readonly property var languages: [{value:"auto",label:"Detect"},{value:"en",label:"English"},{value:"es",label:"Español"},{value:"fr",label:"Français"},{value:"de",label:"Deutsch"},{value:"it",label:"Italiano"},{value:"pt",label:"Português"},{value:"nl",label:"Nederlands"},{value:"pl",label:"Polski"},{value:"ru",label:"Русский"},{value:"ja",label:"日本語"},{value:"zh",label:"中文"},{value:"ko",label:"한국어"},{value:"ar",label:"العربية"}]
    function v(key, fallback) { return Dictation.setting(key, fallback); }
    function deviceLabel(name) { return name === "default" ? "System default" : name; }
    spacing: 16
    Component.onCompleted: { Dictation.refresh(); Dictation.readConfig(); }
    Connections { target: Dictation; function onInstalledChanged() { if (Dictation.installed && !Dictation.configRead) Dictation.readConfig(); } }

    SettingsSection {
        objectName: "dictation"
        heading: "Dictation"
        caption: "Push-to-talk voice typing through Voxtype: hold F9 and speak, or press Super+Ctrl+X to toggle. What you said is typed where the cursor is."
        badge: Dictation.installed ? Dictation.label : "Not installed"
        badgeColor: Dictation.recording ? Theme.ember : Dictation.transcribing ? Theme.amber : Dictation.installed && Dictation.daemon ? Theme.green : Theme.muted
        GridLayout {
            visible: Dictation.installed
            Layout.fillWidth: true; columns: root.width < 600 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
            Readout { label: "Voxtype"; lit: Dictation.daemon; tone: Dictation.recording ? Theme.ember : Theme.green; value: Dictation.label; detail: Dictation.daemon ? "The daemon runs as your user service" + (Dictation.version ? " · v" + Dictation.version : "") + "." : "Start it with: systemctl --user start voxtype" }
            Readout { label: "Model"; lit: Dictation.model !== ""; tone: Theme.teal; value: Dictation.model || "—"; detail: Dictation.backend ? "Runs on " + Dictation.backend + "." : "Chosen below." }
            Readout { label: "Microphone"; lit: Dictation.device !== ""; tone: Theme.teal; value: root.deviceLabel(Dictation.device || "—"); detail: "Voxtype records from this device; the system default follows Settings › Audio." }
        }
        Flow {
            Layout.fillWidth: true; spacing: 8
            StationButton { visible: Dictation.installed; text: Dictation.recording ? "Stop and type" : Dictation.transcribing ? "Transcribing…" : "Start listening"; enabled: Dictation.available && !Dictation.transcribing; accent: Dictation.recording ? Theme.ember : Theme.teal; onClicked: Dictation.recording ? Dictation.stop() : Dictation.start() }
            StationButton { visible: Dictation.active; text: "Cancel"; accent: Theme.amber; enabled: Dictation.available; onClicked: Dictation.cancel() }
            StationButton { text: "Check again"; onClicked: { Dictation.refresh(); Dictation.readConfig(); } }
        }
        RowLayout {
            visible: Dictation.installed
            spacing: 10
            Keycap { keys: "SUPER + CTRL + X" }
            GlowText { text: "toggle"; color: Theme.muted; font.pixelSize: Theme.small }
            Keycap { keys: "F9" }
            GlowText { text: "hold to talk, release to type"; color: Theme.muted; font.pixelSize: Theme.small }
        }
        GlowText { visible: !Dictation.checked; text: "Looking for Voxtype…"; color: Theme.muted; font.pixelSize: Theme.small }
        GlowText { visible: Dictation.checked && !Dictation.installed; text: "Voxtype is not installed, so there is no dictation button or keybind. It comes from voxtype.io; on Omarchy, Install › AI › Dictation adds it with its model. CEDAR finds it on the next Check again or shell start."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
        GlowText { visible: Dictation.error !== ""; text: Dictation.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    }

    // What follows is Voxtype's configuration. Every change is written by
    // `voxtype config set` and takes effect after the daemon restarts (a second).
    GlowText { visible: Dictation.installed && !Dictation.configRead && Dictation.configError === ""; text: "Reading Voxtype's settings…"; color: Theme.muted; font.pixelSize: Theme.small }
    GlowText { visible: Dictation.configError !== ""; text: Dictation.configError; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    GlowText { visible: Dictation.message !== "" && Dictation.configError === ""; text: Dictation.message; color: Dictation.applying || Dictation.downloading ? Theme.amber : Theme.teal; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }

    SettingsSection {
        objectName: "speech"
        visible: root.ready
        heading: "Speech"
        caption: "The Whisper model that turns speech into text. Bigger models hear better and take longer; .en models are English only and quicker."
        badge: String(root.v("whisper.model", ""))
        ColumnLayout {
            Layout.fillWidth: true; spacing: 6
            GlowText { text: "Model"; font.pixelSize: Theme.small; color: Theme.muted }
            ChoiceChips {
                Layout.fillWidth: true; enabled: root.editable; accessibleLabel: "Speech model"
                options: Dictation.installedModels.map(m => ({ value: m.name, label: m.name }))
                current: root.v("whisper.model", "")
                onChosen: value => Dictation.set("whisper.model", value)
            }
            GlowText { visible: !Dictation.installedModels.length; text: "No Whisper model is installed yet; download one below."; color: Theme.amber; font.pixelSize: Theme.small }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: Dictation.downloadableModels.length > 0
            StationCombo {
                id: wanted
                Layout.fillWidth: true
                enabled: root.editable
                model: Dictation.downloadableModels.map(m => m.name)
                Accessible.name: "Model to download"
            }
            StationButton {
                text: Dictation.downloading ? "Downloading " + Dictation.downloadingModel + "…" : "Download"
                enabled: root.editable && wanted.currentText !== ""
                hint: "Fetches the model into ~/.local/share/voxtype/models; it does not switch to it"
                onClicked: Dictation.download(wanted.currentText)
            }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Language"; description: "What you speak. Detect listens for any language; a .en model always hears English."
            ChoiceChips { Layout.fillWidth: true; enabled: root.editable; accessibleLabel: "Language"; options: root.languages; current: root.v("whisper.language", "en"); onChosen: value => Dictation.set("whisper.language", value) }
        }
        StationToggle { Layout.fillWidth: true; label: "Translate to English"; description: "Type an English translation instead of what was said."; checked: root.v("whisper.translate", false) === true; busy: !root.editable; onToggled: value => Dictation.set("whisper.translate", value) }
    }

    SettingsSection {
        objectName: "listening"
        visible: root.ready
        heading: "Listening"
        caption: "Which microphone Voxtype records and what happens around a recording."
        SettingRow {
            Layout.fillWidth: true; title: "Microphone"; description: "System default follows the device chosen under Settings › Audio."
            StationCombo {
                Layout.fillWidth: true; enabled: root.editable
                model: Dictation.devices.map(d => root.deviceLabel(d.name))
                currentIndex: Math.max(0, Dictation.devices.findIndex(d => d.name === root.v("audio.device", "default")))
                Accessible.name: "Dictation microphone"
                onActivated: index => { const d = Dictation.devices[index]; if (d && d.name !== root.v("audio.device", "default")) Dictation.set("audio.device", d.name); }
            }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Longest recording"; description: "A safety cap: " + Math.round(duration.value) + " seconds, then it stops and types on its own."
            StationSlider { id: duration; Layout.fillWidth: true; enabled: root.editable; from: 5; to: 300; stepSize: 5; value: Number(root.v("audio.max_duration_secs", 60)); Accessible.name: "Longest recording in seconds"; onCommitted: value => { if (Math.round(value) !== Number(root.v("audio.max_duration_secs", 60))) Dictation.set("audio.max_duration_secs", Math.round(value)); } }
        }
        StationToggle { Layout.fillWidth: true; label: "Pause media while listening"; description: "Pause players over MPRIS when a recording starts and resume them after."; checked: root.v("audio.pause_media", true) === true; busy: !root.editable; onToggled: value => Dictation.set("audio.pause_media", value) }
        StationToggle { Layout.fillWidth: true; label: "Sound cues"; description: "A short sound when listening starts and stops."; checked: root.v("audio.feedback.enabled", false) === true; busy: !root.editable; onToggled: value => Dictation.set("audio.feedback.enabled", value) }
        SettingRow {
            visible: root.v("audio.feedback.enabled", false) === true
            Layout.fillWidth: true; title: "Cue sound"; description: "Volume " + Math.round(cueVolume.value * 100) + "%."
            ChoiceChips { enabled: root.editable; accessibleLabel: "Cue sound"; options: [{value:"default",label:"Default"},{value:"subtle",label:"Subtle"},{value:"mechanical",label:"Mechanical"}]; current: root.v("audio.feedback.theme", "default"); onChosen: value => Dictation.set("audio.feedback.theme", value) }
            StationSlider { id: cueVolume; Layout.fillWidth: true; enabled: root.editable; from: 0; to: 1; stepSize: .05; value: Number(root.v("audio.feedback.volume", .7)); Accessible.name: "Cue volume"; onCommitted: value => { if (Math.abs(value - Number(root.v("audio.feedback.volume", .7))) > .01) Dictation.set("audio.feedback.volume", Math.round(value * 100) / 100); } }
        }
        StationToggle { Layout.fillWidth: true; label: "Skip silent recordings"; description: "Voice detection drops a recording with no speech in it instead of typing noise."; checked: root.v("vad.enabled", false) === true; busy: !root.editable; onToggled: value => Dictation.set("vad.enabled", value) }
    }

    SettingsSection {
        objectName: "typing"
        visible: root.ready
        heading: "Typing"
        caption: "How the words reach the window: typed as keystrokes, copied, or pasted. Typing uses wtype, dotool or ydotool, whichever is installed."
        SettingRow {
            Layout.fillWidth: true; title: "Deliver as"; description: "Type presses the keys; Clipboard only copies; Paste copies and presses the paste shortcut."
            ChoiceChips { Layout.fillWidth: true; enabled: root.editable; accessibleLabel: "Deliver as"; options: [{value:"type",label:"Type"},{value:"clipboard",label:"Clipboard"},{value:"paste",label:"Paste"}]; current: root.v("output.mode", "type"); onChosen: value => Dictation.set("output.mode", value) }
        }
        StationToggle { Layout.fillWidth: true; label: "Copy if typing fails"; description: "When no typing driver works, the text lands on the clipboard instead of being lost."; checked: root.v("output.fallback_to_clipboard", true) === true; busy: !root.editable; onToggled: value => Dictation.set("output.fallback_to_clipboard", value) }
        StationToggle { Layout.fillWidth: true; label: "Spoken punctuation"; description: "Say \"period\", \"comma\" or \"new line\" to get the character."; checked: root.v("text.spoken_punctuation", false) === true; busy: !root.editable; onToggled: value => Dictation.set("text.spoken_punctuation", value) }
        StationToggle { Layout.fillWidth: true; label: "Drop filler words"; description: "Remove \"uh\", \"um\" and the like from what is typed."; checked: root.v("text.filter_filler_words", true) === true; busy: !root.editable; onToggled: value => Dictation.set("text.filter_filler_words", value) }
        StationToggle { Layout.fillWidth: true; label: "Press Enter afterwards"; description: "Send Return once the text is typed, for chat boxes and prompts."; checked: root.v("output.auto_submit", false) === true; busy: !root.editable; onToggled: value => Dictation.set("output.auto_submit", value) }
        StationToggle { Layout.fillWidth: true; label: "Say \"submit\" to send"; description: "A trailing \"submit\" is removed from the text and Return is pressed instead."; checked: root.v("text.smart_auto_submit", false) === true; busy: !root.editable; onToggled: value => Dictation.set("text.smart_auto_submit", value) }
        StationToggle { Layout.fillWidth: true; label: "New lines as Shift+Enter"; description: "So chat apps add a line instead of sending early."; checked: root.v("output.shift_enter_newlines", false) === true; busy: !root.editable; onToggled: value => Dictation.set("output.shift_enter_newlines", value) }
        SettingRow {
            Layout.fillWidth: true; title: "Pause before typing"; description: Math.round(preDelay.value) + " ms, so a virtual keyboard can attach first. 0 is instant."
            StationSlider { id: preDelay; Layout.fillWidth: true; enabled: root.editable; from: 0; to: 2000; stepSize: 50; value: Number(root.v("output.pre_type_delay_ms", 0)); Accessible.name: "Pause before typing in milliseconds"; onCommitted: value => { if (Math.round(value) !== Number(root.v("output.pre_type_delay_ms", 0))) Dictation.set("output.pre_type_delay_ms", Math.round(value)); } }
        }
    }

    SettingsSection {
        objectName: "notifications"
        visible: root.ready
        heading: "Notifications"
        caption: "Voxtype's own notifications. The bar microphone and the Core row show its state either way."
        StationToggle { Layout.fillWidth: true; label: "When listening starts"; checked: root.v("output.notification.on_recording_start", false) === true; busy: !root.editable; onToggled: value => Dictation.set("output.notification.on_recording_start", value) }
        StationToggle { Layout.fillWidth: true; label: "When listening stops"; checked: root.v("output.notification.on_recording_stop", false) === true; busy: !root.editable; onToggled: value => Dictation.set("output.notification.on_recording_stop", value) }
        StationToggle { Layout.fillWidth: true; label: "With the text, once typed"; checked: root.v("output.notification.on_transcription", false) === true; busy: !root.editable; onToggled: value => Dictation.set("output.notification.on_transcription", value) }
    }

    SettingsSection {
        objectName: "voxtype"
        visible: Dictation.installed
        heading: "Voxtype itself"
        caption: "Everything else (engines, remote transcription, meeting mode, word replacements) lives in Voxtype's own setup screen and its config.toml under ~/.config/voxtype."
        Flow {
            Layout.fillWidth: true; spacing: 8
            StationButton { text: "Open Voxtype's setup"; hint: "voxtype configure, in your terminal"; enabled: !ShellState.locked; onClicked: Dictation.configure() }
            StationButton { text: "Restart Voxtype"; enabled: root.editable; onClicked: Dictation.restartDaemon() }
        }
    }
}
