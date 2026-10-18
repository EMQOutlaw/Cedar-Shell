import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../components"
import "../services"
import "../components/notes/DocumentModel.js" as DocumentModel
import "../components/notes/History.js" as History
import "../components/notes/Layout.js" as Layout
import "../components/notes/Notebook.js" as Notebook

// Field Notes: a sheet of paper that floats above the desktop on a click-through
// layer surface. The board owns the notebook (one undo history per sheet), the
// current tool and pen width, where the board was left on each display, and the
// saved file. Preferences live in Config (Settings › Field Notes); the shell
// reaches the board through the FieldNotes service, which the board attaches to.
//
// State on disk: ~/.local/state/cedar/field-notes/notes.json, written
// atomically about half a second after each change and when the notes close.
// Nothing is written until the existing file has been read, so a slow or failed
// load can never overwrite notes with an empty page.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Item {
    id: root

    property bool opened: false
    // Whether the board has a place on the screen it is shown on (else it is centred there).
    property bool positionInitialized: false
    // The screen the notes are shown on, chosen each time they open (see showOn).
    property var targetScreen: null
    // Where the board was left on each screen, by output name, in that screen's pixels.
    property var boardPositions: ({})
    // A position saved before boards were kept per screen, used once on the first screen opened.
    property var legacyBoard: null
    property string currentTool: "pen"
    property real penWidth: 2.5
    readonly property string toolbarSide: FieldNotes.toolbarSide
    // The toolbar has the same length in either orientation (see NotesToolIsland).
    readonly property var dockLayout: Layout.dock(toolbarSide, currentDocument.page.width, currentDocument.page.height,
        Math.max(tools.implicitWidth, tools.implicitHeight), Math.min(tools.implicitWidth, tools.implicitHeight))
    property var notebook: Notebook.create([History.create(DocumentModel.createSheet("medium"))], 0)
    readonly property var historyState: notebook.sheets[notebook.current]
    readonly property var currentDocument: historyState.present
    readonly property bool canUndo: historyState.past.length > 0
    readonly property bool canRedo: historyState.future.length > 0
    readonly property string stateDir: FieldNotes.stateDir
    // Nothing is written until the saved sheet has been read, so a slow or failed load
    // can never overwrite it with an empty page.
    property bool stateReady: false
    // The notes file is only opened once stateCheck has confirmed it is safe to read.
    property bool stateChecked: false
    readonly property int maxStateBytes: 16 * 1024 * 1024
    property string saveStatus: "LOADING"
    readonly property string exportDir: FieldNotes.exportDir
    readonly property var smoothingStrength: ({ off: 0, light: 2, medium: 3.5, strong: 5 })
    readonly property var eraserRadii: ({ small: 6, medium: 10, large: 16 })
    property string pendingExport: ""
    // What the export in progress puts on the clipboard: "path" or "image".
    property string pendingMode: "path"
    // The copy of the notes file made before saving over it: "", "copying", "done" or "failed".
    property string backupState: ""
    // The last export to finish, for Settings and the scripting interface.
    property string lastExport: ""
    property bool lastExportOk: false

    function focusKeys() {
        // Taking focus away from an open note editor also commits it.
        keySink.forceActiveFocus()
    }

    // Every notebook change goes through here. When the open sheet changes size
    // (switching sheets, resizing, undo), the paper stays centred where it was on screen.
    function setNotebook(next) {
        var before = currentDocument.page
        var centerX = board.x + (paper.x + paper.width / 2) * board.scale
        var centerY = board.y + (paper.y + paper.height / 2) * board.scale
        notebook = next
        var after = currentDocument.page
        if (after.width === before.width && after.height === before.height)
            return
        if (!positionInitialized) {
            centerBoard()
            return
        }
        board.x = Math.round(centerX - (paper.x + paper.width / 2) * board.scale)
        board.y = Math.round(centerY - (paper.y + paper.height / 2) * board.scale)
        clampBoard()
    }

    // Loading keeps only what fits its limits (DocumentModel.overLimits), so no change may
    // take the notebook past them: the excess would be lost on the next load and the save
    // after it. Erasing can add objects as well as points, by splitting strokes. A change
    // that leaves an already over-full notebook no worse is allowed.
    function fitsLimits(nextNotebook) {
        var present = function(sheet) { return sheet.present }
        var after = DocumentModel.overLimits(nextNotebook.sheets.map(present))
        return after === 0 || after <= DocumentModel.overLimits(notebook.sheets.map(present))
    }

    function refuseFull() {
        paper.discardUncommitted()
        paper.refuse("The notebook is full")
    }

    function commitDocument(nextDocument) {
        var next = Notebook.replaceCurrent(notebook, History.commit(historyState, nextDocument))
        if (!fitsLimits(next)) {
            refuseFull()
            return false
        }
        setNotebook(next)
        return true
    }

    // Commits an open note and drops any gesture or selection, whose object ids belong
    // to the sheet being left.
    function leaveSheet() {
        focusKeys()
        paper.cancelScriptStrokes()
        paper.cancelGesture()
        paper.clearSelection()
    }

    function selectSheet(index) {
        leaveSheet()
        setNotebook(Notebook.select(notebook, index))
    }

    function addSheet() {
        leaveSheet()
        // A new sheet starts with the size and paper of the sheet being left.
        setNotebook(Notebook.add(notebook, History.create(
            DocumentModel.createSheet(DocumentModel.sizeName(currentDocument), currentDocument.paper))))
    }

    function selectTool(tool) {
        focusKeys()
        currentTool = tool
    }

    // Undo and redo can bring back strokes too (undoing a Clear restores a whole sheet).
    function undo() {
        focusKeys()
        var next = Notebook.replaceCurrent(notebook, History.undo(historyState))
        if (fitsLimits(next))
            setNotebook(next)
        else
            refuseFull()
        return notebook === next
    }

    function redo() {
        focusKeys()
        var next = Notebook.replaceCurrent(notebook, History.redo(historyState))
        if (fitsLimits(next))
            setNotebook(next)
        else
            refuseFull()
        return notebook === next
    }

    function cyclePaper() {
        focusKeys()
        commitDocument(DocumentModel.setPaper(currentDocument, DocumentModel.nextPaper(currentDocument.paper)))
    }

    function cycleSize() {
        focusKeys()
        var size = DocumentModel.nextSize(currentDocument)
        if (size === DocumentModel.sizeName(currentDocument))
            paper.refuseSize("The ink doesn't fit a smaller size")
        else
            commitDocument(DocumentModel.setSize(currentDocument, size))
    }

    function renameSheet(title) {
        commitDocument(DocumentModel.setTitle(currentDocument, title))
    }

    // Saves the open sheet as a PNG and copies its path or the image itself, for pasting
    // into other tools: the "Ctrl+C copies" setting, or the other one when alternate is
    // true (Ctrl+Shift+C). Every export is a new file, so a path pasted earlier keeps
    // showing that version.
    function copyImagePath(alternate) {
        focusKeys()
        if (pendingExport !== "")
            return
        var preferred = Config.saved.notesClipboard === "image" ? "image" : "path"
        pendingMode = alternate ? (preferred === "image" ? "path" : "image") : preferred
        var name = DocumentModel.slug(currentDocument.title) || "sheet-" + paper.pad2(notebook.current + 1)
        pendingExport = exportDir + "/" + name + "-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".png"
        prepareExportDir.running = true
    }

    function finishExport(ok) {
        lastExport = pendingExport
        lastExportOk = ok
        pendingExport = ""
        tools.exportFinished(ok, pendingMode)
    }

    function clearDocument() {
        focusKeys()
        commitDocument(DocumentModel.clearDocument(currentDocument))
    }

    // Docks the toolbar to another side of the paper while keeping the paper where it is
    // on screen. The side is a preference (Settings › Field Notes), so Config owns it.
    function setToolbarSide(side) {
        if (side === toolbarSide || Layout.TOOLBAR_SIDES.indexOf(side) < 0)
            return
        var paperX = board.x + paper.x * board.scale
        var paperY = board.y + paper.y * board.scale
        Config.saved.notesToolbar = side
        board.x = paperX - paper.x * board.scale
        board.y = paperY - paper.y * board.scale
        positionInitialized = true
        clampBoard()
        scheduleSave()
    }
    // The preference changed in Settings: keep the paper where it is.
    onToolbarSideChanged: {
        if (!positionInitialized)
            return
        clampBoard()
    }

    function dragToolbar(sceneX, sceneY) {
        var point = board.mapFromItem(null, sceneX, sceneY)
        setToolbarSide(Layout.nearestSide(point.x, point.y, paper, toolbarSide))
    }

    function openSettings() {
        focusKeys()
        paper.cancelGesture()
        FieldNotes.openSettings()
    }

    function setPenWidth(width) {
        penWidth = Math.max(1, Math.min(12, width))
    }

    function scheduleSave() {
        if (!stateReady)
            return
        saveStatus = "EDITED"
        saveTimer.restart()
    }

    // The preferences block written beside the sheets keeps the file readable by the
    // original plugin; CEDAR itself reads these from Config.
    function fileSettings() {
        return DocumentModel.sanitizeSettings({
            theme: true,
            tilt: Config.saved.notesTilt === true,
            fadeToolbar: Config.saved.notesFadeToolbar === true,
            smoothing: Config.saved.notesSmoothing,
            eraser: Config.saved.notesEraser,
            clipboard: Config.saved.notesClipboard,
            exportDir: Config.saved.notesExportDir
        })
    }

    function saveNow() {
        saveTimer.stop()
        if (!stateReady)
            return
        // The file must be safely copied before anything is saved over it. Wait while the copy
        // runs; if it failed, keep the file exactly as it is.
        if (backupState === "copying") {
            saveTimer.restart()
            return
        }
        if (backupState === "failed") {
            saveStatus = "NOT SAVED"
            return
        }
        var documents = notebook.sheets.map(function(sheet) {
            return sheet.present
        })
        rememberBoard()
        stateFile.setText(DocumentModel.serialize(documents, notebook.current, {
            tool: currentTool,
            penWidth: penWidth,
            toolbar: toolbarSide,
            // boardX/boardY keep the open screen's place readable by older versions.
            boardX: positionInitialized ? Math.round(board.x) : null,
            boardY: positionInitialized ? Math.round(board.y) : null,
            boards: boardPositions
        }, fileSettings()))
    }

    // Copies the notes file aside (backupCorrupt or backupTrimmed) before anything is saved over
    // it. Saving waits for the copy and only goes ahead once cp has succeeded (see saveNow).
    function startBackup(process) {
        backupState = "copying"
        backupWatchdog.restart()
        process.running = true
    }

    function finishBackup(exitCode, name) {
        if (backupState !== "copying")
            return
        backupWatchdog.stop()
        backupState = exitCode === 0 ? "done" : "failed"
        if (backupState === "failed") {
            console.warn("Field Notes: could not copy " + stateFile.path + " to " + name + "; it will not be saved over")
            saveStatus = "NOT SAVED"
        }
    }

    function flushSave() {
        if (saveTimer.running)
            saveNow()
    }

    function restoreState(text) {
        if (stateReady)
            return
        var raw = null
        try {
            raw = JSON.parse(text)
        } catch (error) {
            raw = null
        }
        var restored = DocumentModel.sanitizeNotebook(raw, 760, 560)
        if (restored) {
            notebook = Notebook.create(restored.documents.map(function(document) {
                return History.create(document)
            }), restored.current)
            currentTool = restored.ui.tool
            penWidth = restored.ui.penWidth
            // The file's own preferences are not read: Settings › Field Notes owns them.
            // Places are applied per screen as the notes open there (showOn).
            boardPositions = restored.ui.boards || {}
            if (!restored.ui.boards && restored.ui.boardX !== undefined)
                legacyBoard = { x: restored.ui.boardX, y: restored.ui.boardY }
            if (targetScreen && boardPositions[targetScreen.name]) {
                board.x = boardPositions[targetScreen.name].x
                board.y = boardPositions[targetScreen.name].y
                positionInitialized = true
                clampBoard()
            }
            if (restored.trimmed) {
                // The file held more than loading keeps (written by an older version, or by
                // hand): keep the whole of it before the next save replaces it.
                console.warn("Field Notes: " + stateFile.path + " holds more than a notebook can keep; the full file is saved as notes.json.trimmed")
                startBackup(backupTrimmed)
                saveStatus = "RECOVERED"
            } else {
                saveStatus = "SAVED"
            }
        } else if (String(text).trim() !== "") {
            // Keep a copy of the unreadable file before the next save replaces it.
            startBackup(backupCorrupt)
            saveStatus = "RECOVERED"
        } else {
            saveStatus = "READY"
        }
        stateReady = true
    }

    function clampBoard() {
        if (!surface || !board || surface.width <= 0 || surface.height <= 0)
            return
        var edge = Layout.margin(surface.width, surface.height)
        board.x = Layout.clampPosition(board.x, surface.width, board.width, board.scale, edge)
        board.y = Layout.clampPosition(board.y, surface.height, board.height, board.scale, edge)
    }

    // Until the user places the board, it stays centered as the surface settles its size.
    function centerBoard(remember) {
        if (!surface || !board || surface.width <= 0 || surface.height <= 0)
            return
        board.x = Math.round((surface.width - board.width * board.scale) / 2)
        board.y = Math.round((surface.height - board.height * board.scale) / 2)
        if (remember) {
            positionInitialized = true
            scheduleSave()
        }
    }

    function ensureBoardPosition() {
        if (!positionInitialized)
            centerBoard()
        else
            clampBoard()
    }

    function nudgeBoard(dx, dy) {
        board.x += dx
        board.y += dy
        positionInitialized = true
        clampBoard()
        scheduleSave()
    }

    function screenNamed(name) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === name)
                return Quickshell.screens[i]
        }
        return null
    }

    // The monitor Hyprland has focused: where a keyboard-summoned board belongs.
    function focusedScreen() {
        var monitor = Hyprland.focusedMonitor
        return screenNamed(monitor ? String(monitor.name || "") : "")
            || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    }

    function rememberBoard() {
        if (!targetScreen || !positionInitialized || !DocumentModel.isScreenName(targetScreen.name))
            return
        var next = Object.assign({}, boardPositions)
        next[targetScreen.name] = { x: Math.round(board.x), y: Math.round(board.y) }
        boardPositions = next
    }

    // Shows the notes on screen, with the board where it was last left there (or centred).
    function showOn(screen) {
        if (!screen || screen === targetScreen)
            return
        rememberBoard()
        targetScreen = screen
        var saved = boardPositions[screen.name] || legacyBoard
        legacyBoard = null
        if (saved) {
            board.x = saved.x
            board.y = saved.y
        }
        positionInitialized = !!saved
        Qt.callLater(ensureBoardPosition)
    }

    // payloadJson may hold "screen" (an output name: the bar button passes the display it
    // sits on; otherwise the focused display is used), "settings": true to open Settings ›
    // Field Notes as well, and "toggle": true to put the notes away if they are already open
    // on that screen. A summon while open applies the payload, moving the notes if it names
    // another screen.
    function open(payloadJson) {
        if (ShellState.locked)
            return
        var payload = {}
        try {
            payload = JSON.parse(payloadJson || "{}") || {}
        } catch (error) {
            payload = {}
        }
        var screen = (DocumentModel.isScreenName(payload.screen) ? screenNamed(payload.screen) : null) || focusedScreen()
        if (opened && payload.toggle === true && screen === targetScreen) {
            Qt.callLater(close)
            return
        }
        showOn(screen)
        opened = true
        Qt.callLater(function() {
            root.ensureBoardPosition()
            if (payload.settings === true)
                root.openSettings()
            else
                root.focusKeys()
        })
    }

    function close() {
        focusKeys()
        opened = false
        flushSave()
    }

    // The open sheet and its place on screen, for scripts (`notes status`).
    function scriptStatus() {
        var corners = [[0, 0], [paper.width, 0], [paper.width, paper.height], [0, paper.height]].map(function(point) {
            var mapped = paper.mapToItem(null, point[0], point[1])
            return [Math.round(mapped.x * 10) / 10, Math.round(mapped.y * 10) / 10]
        })
        return {
            open: opened,
            loaded: true,
            screen: targetScreen ? targetScreen.name : "",
            screens: Quickshell.screens.map(function(screen) { return screen.name }),
            sheet: notebook.current + 1,
            sheets: notebook.sheets.length,
            title: currentDocument.title,
            paper: currentDocument.paper,
            size: DocumentModel.sizeName(currentDocument),
            page: { width: currentDocument.page.width, height: currentDocument.page.height },
            objects: currentDocument.objects.length,
            tool: currentTool,
            penWidth: penWidth,
            toolbar: toolbarSide,
            // Script strokes still to be drawn, including the one being drawn.
            drawing: paper.scriptPending,
            saved: saveStatus,
            lastExport: lastExport,
            lastExportOk: lastExportOk,
            // The sheet's corners in the screen's pixels, clockwise from top-left, after the
            // board's scale and the paper's tilt: sheet point (x, y) lands at
            // corners[0] + (corners[1] - corners[0]) * x / page.width + (corners[3] - corners[0]) * y / page.height.
            corners: opened ? corners : null
        }
    }

    function scriptSetSize(size) {
        if (!DocumentModel.SIZES[size])
            return "error: size is small, medium or large"
        if (size === DocumentModel.sizeName(currentDocument))
            return "ok"
        if (!DocumentModel.fitsSize(currentDocument, size))
            return "error: the ink doesn't fit a " + size + " sheet"
        focusKeys()
        commitDocument(DocumentModel.setSize(currentDocument, size))
        return "ok"
    }

    // pointsText is "x y x y ..." in sheet coordinates (commas between numbers are fine; a
    // bracketed list is not, because the qs command line splits "[a,b]" into arguments).
    // The stroke is drawn live over durationMs with the current pen width, after any strokes
    // still being drawn; with the notes put away it is added at once.
    function scriptDraw(pointsText, durationMs) {
        var numbers = String(pointsText).trim().split(/[\s,;]+/).map(Number)
        if (numbers.length % 2 !== 0 || numbers.some(function(value) { return !isFinite(value) }))
            return "error: points are numbers in x y pairs, like \"10 20 30 40\""
        if (numbers.length < 4)
            return "error: a stroke needs at least two points"
        if (numbers.length > 2 * 8192)
            return "error: a stroke has at most 8192 points"
        var points = []
        for (var i = 0; i < numbers.length; i += 2)
            points.push([numbers[i], numbers[i + 1]])
        var present = notebook.sheets.map(function(sheet) { return sheet.present })
        if (DocumentModel.totalPoints(present) + points.length > DocumentModel.MAX_TOTAL_POINTS)
            return "error: the notebook is full"
        if (currentDocument.objects.length >= DocumentModel.MAX_OBJECTS)
            return "error: the sheet is full"
        paper.drawScriptStroke(points, penWidth, opened ? Math.max(0, Math.min(60000, Number(durationMs) || 0)) : 0)
        return "ok"
    }

    // A typed note with its top-left at (x, y) in sheet coordinates; "\n" starts a new line.
    function scriptNote(x, y, text) {
        var clean = String(text || "").replace(/\\n/g, "\n")
        if (clean.trim() === "")
            return "error: a note needs some text"
        var next = DocumentModel.addText(currentDocument, x, y, clean)
        if (next === currentDocument)
            return "error: the sheet is full"
        var added = next.objects[next.objects.length - 1]
        commitDocument(DocumentModel.updateText(next, added.id, clean, clean.split("\n").length * 21 + 8))
        return "ok"
    }

    // mode is "path", "image", or "" for whatever Ctrl+C copies. Returns the PNG's path;
    // status() reports lastExport and lastExportOk once it is written and copied.
    function scriptCopy(mode) {
        if (mode !== "" && mode !== "path" && mode !== "image")
            return "error: mode is path, image or empty"
        if (pendingExport !== "")
            return "error: an export is already running"
        var preferred = Config.saved.notesClipboard === "image" ? "image" : "path"
        copyImagePath(mode !== "" && mode !== preferred)
        return pendingExport
    }

    // The scripting interface behind the `notes` IPC target (shell.qml), reached through
    // FieldNotes.script(). Actions answer "ok" or "error: <reason>"; sheets are numbered
    // from 1 as on the paper.
    function script(method, args) {
        switch (method) {
        case "status": return JSON.stringify(scriptStatus())
        case "open": return FieldNotes.summon({}) ? "ok" : "error: the shell did not open the notes"
        case "openOn":
            if (!DocumentModel.isScreenName(args[0]) || !screenNamed(args[0]))
                return "error: no screen named " + String(args[0]).slice(0, 128)
            return FieldNotes.summon({ screen: args[0] }) ? "ok" : "error: the shell did not open the notes"
        case "close":
            if (opened)
                close()
            return "ok"
        case "toggle": return opened ? script("close", []) : script("open", [])
        case "newSheet":
            if (notebook.sheets.length >= DocumentModel.MAX_SHEETS)
                return "error: the notebook is full"
            addSheet()
            return "ok"
        case "selectSheet": {
            var number = Number(args[0])
            if (!isFinite(number) || number < 1 || number > notebook.sheets.length)
                return "error: there is no sheet " + String(args[0]).slice(0, 32)
            selectSheet(number - 1)
            return "ok"
        }
        case "setTitle":
            renameSheet(args[0])
            return "ok"
        case "setPaper":
            if (DocumentModel.PAPERS.indexOf(args[0]) < 0)
                return "error: paper is graph, dots, ruled or plain"
            focusKeys()
            commitDocument(DocumentModel.setPaper(currentDocument, args[0]))
            return "ok"
        case "setSize": return scriptSetSize(args[0])
        case "setTool":
            if (DocumentModel.TOOLS.indexOf(args[0]) < 0)
                return "error: tool is select, pen, eraser or text"
            selectTool(args[0])
            return "ok"
        case "setPenWidth":
            if (!isFinite(Number(args[0])))
                return "error: width is a number from 1 to 12"
            setPenWidth(Number(args[0]))
            return "ok"
        case "clear":
            clearDocument()
            return "ok"
        case "center":
            centerBoard(true)
            return "ok"
        case "undo":
            if (!canUndo)
                return "error: nothing to undo"
            return undo() ? "ok" : "error: the notebook is full"
        case "redo":
            if (!canRedo)
                return "error: nothing to redo"
            return redo() ? "ok" : "error: the notebook is full"
        case "draw": return scriptDraw(args[0], args[1])
        case "stopDrawing":
            paper.cancelScriptStrokes()
            return "ok"
        case "addNote": return scriptNote(Number(args[0]), Number(args[1]), args[2])
        case "copy": return scriptCopy(String(args[0] === undefined || args[0] === null ? "" : args[0]))
        }
        return "error: unknown method"
    }

    onNotebookChanged: scheduleSave()
    onCurrentToolChanged: scheduleSave()
    onPenWidthChanged: scheduleSave()
    Component.onCompleted: {
        FieldNotes.attach(root)
        prepareStateDir.running = true
    }
    Component.onDestruction: {
        flushSave()
        FieldNotes.detach(root)
    }

    NotesTheme {
        id: notesTheme
    }

    // A monitor unplugged under the notes: show them on the focused one instead. Wait a turn so
    // the removed output finishes closing its surface before another is mapped.
    Connections {
        target: Quickshell

        function onScreensChanged() {
            if (!root.targetScreen || Quickshell.screens.indexOf(root.targetScreen) >= 0)
                return
            root.targetScreen = null
            root.positionInitialized = false
            Qt.callLater(function() {
                if (root.opened && !root.targetScreen)
                    root.showOn(root.focusedScreen())
            })
        }
    }

    // One-shot: the file is written half a second after the last change.
    Timer {
        id: saveTimer

        interval: 500
        onTriggered: root.saveNow()
    }

    Process {
        id: prepareStateDir

        command: ["mkdir", "-p", "-m", "700", root.stateDir]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                stateCheck.running = true
            } else {
                console.warn("Field Notes: cannot create " + root.stateDir + "; notes will not be saved")
                root.saveStatus = "NOT SAVED"
            }
        }
    }

    // Reads of the notes file fail closed: only a regular file (not a symlink, pipe or
    // folder) of at most maxStateBytes is opened. Otherwise nothing is read and nothing is
    // ever written over it. Exit codes: 0 safe, 3 missing (start fresh), 4 not a regular
    // file, 5 unreadable, 6 too large.
    Process {
        id: stateCheck

        command: ["sh", "-c",
            "if [ -L \"$1\" ]; then exit 4; fi; [ -e \"$1\" ] || exit 3; [ -f \"$1\" ] || exit 4; size=$(stat -c %s -- \"$1\") || exit 5; [ \"$size\" -le \"$2\" ] || exit 6",
            "cedar-notes", root.stateDir + "/notes.json", String(root.maxStateBytes)]
        onExited: function(exitCode) {
            if (exitCode === 0 || exitCode === 3) {
                root.stateChecked = true
                return
            }
            var reasons = { 4: "is not a regular file", 5: "cannot be read", 6: "is larger than 16 MiB" }
            console.warn("Field Notes: " + root.stateDir + "/notes.json " + (reasons[exitCode] || "failed its safety check")
                + "; it was not opened and notes will not be saved over it")
            root.saveStatus = "NOT SAVED"
        }
    }

    Process {
        id: prepareExportDir

        command: ["mkdir", "-p", "--", root.exportDir]
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.finishExport(false)
                return
            }
            paper.exportImage(root.pendingExport, function(ok) {
                if (!ok) {
                    root.finishExport(false)
                    return
                }
                copyPath.command = root.pendingMode === "image"
                    ? ["sh", "-c", "exec wl-copy --type image/png < \"$1\"", "cedar-notes", root.pendingExport]
                    : ["wl-copy", root.pendingExport]
                copyPath.running = true
            })
        }
    }

    Process {
        id: copyPath

        onExited: function(exitCode) {
            root.finishExport(exitCode === 0)
        }
    }

    Process {
        id: backupCorrupt

        // Never follows symlinks: replaces any existing backup rather than writing through it.
        command: ["cp", "--no-dereference", "--remove-destination", "--", stateFile.path, stateFile.path + ".corrupt"]
        onExited: function(exitCode) {
            root.finishBackup(exitCode, "notes.json.corrupt")
        }
    }

    Process {
        id: backupTrimmed

        // The same rules as backupCorrupt, for a file that loading had to trim.
        command: ["cp", "--no-dereference", "--remove-destination", "--", stateFile.path, stateFile.path + ".trimmed"]
        onExited: function(exitCode) {
            root.finishBackup(exitCode, "notes.json.trimmed")
        }
    }

    // A copy that never reports back (cp could not start) counts as failed, not as done. One-shot.
    Timer {
        id: backupWatchdog

        interval: 10000
        onTriggered: root.finishBackup(-1, "a backup")
    }

    FileView {
        id: stateFile

        path: root.stateChecked ? root.stateDir + "/notes.json" : ""
        atomicWrites: true
        blockWrites: true
        printErrors: false

        onLoaded: root.restoreState(text())
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) {
                root.saveStatus = "READY"
                root.stateReady = true
            } else {
                root.saveStatus = "NOT SAVED"
            }
        }
        onSaved: {
            if (!saveTimer.running)
                root.saveStatus = "SAVED"
        }
        onSaveFailed: function(error) {
            root.saveStatus = "NOT SAVED"
        }
    }

    PanelWindow {
        id: surface

        screen: root.targetScreen
        visible: root.opened
        color: Theme.transparent
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "cedar-notes"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the paper, the toolbar and the clip take input; everything else is click-through.
        mask: Region {
            Region {
                x: board.x + (paper.x - 24) * board.scale
                y: board.y + (paper.y - 28) * board.scale
                width: (paper.width + 48) * board.scale
                height: (paper.height + 56) * board.scale
            }
            Region {
                x: board.x + (tools.x - 18) * board.scale
                y: board.y + (tools.y - 18) * board.scale
                width: (tools.width + 36) * board.scale
                height: (tools.height + 36) * board.scale
            }
            Region {
                x: board.x + dragClip.x * board.scale
                y: board.y + dragClip.y * board.scale
                width: dragClip.width * board.scale
                height: dragClip.height * board.scale
            }
        }

        onWidthChanged: root.ensureBoardPosition()
        onHeightChanged: root.ensureBoardPosition()

        FocusScope {
            id: keyboardRoot

            anchors.fill: parent
            focus: true

            // Plain focus target: unlike the FocusScope itself, focusing it pulls active
            // focus out of a note editor. Unhandled keys bubble up to keyboardRoot.
            Item {
                id: keySink

                focus: true
            }

            Keys.onPressed: function(event) {
                var control = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (control && event.key === Qt.Key_Comma) {
                    root.openSettings()
                    event.accepted = true
                    return
                }
                if (control && event.key === Qt.Key_Z && shift) {
                    root.redo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_Z) {
                    root.undo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_C) {
                    root.copyImagePath(shift)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_F2) {
                    paper.editTitle()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_Y) {
                    root.redo()
                    event.accepted = true
                    return
                } else if (!control && (event.key === Qt.Key_P || event.key === Qt.Key_B)) {
                    root.selectTool("pen")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_E) {
                    root.selectTool("eraser")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_T) {
                    root.selectTool("text")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_V) {
                    root.selectTool("select")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_G) {
                    root.cyclePaper()
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_S) {
                    root.cycleSize()
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_N) {
                    root.addSheet()
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_PageUp) {
                    root.selectSheet(root.notebook.current - 1)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_PageDown) {
                    root.selectSheet(root.notebook.current + 1)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketLeft) {
                    root.setPenWidth(root.penWidth - 0.5)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketRight) {
                    root.setPenWidth(root.penWidth + 0.5)
                    event.accepted = true
                    return
                }
                var step = shift ? 32 : 8
                if (event.key === Qt.Key_Left) {
                    root.nudgeBoard(-step, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.nudgeBoard(step, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.nudgeBoard(0, -step)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.nudgeBoard(0, step)
                    event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                    root.centerBoard(true)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    event.accepted = paper.deleteSelected()
                } else if (event.key === Qt.Key_Escape) {
                    if (!paper.cancelEditing() && !paper.clearSelection())
                        root.close()
                    event.accepted = true
                }
            }

            Item {
                id: board

                width: root.dockLayout.width
                height: root.dockLayout.height
                // Shrinks the whole board on small displays; stored geometry stays in paper space.
                scale: Layout.fitScale(surface.width, surface.height, width, height)
                transformOrigin: Item.TopLeft
                onScaleChanged: Qt.callLater(root.ensureBoardPosition)

                NotesPaper {
                    id: paper

                    x: root.dockLayout.paperX
                    y: root.dockLayout.paperY
                    width: root.currentDocument.page.width
                    height: root.currentDocument.page.height
                    theme: notesTheme
                    document: root.currentDocument
                    currentTool: root.currentTool
                    penWidth: root.penWidth
                    statusText: root.saveStatus
                    tilted: Config.saved.notesTilt === true
                    mouseSmoothing: root.smoothingStrength[Config.saved.notesSmoothing] ?? 3.5
                    eraserRadius: root.eraserRadii[Config.saved.notesEraser] ?? 10
                    sheetIndex: root.notebook.current
                    sheetCount: root.notebook.sheets.length
                    onCommitRequested: function(nextDocument) {
                        root.commitDocument(nextDocument)
                    }
                    onEditingFinished: root.focusKeys()
                    onPaperRequested: root.cyclePaper()
                    onSizeRequested: root.cycleSize()
                    onTitleCommitted: function(title) {
                        root.renameSheet(title)
                    }
                    onToolRequested: function(tool) {
                        root.selectTool(tool)
                    }
                }

                NotesToolIsland {
                    id: tools

                    x: root.dockLayout.toolX
                    y: root.dockLayout.toolY
                    // Topmost on the board, so its tooltips draw over the paper and the clip.
                    z: 30
                    width: implicitWidth
                    height: implicitHeight
                    side: root.toolbarSide
                    theme: notesTheme
                    sheetIndex: root.notebook.current
                    sheetCount: root.notebook.sheets.length
                    canAddSheet: Notebook.canAdd(root.notebook)
                    currentTool: root.currentTool
                    canUndo: root.canUndo
                    canRedo: root.canRedo
                    hasContent: root.currentDocument.objects.length > 0
                    penWidth: root.penWidth
                    onToolSelected: function(tool) {
                        root.selectTool(tool)
                    }
                    onUndoRequested: root.undo()
                    onRedoRequested: root.redo()
                    onClearRequested: root.clearDocument()
                    onPenWidthRequested: function(width) {
                        root.setPenWidth(width)
                    }
                    onSheetRequested: function(index) {
                        root.selectSheet(index)
                    }
                    onNewSheetRequested: root.addSheet()
                    onCopyImageRequested: root.copyImagePath()
                    onSettingsRequested: root.openSettings()
                    copyMode: Config.saved.notesClipboard === "image" ? "image" : "path"
                    // The notes' surface holds keyboard focus while you work in them.
                    faded: Config.saved.notesFadeToolbar === true && !Window.active
                    onCloseRequested: root.close()
                    onGripMoved: function(sceneX, sceneY) {
                        root.dragToolbar(sceneX, sceneY)
                    }
                    onGripReleased: root.focusKeys()
                }

                Item {
                    id: dragClip

                    // Centred on the paper's top edge, following its tilt.
                    x: paper.x + Math.round((paper.width - width) / 2 + paper.height / 2 * Math.sin(paper.rotation * Math.PI / 180))
                    y: paper.y - 26
                    width: 140
                    height: 50
                    z: 20

                    Accessible.role: Accessible.Grip
                    Accessible.name: "Move the board (arrow keys nudge it, Home centres it)"

                    NotesBinderClip {
                        x: Math.round((parent.width - width) / 2)
                        width: implicitWidth
                        height: implicitHeight
                        theme: notesTheme
                        tilt: paper.rotation
                        hovered: clipHover.hovered
                        lifted: clipDrag.active
                    }

                    NotesTooltip {
                        theme: notesTheme
                        text: "Drag to move"
                        shortcut: "Arrows"
                        side: "bottom"
                        hovered: clipHover.hovered && !clipDrag.active
                    }

                    HoverHandler {
                        id: clipHover

                        cursorShape: clipDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    }
                    TapHandler {
                        onTapped: root.focusKeys()
                    }
                    DragHandler {
                        id: clipDrag

                        target: board
                        acceptedButtons: Qt.LeftButton
                        xAxis.minimum: Layout.margin(surface.width, surface.height)
                        xAxis.maximum: Math.max(xAxis.minimum, surface.width - board.width * board.scale - xAxis.minimum)
                        yAxis.minimum: Layout.margin(surface.width, surface.height)
                        yAxis.maximum: Math.max(yAxis.minimum, surface.height - board.height * board.scale - yAxis.minimum)
                        onActiveChanged: {
                            if (!active) {
                                root.positionInitialized = true
                                root.clampBoard()
                                root.focusKeys()
                                root.scheduleSave()
                            }
                        }
                    }
                }
            }
        }
    }
}
