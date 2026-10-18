// Contract tests for Field Notes inside CEDAR: the wiring that is easy to break
// silently. Each assertion's message says what it protects. The upstream plugin's
// contract tests covered its manifest and Omarchy theme; these cover CEDAR's
// tokens, manifests, IPC and settings instead.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "../..")
function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8")
}
function stripJsonc(text) {
  return text.replace(/^\s*\/\/.*$/gm, "")
}

const board = read("modules/FieldNotesBoard.qml")
const paper = read("components/NotesPaper.qml")
const tools = read("components/NotesToolIsland.qml")
const service = read("services/FieldNotes.qml")
const shell = read("shell.qml")
const schema = read("components/SettingsSchema.js")
const config = read("Config.qml")
const notesFiles = [
  "modules/FieldNotesBoard.qml", "modules/FieldNotesSettings.qml", "services/FieldNotes.qml",
  "components/NotesTheme.qml", "components/NotesTooltip.qml", "components/NotesToolButton.qml",
  "components/NotesToolIsland.qml", "components/NotesHeaderLabel.qml", "components/NotesTitleField.qml",
  "components/NotesTextNote.qml", "components/NotesBinderClip.qml", "components/NotesPaper.qml"
]

test("every Field Notes QML file exists, is registered, and carries only Theme tokens", () => {
  const components = read("components/qmldir")
  const modules = read("modules/qmldir")
  const services = read("services/qmldir")
  for (const file of notesFiles) {
    assert.equal(fs.existsSync(path.join(root, file)), true, `${file} must exist`)
    const text = read(file)
    assert.doesNotMatch(text, /#[0-9a-fA-F]{6}\b/, `${file} must take every colour from Theme, never a literal`)
    assert.doesNotMatch(text, /font\.family:\s*"/, `${file} must use Theme.labelFont or Theme.dataFont`)
    const name = path.basename(file, ".qml")
    const registry = file.startsWith("components/") ? components : file.startsWith("services/") ? services : modules
    assert.match(registry, new RegExp(`^(singleton )?${name} 1\\.0 ${name}\\.qml$`, "m"), `${name} must be registered in its qmldir`)
  }
  for (const module of ["DocumentModel", "Geometry", "History", "Notebook", "Layout"])
    assert.equal(fs.existsSync(path.join(root, "components/notes", module + ".js")), true, `${module}.js must ship`)
})

test("the paper tokens exist in Theme, the palette and the docs", () => {
  const theme = read("Theme.qml")
  const palette = JSON.parse(read("themes/palettes/cedar.json")).colors
  const doc = read("docs/PALETTE.md")
  for (const token of ["paper", "paperEdge", "paperUnder", "ink", "inkSelection", "rule", "ruleMajor", "marginRule"]) {
    assert.match(theme, new RegExp(`readonly property color ${token}: token\\("${token}", "#[0-9A-Fa-f]{6}"\\)`), `Theme.${token} must be an overridable token`)
    assert.match(palette[token], /^#[0-9A-Fa-f]{6}$/, `${token} must be in the shared palette`)
    assert.match(doc, new RegExp("`" + token + "`"), `${token} must be documented in PALETTE.md`)
  }
})

test("the board is a click-through layer surface that moves its scene, kept loaded by the shell", () => {
  assert.match(board, /PanelWindow\s*\{/)
  assert.doesNotMatch(board, /FloatingWindow\s*\{/, "the notes float over the desktop, they are not a toplevel")
  assert.match(board, /visible:\s*root\.opened\b/)
  assert.doesNotMatch(board, /visible:\s*root\.opened\s*&&/, "PanelWindow visibility must not depend on its backing screen")
  assert.match(board, /WlrLayershell\.namespace:\s*"cedar-notes"/, "the namespace must match the cedar-.* layer rule")
  assert.match(board, /WlrLayershell\.layer:\s*WlrLayer\.(Top|Overlay)/)
  assert.match(board, /exclusionMode:\s*ExclusionMode\.Ignore/)
  assert.match(board, /mask:\s*Region\s*\{/)
  assert.doesNotMatch(board, /startSystemMove\s*\(/, "layer surfaces move their scene, not a compositor window")
  assert.match(board, /FieldNotes\.attach\(root\)/, "the board must attach to the service so the shell can reach it")
  assert.match(board, /FieldNotes\.detach\(root\)/)
  assert.match(shell, /LazyLoader\s*\{\s*active:\s*Config\.stage >= 3\s*FieldNotesBoard\s*\{\}/, "shell.qml keeps one board loaded at stage 3")
})

test("the notes IPC target exposes the plugin's scripting surface through the service gate", () => {
  const target = /IpcHandler\s*\{\s*target:\s*"notes"[\s\S]*?\n    \}/.exec(shell)
  assert.ok(target, "shell.qml must declare the notes target")
  for (const method of ["status", "open", "openOn", "close", "toggle", "newSheet", "selectSheet", "setTitle", "setPaper", "setSize", "setTool", "setPenWidth", "clear", "center", "undo", "redo", "draw", "stopDrawing", "addNote", "copy"]) {
    assert.match(target[0], new RegExp(`function ${method}\\(`), `notes ${method} must exist`)
    assert.match(board, new RegExp(`case "${method}":`), `the board must answer ${method}`)
  }
  assert.match(target[0], /FieldNotes\.script\(/, "every method goes through FieldNotes.script, which refuses while locked")
  assert.match(service, /if \(method !== "status" && ShellState\.locked\) return "error: the session is locked"/)
  assert.match(read("docs/SECURITY.md"), /\| `notes` \|/, "SECURITY.md must list the target")
})

test("the bar, Applications, the keybind set and Settings each reach the notes once", () => {
  const bar = read("modules/StrataBarContents.qml")
  assert.match(bar, /objectName: "strataNotes"/)
  assert.match(bar, /Config\.moduleEnabled\("notes"\)/, "the bar module can be hidden like the others")
  assert.match(schema, /\{key:"notes",label:"Field Notes"\}/)
  assert.equal((bar.match(/FieldNotes\.summon\(/g) || []).length, 1, "one bar control opens the notes")
  const menu = JSON.parse(stripJsonc(read("menus/cedar-menu.jsonc")))
  assert.equal(menu["cedar.notes"].action, "cedar:notes")
  assert.match(read("scripts/desktop_runtime.py"), /'notes': \('notes', 'toggle'\)/)
  const keybinds = JSON.stringify(JSON.parse(read("data/keybinds.json")))
  assert.match(keybinds, /SUPER \+ ALT \+ N/)
  assert.match(keybinds, /notes toggle/)
  assert.match(read("docs/KEYBINDS.md"), /Super\+Alt\+N/)
  assert.match(schema, /\{id:"notes",label:"Field Notes"/, "the Settings page must be in the schema")
  assert.match(read("modules/SettingsPanel.qml"), /notes:notesPage/)
  assert.match(read("tests/qml/DesktopHarness.qml"), /"notes"/, "the desktop harness renders the page")
})

test("every preference is a schema descriptor with a Config default that is saved", () => {
  const keys = ["notesTilt", "notesToolbar", "notesFadeToolbar", "notesSmoothing", "notesEraser", "notesClipboard", "notesExportDir"]
  const saved = /const keys = \[([^\]]*)\]/.exec(config)[1]
  for (const key of keys) {
    assert.match(schema, new RegExp(`key:"${key}"`), `${key} must have a descriptor`)
    assert.match(config, new RegExp(`property \\w+ ${key}:`), `${key} must have a default in Config`)
    assert.match(saved, new RegExp(`"${key}"`), `${key} must be in savePreferences so it persists`)
  }
  assert.match(config, /ipcProtected: \[[^\]]*"notesExportDir"/, "the export folder decides where files are written; it stays with Settings")
  assert.match(board, /Config\.saved\.notesClipboard/)
  assert.match(board, /Config\.saved\.notesTilt/)
  assert.match(board, /Config\.saved\.notesSmoothing/)
  assert.match(board, /Config\.saved\.notesEraser/)
  assert.match(board, /Config\.saved\.notesFadeToolbar/)
  assert.match(board, /Config\.saved\.notesToolbar = side/, "dragging the toolbar writes the preference, so Settings and the grip agree")
  assert.match(service, /Config\.saved\.notesExportDir/)
  assert.doesNotMatch(board, /restored\.settings/, "the file's settings block is not read; Config owns preferences")
})

test("paper and toolbar keep the plugin's editing contract", () => {
  assert.match(paper, /signal commitRequested/)
  assert.match(paper, /function eraseAt\(x, y\)[\s\S]*?Geometry\.splitStroke[\s\S]*?DocumentModel\.replaceStrokeSegments/, "erase must cut a local gap and keep editable segments")
  assert.match(paper, /onPositionChanged:[\s\S]*?root\.currentTool === "eraser"[\s\S]*?root\.eraseAlong\(/, "dragging the eraser sweeps the whole path")
  assert.match(paper, /function finishGesture\([\s\S]*?commit\(draftDocument\)/, "an erase or move gesture lands as one undo step")
  assert.match(paper, /steadyStroke && mouseSmoothing > 0 \? Geometry\.smoothStroke/, "only mouse and touchpad strokes are smoothed")
  assert.match(board, /onCommitRequested: function\(nextDocument\) \{\s*root\.commitDocument\(nextDocument\)\s*\}/, "commits must not steal focus from an active editor")
  assert.match(board, /onEditingFinished: root\.focusKeys\(\)/)
  assert.match(board, /function fitsLimits\(/, "every edit is held to the load limits")
  for (const label of ["Select", "Pen", "Erase", "Text", "Undo", "Redo", "Close"])
    assert.match(tools, new RegExp(`text:\\s*"${label}"`))
  assert.match(tools, /ChamferFrame\s*\{/, "the island wears the pill's chamfer")
  assert.match(tools, /topLine: true/)
})

test("motion rests: every Behavior is gated and no loop runs on a mapped surface", () => {
  for (const file of notesFiles) {
    const text = read(file)
    const behaviors = text.match(/Behavior on \w+\s*\{[^}]*\}/g) || []
    for (const behavior of behaviors)
      assert.match(behavior, /enabled: !Theme\.reducedMotion/, `${file}: ${behavior.split("\n")[0]} must snap under Reduced Motion`)
    assert.doesNotMatch(text, /loops:\s*Animation\.Infinite/, `${file} must not loop an animation`)
    assert.doesNotMatch(text, /\w+Animator\s*\{/, `${file} must not run an Animator`)
  }
  assert.match(paper, /FrameAnimation\s*\{\s*running: root\.scriptStroke !== null && !root\.scriptCommitted/, "the script stroke's frame clock stops when the stroke commits")
})

test("the saved file is read safely, written atomically and never overwritten unread", () => {
  assert.match(board, /atomicWrites: true/)
  assert.match(board, /if \(!stateReady\)\s*return/, "nothing is saved before the file has been read")
  assert.match(board, /id: stateCheck[\s\S]*?\[ -L \\"\$1\\" \]/, "symlinks are refused before the file is opened")
  assert.match(board, /path: root\.stateChecked \? root\.stateDir \+ "\/notes\.json" : ""/, "the FileView opens the file only after the check")
  assert.match(board, /--no-dereference/, "backups never write through a symlink")
  assert.match(service, /stateDir: Config\.stateDir \+ "\/field-notes"/, "state lives under CEDAR's state directory")
  assert.match(read("data/plugins.json"), /"id": "cedar\.field-notes"/, "the bundle is declared")
  assert.match(read("docs/LICENSES.md"), /Field-Notes-MIT\.txt/, "the MIT attribution is recorded")
  assert.equal(fs.existsSync(path.join(root, "licenses/Field-Notes-MIT.txt")), true)
})
