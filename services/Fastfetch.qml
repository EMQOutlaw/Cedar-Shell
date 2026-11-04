pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    // CEDAR's Fastfetch editor state: the committed model (what config.jsonc
    // holds), the draft the page edits, and the live preview specimen.
    property var model: null        // committed
    property var draft: null        // being edited
    property bool ready: false
    property bool installed: false
    property bool configError: false
    property string configErrorText: ""
    property string error: ""
    property string message: ""
    property string previewText: ""
    property bool previewBusy: false
    property bool saving: false
    property string configPath: ""
    property string errorKind: ""   // which request the error belongs to: get/save/preview
    property string previewError: ""  // a failed preview, kept apart from persistent save/get failures
    property int previewGeneration: 0  // bumped by discard(): older specimens are stale
    property var catalog: []
    property var presets: []       // fastfetch's shipped community presets
    readonly property bool dirty: ready && draft !== null && JSON.stringify(draft) !== JSON.stringify(model)
    readonly property var rows: draft ? draft.rows : []
    property double lastRead: 0
    // True while a request that replaces the draft (get/save) is in flight:
    // commits during those would be silently dropped. Previews only paint the
    // specimen, so editing stays live while one runs.
    property bool commitLock: false

    readonly property bool busy: worker ? worker.busy : false
    function refresh(force) {
        // Reads are allowed under test mode (the helper's get is strictly
        // read-only, so harnesses verify the real render); only writes refuse.
        if (busy) return;
        if (!force && Date.now() - lastRead < 15000) return;
        lastRead = Date.now();
        commitLock = true;
        worker.send({action: "get"});
    }
    function edit(fn) {
        if (!ready || typeof fn !== "function" || commitLock || saving) return;
        const next = JSON.parse(JSON.stringify(draft));
        fn(next);
        draft = next;
        previewTimer.restart();
    }
    function setLogo(key, value) { edit(m => { m.logo[key] = value; }); }
    function setAccent(value) { edit(m => { m.accent = value; }); }
    function setRowLabel(index, label) { edit(m => { if (m.rows[index] && !m.rows[index].fixed) m.rows[index].label = label; }); }
    function moveRow(index, delta) { edit(m => { const j = index + delta; if (j < 0 || j >= m.rows.length) return; const t = m.rows[index]; m.rows[index] = m.rows[j]; m.rows[j] = t; }); }
    function removeRow(index) { edit(m => { m.rows.splice(index, 1); }); }
    function addRow(key) {
        edit(m => {
            if (m.rows.some(r => r.key === key)) return;  // fastfetch would print it twice
            m.rows.push({ kind: "module", key: key, label: key.toUpperCase() });
        });
    }
    // A community preset becomes the draft: the specimen shows it live, the
    // Save bar appears (the draft no longer matches config.jsonc), and Save
    // writes it with the previous config kept as config.jsonc.bak. Nothing is
    // written until Save — a preset is an edit, not a commit.
    function loadPreset(name) {
        if (!ready || !installed || commitLock || saving) return;
        // A preset reply replaces the draft wholesale: edits made while the
        // request runs would be silently discarded, so the draft is locked
        // exactly like a save (commitLock clears in the reply/failure paths).
        commitLock = true;
        error = ""; errorKind = ""; message = "Loading preset " + name + "…";
        worker.send({action: "preset", name: name}, "preset");
    }
    function revert() {
        if (commitLock || saving) return;
        draft = JSON.parse(JSON.stringify(model)); error = ""; errorKind = ""; previewError = ""; message = "";
        previewGeneration++;  // specimens of the discarded draft are stale
        previewText = "";     // never show an old specimen beside "matches config.jsonc"
        requestPreview();
    }
    function save() {
        if (Config.testMode) { message = "Saving is refused while CEDAR runs under a test environment."; return; }
        if (!ready || !dirty) return;
        if (busy) { message = "Still working — try Save again in a moment."; return; }
        // A queued preview would run after the save and, on success, read as
        // if the save had succeeded. Nothing may follow a save but its own
        // reload; the preview restarts from the fresh model.
        previewTimer.stop(); sendDeferred.stop();
        commitLock = true;
        saving = true; error = ""; errorKind = ""; message = "Saving…";
        worker.send({action: "save", model: draft}, "save");
    }
    Timer {
        id: previewTimer; interval: 150
        onTriggered: root.requestPreview()
    }
    function requestPreviewNow() {
        if (!installed || !draft) return;
        previewBusy = true;
        worker.send({action: "preview", model: draft}, "preview:" + previewGeneration);
    }
    function requestPreview() {
        // The specimen shows the committed readout after a get (not dirty)
        // and the draft once editing starts. Either way fastfetch runs —
        // the panel is a specimen of what the terminal will print.
        if (!installed || !draft) return;
        previewBusy = true;
        sendDeferred.restart();  // never send from inside another request's result handler
    }
    Timer {
        id: sendDeferred; interval: 60
        onTriggered: {
            if (!root.installed || !root.draft) return;
            root.requestPreviewNow();
        }
    }
    ServiceRequest {
        id: worker; script: "scripts/fastfetch_settings.py"; timeoutMs: 45000
        onResult: result => {
            // Errors are cleared only by the reply that supersedes them: a
            // successful preview must never wash away a save failure.
            if (result.preset !== undefined) {  // a "preset" reply: the draft becomes the preset
                root.error = ""; root.errorKind = ""; root.message = "";
                root.previewError = "";  // the abandoned draft's specimen error is stale
                root.commitLock = false;
                root.catalog = result.catalog || root.catalog;
                root.presets = result.presets || root.presets;
                root.draft = result.model ? JSON.parse(JSON.stringify(result.model)) : null;
                // the in-flight specimen is of the old draft: invalidate, then
                // show the preset's own readout
                root.previewGeneration++;
                requestPreviewNow();
            } else if (result.model !== undefined || result.installed !== undefined) {  // a "get" reply
                root.error = ""; root.errorKind = "";
                root.commitLock = false;
                root.installed = result.installed === true;
                root.model = result.model;
                root.draft = result.model ? JSON.parse(JSON.stringify(result.model)) : null;
                root.ready = result.model !== null;
                root.configError = result.model === null;
                root.configErrorText = result.error || "";
                root.configPath = result.configPath || "";
                root.catalog = result.catalog || [];
                root.presets = result.presets || [];
                requestPreviewNow();
            } else if (result.preview !== undefined) {
                if (worker.tag !== "preview:" + root.previewGeneration) {
                    root.previewBusy = worker.queued !== null;
                    return;  // a specimen of a discarded draft: never displayed
                }
                root.previewText = result.preview;
                root.previewError = "";
                // a successful preview supersedes only a preview error; a save
                // failure stays on screen beside the fresh specimen
                if (root.errorKind === "preview") { root.error = ""; root.errorKind = ""; }
                root.previewBusy = worker.queued !== null;
            } else if (result.saved) {
                root.saving = false; root.error = ""; root.message = "Saved. The previous config is kept as config.jsonc.bak.";
                worker.send({action: "get"});  // reload the committed model; commitLock holds until it answers
            }
        }
        onFailed: value => {
            // reconcile the spinner against whatever is actually queued (the
            // queue is dropped before a failure is emitted, stale or not)
            root.previewBusy = worker.queued !== null;
            if (worker.tag && worker.tag.startsWith("preview:")) {
                if (worker.tag === "preview:" + root.previewGeneration) root.previewError = value;
                return;  // stale preview failure: suppress the text, not the cleanup
            }
            root.error = value;
            // a preset failure is a draft-replacing read, not a save: label it honestly
            root.errorKind = worker.tag === "save" ? "save" : worker.tag === "preset" ? "preset" : "get";
            root.saving = false; root.commitLock = false; root.message = "";
        }
    }
}
