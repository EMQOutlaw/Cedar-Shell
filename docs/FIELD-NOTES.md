# Field Notes

A sheet of paper that floats above the desktop. Sketch with the mouse or a pen
tablet, type notes, keep several sheets, and copy any sheet as an image with one
key, ready to paste into a chat, an issue or an agent. Everything around the
paper is click-through, so the desktop keeps working underneath.

Field Notes is carried into CEDAR from OldJobobo's Field Notes plugin for the
Omarchy shell (MIT; `licenses/Field-Notes-MIT.txt`). The JavaScript model is
unchanged; the surface was rewritten in CEDAR's tokens and wired to CEDAR's
service, Settings, bar and IPC conventions.

## Opening

- The Field Notes button on the bar's right rail (hide it under Settings › Top
  Bar › Bar modules). Left click toggles the notes on that display; right click
  opens Settings › Field Notes without closing them.
- `Super+Alt+N` (the managed keybind set), Applications › CEDAR › Field Notes,
  or `qs -c cedar ipc call notes toggle`.
- The notes open on the display you are using: the bar you clicked, or the
  focused monitor for a keybind. Clicking the button on another display's bar
  brings open notes over. An unplugged monitor sends them to the focused one.

`Esc` puts them away. Locking the session puts them away too.

## On the paper

The pen is ready as soon as the paper opens. Everything printed in the header is
also a control: click the title (or `F2`) to name the sheet; click the paper
label (or `G`) to cycle GRAPH 16 → DOTS 16 → RULED 24 → PLAIN; click the size
label (or `S`) to cycle SMALL → MEDIUM → LARGE. A sheet never shrinks below what
is drawn on it; the label says when no smaller size fits. The footer shows the
save status once the latest change is on disk.

| Control | Key | What it does |
|---|---|---|
| Select | `V` | Pick up a stroke or note to move it; `Delete` removes it; double-click a note to edit |
| Pen | `P` or `B` | Draw. Mouse and touchpad strokes are steadied; tablets stay exact |
| Erase | `E` | Cuts strokes at the ring's edge, removes notes it touches; one drag is one undo step |
| Text | `T` | Click the paper and type. `Enter` new line, `Ctrl+Enter` or click away finishes, `Esc` cancels |
| Undo / Redo | `Ctrl+Z` / `Ctrl+Y` | Per sheet, until the shell restarts |
| ‹ n/m › | `PgUp` / `PgDn`, `N` | Previous and next sheet; on the last sheet › becomes + for a new one |
| Width | `[` `]` | Four pen widths; the keys step finer |
| Copy | `Ctrl+C`, `Ctrl+Shift+C` | Save the sheet as a PNG and copy its path, or the image (Settings swaps them) |
| Clear | | Clear the sheet; click twice to confirm; undoable |
| Settings | `Ctrl+,` | Settings › Field Notes |
| Close | `Esc` | Put the notes away |

Move the board by its binder clip, or with the arrow keys (`Shift` for bigger
steps); `Home` centres it. Drag the toolbar's grip toward any side of the paper
to dock it there. On small displays the whole board scales down to fit. A blank
sheet is dropped when you leave it, so empty pages never pile up.

## Settings › Field Notes

Tilted paper, toolbar side, fade toolbar, mouse smoothing, eraser size, what
`Ctrl+C` copies, and the export folder (empty uses `~/Pictures/field-notes`).
These are ordinary CEDAR preferences in `settings.json` (`notes*` keys); the
export folder is `ipcProtected`. The page also shows the notebook's state and
offers Open, Center the board and Open export folder.

## Files

- `~/.local/state/cedar/field-notes/notes.json` (`XDG_STATE_HOME` respected):
  the sheets, the open sheet, the tool, pen width and where the board sits on
  each display. Written atomically about half a second after each change and
  when the notes close; nothing is written until the existing file has been
  read. The file is treated as untrusted on load (`DocumentModel.sanitizeNotebook`):
  unknown values fall back, coordinates are clamped, IDs are made unique, and
  limits apply (32 sheets, 4096 objects per sheet, 8192 points per stroke,
  250 000 points in total, 4096 characters per note, 60 per title). An
  unreadable file is copied to `notes.json.corrupt`, an over-full one to
  `notes.json.trimmed`, before anything is saved over it; if that copy fails the
  file is left alone and the status reads NOT SAVED. Reads fail closed: a
  symlink, pipe, folder or file over 16 MiB is never opened.
