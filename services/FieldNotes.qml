pragma Singleton
import QtQuick
import Quickshell
import ".."

// Field Notes: the shell's handle on the floating notebook. The board
// (modules/FieldNotesBoard.qml) owns the sheets, their history and the saved
// file; it attaches here when it loads so the bar, Settings, Go and the `notes`
// IPC target have one place to ask. A summon before the board exists is kept
// and applied the moment it attaches. Nothing here polls; locking the session
// puts the notes away.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Singleton {
    id: root
    property var board: null
    property var pendingSummon: null
    readonly property bool loaded: board !== null
    readonly property bool opened: board ? board.opened : false
    readonly property int sheets: board ? board.notebook.sheets.length : 0
    readonly property int sheet: board ? board.notebook.current + 1 : 0
    readonly property string saveStatus: board ? board.saveStatus : "UNLOADED"
    readonly property string lastExport: board ? board.lastExport : ""
    readonly property bool lastExportOk: board ? board.lastExportOk : false
    readonly property string screenName: board && board.targetScreen ? board.targetScreen.name : ""
    readonly property string stateDir: Config.stateDir + "/field-notes"
    readonly property string defaultExportDir: (Quickshell.env("XDG_PICTURES_DIR") || Config.home + "/Pictures") + "/field-notes"
    // "~" and relative paths are taken from the home folder.
    function expandHome(path) {
        const value = String(path || "").trim();
        if (value === "" ) return defaultExportDir;
        if (value === "~") return Config.home;
        if (value.indexOf("~/") === 0) return Config.home + value.slice(1);
        return value.charAt(0) === "/" ? value : Config.home + "/" + value;
    }
    readonly property string exportDir: expandHome(Config.saved.notesExportDir)
    readonly property var toolbarSides: ["right", "left", "top", "bottom"]
    readonly property string toolbarSide: toolbarSides.includes(Config.saved.notesToolbar) ? Config.saved.notesToolbar : "right"

    function attach(item) {
        board = item;
        if (pendingSummon) {
            const payload = pendingSummon;
            pendingSummon = null;
            item.open(JSON.stringify(payload));
        }
    }
    function detach(item) {
        if (board === item) board = null;
    }
    // payload: { screen, toggle, settings } as the board's open() reads it.
    function summon(payload) {
        if (ShellState.locked || Config.stage < 3) return false;
        const data = payload && typeof payload === "object" ? payload : {};
        if (board) board.open(JSON.stringify(data));
        else pendingSummon = data;
        return true;
    }
    function open() { return summon({}); }
    function openOn(screen) { return summon({ screen: screen }); }
    function toggle() { return summon({ toggle: true }); }
    function close() { if (board) board.close(); }
    function center() { if (board) board.centerBoard(true); }
    function openSettings() {
        if (ShellState.locked || Config.stage < 3) return;
        ShellState.settingsPage = "notes";
        ShellState.open("settings");
    }
    // Opens the export folder in the file manager, detached from the shell. The
    // folder is only ever an argument; gio reads desktop entries correctly where
    // xdg-open outside a full desktop can mangle a quoted Exec path.
    function openExportFolder() {
        if (ShellState.locked) return;
        Quickshell.execDetached(["sh", "-c", "mkdir -p -- \"$1\" || exit 1; command -v gio >/dev/null 2>&1 && exec gio open \"$1\"; exec xdg-open \"$1\"", "cedar-notes", exportDir]);
    }
    // The scripting surface behind the `notes` IPC target. Every method answers
    // "ok", a value, or "error: <reason>"; nothing but status runs while locked.
    function script(method, args) {
        if (method !== "status" && ShellState.locked) return "error: the session is locked";
        if (!board) return method === "status" ? JSON.stringify({ open: false, loaded: false }) : "error: Field Notes is not loaded";
        return board.script(method, args || []);
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.close(); } }
}