- `~/Pictures/field-notes/<title>-<timestamp>.png`: every copy is a new file.
- The format is the plugin's version 2 notebook, so a file moves between the
  Omarchy plugin and CEDAR either way. The `settings` block is written for that
  compatibility but CEDAR reads preferences from Config only.

## Scripting

`qs -c cedar ipc call notes <method> …` (or `cedar ipc notes …`). Actions
answer `ok` or `error: <reason>`; sheets are numbered from 1 as on the paper.
Everything but `status` is refused while the session is locked.

| Method | What it does |
|---|---|
| `status` | The open sheet as JSON: number, title, paper, size, tool, save status, last export, the display it is on (`screen`, all of them in `screens`), and the sheet's corners on screen |
| `open` / `close` / `toggle` | Show or put away the notes on the focused display |
| `openOn <output>` | Show the notes on a display by name, such as `DP-1` |
| `newSheet` / `selectSheet <n>` | Add a sheet after the last, or open sheet n |
| `setTitle <text>` / `setPaper <graph\|dots\|ruled\|plain>` / `setSize <small\|medium\|large>` | Change the open sheet |
| `setTool <select\|pen\|eraser\|text>` / `setPenWidth <1–12>` | Pick a tool and pen width |
| `draw "<x y x y …>" <ms>` | Draw a stroke live over ms milliseconds, exactly as given, in sheet coordinates; strokes queue |
| `stopDrawing` | Drop the strokes still waiting |
| `addNote <x> <y> <text>` | Add a typed note; `\n` starts a new line |
| `undo` / `redo` / `clear` / `center` | As the toolbar |
| `copy <path\|image\|"">` | Save the sheet as a PNG and copy its path or the image; `""` copies what `Ctrl+C` does. Prints the PNG's path |

Sheet coordinates run from the paper's top-left: small 520×380, medium 760×560,
large 1040×760. `status` gives the paper's corners in screen pixels, clockwise
from top-left, so a script can turn a point on screen into one on the sheet.

```bash
qs -c cedar ipc call notes open
qs -c cedar ipc call notes setPaper dots
qs -c cedar ipc call notes draw '60 80 200 80 200 160' 900
qs -c cedar ipc call notes addNote 90 200 'Call back'
qs -c cedar ipc call notes copy path
```

## Architecture

| File | Role |
|---|---|
| `services/FieldNotes.qml` | The shell's handle: summon/open/close/toggle, Settings deep link, export folder, the `script()` gate the IPC target calls; keeps a summon until the board attaches |
| `modules/FieldNotesBoard.qml` | The board: notebook, per-sheet history, tool and pen width, per-display positions, saving and export, keyboard, the layer surface and its input mask |
| `components/NotesPaper.qml` | One sheet: ruling, ink and wet canvases, notes, pointer tools, header and footer print, export capture |
| `components/NotesToolIsland.qml`, `NotesToolButton.qml`, `NotesTooltip.qml` | The toolbar on the pill's chamfer, its buttons and tooltips |
| `components/NotesTitleField.qml`, `NotesHeaderLabel.qml`, `NotesTextNote.qml`, `NotesBinderClip.qml` | Header controls, typed notes, the drawn clip |
| `components/NotesTheme.qml` | Theme tokens mapped onto the notes; the paper tokens (`paper`, `ink`, `rule`…) are overridable in `theme.json` |
| `components/notes/*.js` | Immutable document model, per-sheet history, the notebook, eraser/hit/smoothing geometry, board layout; run unchanged in QML and Node |
| `modules/FieldNotesSettings.qml` | Settings › Field Notes |

The board is loaded once at stage 3 and kept, like the plugin's `keepLoaded`:
undo history survives putting the notes away, and scripts can draw before the
first open. Its `PanelWindow` maps a surface only while the notes show. Shadows
are offset rectangles, not render layers; all motion is a `Behavior` gated by
`Theme.reducedMotion`; the only animation loop is the `FrameAnimation` that lays
down a scripted stroke, which stops when the stroke commits.

## Tests

```bash
node --test tests/notes/          # model, geometry, history, notebook, layout, state safety, CEDAR contract
python3 tests/check_desktop_ui.py # renders Settings › Field Notes
python3 tests/check_strata_bar.py # the bar with its Field Notes button
```

Drawing, erasing, export and the layer surface's click-through are checked on
the live shell; offscreen renders do not prove them.
