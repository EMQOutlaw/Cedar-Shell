#!/usr/bin/env python3
"""Settings › Fastfetch's helper over fastfetch's own configuration.

One JSON request on stdin, one {"ok":true,"data":…} (or {"ok":false,"error":…})
object on stdout — the ServiceRequest protocol. fastfetch's config.jsonc stays
the source of truth: this helper reads it, previews a candidate model by
running fastfetch with it (capturing the real truecolor output), and saves a
candidate back over the config (the previous file is kept as config.jsonc.bak
next to it).

Safety posture:
- The candidate is built by EDITING a deep copy of the original config. Keys
  CEDAR does not manage (module options, custom formats, colors objects,
  display.separator, string/other logo forms…) survive verbatim; a save that
  would change nothing the user edited changes nothing at all. Values CEDAR
  cannot represent (a named accent colour like "red") are preserved, never
  silently dropped.
- Save carries the sha256 of the file as it was read; the hash is rechecked
  under an exclusive lock right before the replacement, so a file that changed
  underneath — even between the backup and the write — is a conflict, never a
  silent overwrite. Non-cooperating external writers that land inside that
  final window cannot be fully excluded without their cooperation; the window
  is a single os.replace wide.
- A symlinked config.jsonc is refused outright — CEDAR will not replace the
  user's link.
- All scratch/backup writes are private (0600, exclusive creation where the
  name is predictable) and land atomically via os.replace.
- Save is refused under CEDAR_TEST / FOXFIRE_TEST, in QML and here at the
  helper boundary. get() is strictly read-only: a missing config is reported,
  never generated.
"""
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config')) / 'fastfetch' / 'config.jsonc'

# The modules a user may put in the readout. The list mirrors what fastfetch
# --list-modules offers, curated to what makes sense in a readout: the
# hardware and system rows CEDAR's machines actually show.
CATALOG = [
    {'key': 'title', 'label': 'Title'}, {'key': 'separator', 'label': 'Separator'},
    {'key': 'os', 'label': 'OS'}, {'key': 'host', 'label': 'Host'},
    {'key': 'kernel', 'label': 'Kernel'}, {'key': 'uptime', 'label': 'Uptime'},
    {'key': 'packages', 'label': 'Packages'}, {'key': 'shell', 'label': 'Shell'},
    {'key': 'terminal', 'label': 'Terminal'}, {'key': 'wm', 'label': 'WM'},
    {'key': 'de', 'label': 'Desktop'}, {'key': 'cpu', 'label': 'CPU'},
    {'key': 'gpu', 'label': 'GPU'}, {'key': 'memory', 'label': 'Memory'},
    {'key': 'disk', 'label': 'Disk'}, {'key': 'battery', 'label': 'Battery'},
    {'key': 'localip', 'label': 'Local IP'}, {'key': 'board', 'label': 'Board'},
    {'key': 'break', 'label': 'Spacer'}, {'key': 'colors', 'label': 'Colour swatches'},
]
CATALOG_KEYS = {row['key'] for row in CATALOG}

# CEDAR's UI kinds and the fastfetch logo types behind them. Everything else —
# "file" (a colour-replaced text logo), "data"/"data-raw" (inline text), the
# image renderers (sixel/kitty/iterm/chafa), "auto", named logos like "arch" —
# is kind "other": preserved verbatim, shown but not edited. CEDAR offers no
# Image kind because rendering depends on the terminal's graphics protocol;
# an existing image-logo config keeps working untouched.
KIND_TO_TYPE = {'none': 'none', 'builtin': 'builtin', 'ascii': 'file-raw'}
TYPE_TO_KIND = {type_name: kind for kind, type_name in KIND_TO_TYPE.items()}


def catalog_label(key):
    for row in CATALOG:
        if row['key'] == key:
            return row['label'].upper()
    return str(key).upper()


def run(args, timeout=15):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or 'Command failed')
    return p.stdout


def installed():
    return shutil.which('fastfetch') is not None


def test_mode():
    return os.environ.get('CEDAR_TEST') == '1' or os.environ.get('FOXFIRE_TEST') == '1'


def strip_comments(text):
    """A tiny JSONC reader: // and /* */ comments and trailing commas are not
    JSON; fastfetch tolerates them, so the reader must too. String contents —
    including one that contains ",]" — survive untouched."""
    out, i, n = [], 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if c == ',':
            # Trailing comma: skip it when the next meaningful character
            # closes the current value. Comments between are skipped too.
            j = i + 1
            while j < n:
                if text[j] == '"':
                    break
                if text[j] == '/' and j + 1 < n and text[j + 1] == '/':
                    while j < n and text[j] != '\n':
                        j += 1
                    continue
                if text[j] == '/' and j + 1 < n and text[j + 1] == '*':
                    j += 2
                    while j + 1 < n and not (text[j] == '*' and text[j + 1] == '/'):
                        j += 1
                    j += 2
                    continue
                if not text[j].isspace():
                    break
                j += 1
            if j < n and text[j] in '}]':
                i += 1
                continue
        out.append(c); i += 1
    return ''.join(out)


def _row_for(module):
    """One editable readout row for a config module. `orig` carries the
    original object (or None for a plain string) so a save can reproduce it
    byte-for-byte; `fixed` marks rows CEDAR only shows, never rewrites."""
    if isinstance(module, str):
        key = module
        known = key in CATALOG_KEYS
        return {'kind': 'module', 'key': key, 'label': catalog_label(key),
                'olabel': catalog_label(key), 'fixed': not known, 'orig': module}
    if isinstance(module, dict) and isinstance(module.get('type'), str):
        key = module['type']
        known = key in CATALOG_KEYS and key not in ('break', 'colors')
        label = str(module.get('key', '') or catalog_label(key))
        return {'kind': 'module', 'key': key, 'label': label,
                'olabel': label, 'fixed': not known, 'orig': module}
    return None


def normalize(config, raw_text):
    """The model CEDAR edits: baseline hash (over the RAW file bytes, so CRLF
    and BOM-prefixed files round-trip), logo {kind,source,width,height,
    padding}, accent, rows [{kind,key,label,…}]. The original config travels
    inside the model ('orig') and every save starts from it; logo and accent
    also carry their raw original representations so a save can replay them
    byte-for-byte whenever the draft did not change them."""
    if not isinstance(config, dict):
        raise ValueError('The fastfetch config is not an object.')
    raw_logo = config.get('logo', {})
    logo_is_string = isinstance(raw_logo, str)
    logo = {} if logo_is_string or not isinstance(raw_logo, dict) else raw_logo
    # A logo dict without a "type" (an implicitly typed file logo) is not
    # CEDAR's to re-type: kind "other" preserves it verbatim.
    if not logo_is_string and logo and 'type' not in logo:
        kind = 'other'
        raw_type = ''
    else:
        raw_type = '' if logo_is_string else str(logo.get('type', 'builtin'))
        kind = 'other' if logo_is_string else TYPE_TO_KIND.get(raw_type, 'other')
    rows = []
    for module in config.get('modules') or []:
        row = _row_for(module)
        if row is not None:
            rows.append(row)
    accent, accent_original = '', ''
    color_was_string = False
    display = config.get('display')
    if isinstance(display, dict):
        color = display.get('color')
        if isinstance(color, str):
            color_was_string = True
            color = {'keys': color, 'title': color}  # fastfetch's string form colours keys AND title
        if isinstance(color, dict) and isinstance(color.get('keys'), str):
            accent_original = color['keys']
            if re.fullmatch(r'\d{1,3};\d{1,3};\d{1,3}', accent_original):
                r, g, b = (int(x) for x in accent_original.split(';'))
                accent = '#%02x%02x%02x' % (min(r, 255), min(g, 255), min(b, 255))
    width_raw, height_raw = logo.get('width', 28), logo.get('height', 14)
    padding_raw = logo.get('padding', 3)
    return {
        'baseline': hashlib.sha256(raw_text if isinstance(raw_text, bytes) else raw_text.encode('utf-8')).hexdigest(),
        'logo': {
            'kind': kind,
            'type': raw_logo if logo_is_string else (raw_type if kind == 'other' else ''),
            'source': str(logo.get('source', '')) if kind == 'ascii' else '',
            'width': int(width_raw or 28),
            'height': int(height_raw or 14),
            'padding': int(padding_raw.get('left', 3) if isinstance(padding_raw, dict) else padding_raw or 3),
            'raw': {'source': logo.get('source', ''), 'width': width_raw, 'height': height_raw, 'padding': padding_raw},
        },
        'accent': accent,
        'accentOriginal': accent_original,
        'colorWasString': color_was_string,
        'rows': rows,
        'orig': config,
    }


def candidate(model):
    """The config dict CEDAR writes back: a deep copy of the original with
    only the fields the draft actually changed. A value the draft left alone —
    including one CEDAR cannot represent in its model — is replayed verbatim."""
    import copy
    if not isinstance(model, dict):
        raise ValueError('The model is not an object.')
    original = model.get('orig')
    if not isinstance(original, dict):
        raise ValueError('The model carries no original config.')
    logo = model.get('logo') or {}
    if not isinstance(logo, dict):
        raise ValueError('The model logo is not an object.')
    kind = str(logo.get('kind', 'builtin'))
    if kind not in KIND_TO_TYPE and kind != 'other':
        raise ValueError('Unknown logo kind: ' + kind)
    raw = logo.get('raw') or {}
    config = copy.deepcopy(original)

    # Emblem. The original logo form (object or bare string like "arch") is
    # replayed unless the draft moved it to a managed kind. Managed kinds set
    # the type and, only for values the draft changed, the size fields — an
    # untouched padding dict like {top:2,left:4,right:7} survives as-is.
    if kind == 'other':
        original_logo = original.get('logo')
        if isinstance(original_logo, str):
            config['logo'] = copy.deepcopy(original_logo)  # e.g. logo = "arch"
        else:
            config['logo'] = copy.deepcopy(original_logo or {'type': 'auto'})
            kept = str(logo.get('type', '') or config['logo'].get('type', ''))
            if kept:
                config['logo']['type'] = kept
            # an original with no type at all stays without one
    else:
        new_logo = copy.deepcopy(original['logo']) if isinstance(original.get('logo'), dict) else {}
        new_logo['type'] = KIND_TO_TYPE[kind]
        if kind == 'ascii':
            source = str(logo.get('source', '')).strip()
            if not source:
                raise ValueError('An ASCII emblem needs a file.')
            if '..' in Path(source).parts or source.startswith('/etc'):
                raise ValueError('That emblem path is not allowed.')
            if source != str(raw.get('source', '')):
                new_logo['source'] = source
            elif 'source' in original.get('logo', {}):
                new_logo['source'] = original['logo']['source']
            width, height, padding = int(logo.get('width', 28)), int(logo.get('height', 14)), int(logo.get('padding', 3))
            if not all(0 <= v <= 200 for v in (width, height, padding)):
                raise ValueError('Logo size out of range.')
            if width != int(raw.get('width', 28) or 28):
                new_logo['width'] = width
            if height != int(raw.get('height', 14) or 14):
                new_logo['height'] = height
            orig_padding = raw.get('padding', 3)
            orig_padding_num = int(orig_padding.get('left', 3)) if isinstance(orig_padding, dict) else int(orig_padding or 3)
            if padding != orig_padding_num:
                if isinstance(orig_padding, dict):
                    new_padding = dict(orig_padding)  # top/right/bottom stay; only the left column is CEDAR's
                    new_padding['left'] = padding
                else:
                    new_padding = {'left': padding}
                new_logo['padding'] = new_padding
            # else: the original padding (scalar or object) stays verbatim
        config['logo'] = new_logo

    # Accent. The string form of display.color colours keys AND title, so an
    # untouched config (or one CEDAR cannot represent) replays verbatim; only
    # an explicit accent edit rewrites the colour — carrying the original
    # title colour along when it came from the string form.
    accent = str(model.get('accent', '') or '').strip().lstrip('#').lower()
    if accent and not re.fullmatch(r'[0-9a-f]{6}|[0-9a-f]{8}', accent):
        raise ValueError('The accent must be a hex colour like a1b2c3.')
    if len(accent) == 8:
        accent = accent[2:]  # AARRGGBB (Theme tokens) -> RRGGBB
    accent_original = str(model.get('accentOriginal', '') or '')
    representable = bool(re.fullmatch(r'\d{1,3};\d{1,3};\d{1,3}', accent_original))
    original_hex = ''
    if representable:
        r, g, b = (int(x) for x in accent_original.split(';'))
        original_hex = '%02x%02x%02x' % (min(r, 255), min(g, 255), min(b, 255))
    if accent and accent != original_hex:
        accent_triple = ';'.join(str(int(accent[i:i + 2], 16)) for i in (0, 2, 4))
        display = dict(config.get('display') or {})
        old_color = display.get('color')
        color = dict(old_color) if isinstance(old_color, dict) else {}
        color['keys'] = accent_triple
        if model.get('colorWasString') and accent_original:
            color['title'] = accent_original  # the string form coloured the title too; keep it
        display['color'] = color
        config['display'] = display
    elif not accent and representable:
        display = config.get('display')
        if isinstance(display, dict):
            old_color = display.get('color')
            if isinstance(old_color, str) and old_color == accent_original:
                # the string form coloured keys AND title; clearing removes the
                # keys override and keeps the title colour
                config['display'] = {**display, 'color': {'title': old_color}}
            elif isinstance(old_color, dict) and 'keys' in old_color:
                color = dict(old_color)
                del color['keys']
                if color:
                    display['color'] = color
                else:
                    del display['color']
                if display:
                    config['display'] = display
                else:
                    del config['display']
    # else: untouched, or an unrepresentable original ("red") — display stays verbatim

    # Rows: every row replays its original object; a relabel sets the label
    # key on a copy of it; a key change builds a fresh module. No
    # deduplication — two custom rows with different formats are the user's
    # data, and fastfetch printing a repeated row twice is the user's choice.
    rows = model.get('rows')
    if not isinstance(rows, list) or len(rows) > 60:
        raise ValueError('The readout needs a list of rows (60 at most).')
    modules = []
    for row in rows:
        if not isinstance(row, dict) or row.get('kind') != 'module' or not isinstance(row.get('key'), str):
            raise ValueError('Every readout row is a module row.')
        key = row['key']
        orig = row.get('orig')
        label = str(row.get('label', '') or catalog_label(key))
        if isinstance(orig, dict) and orig.get('type') == key:
            item = copy.deepcopy(orig)
            if not row.get('fixed') and label != str(row.get('olabel', '') or ''):
                item['key'] = label.upper()
        elif isinstance(orig, str) and orig == key:
            if label == str(row.get('olabel', '') or catalog_label(key)):
                item = key
            else:
                # A relabelled plain-string module becomes the object form —
                # the only way fastfetch can carry a label for it.
                item = {'type': key, 'key': label.upper()}
        elif key in ('break', 'colors') and not isinstance(orig, (dict, str)):
            item = 'break' if key == 'break' else {'type': 'colors', 'symbol': 'circle'}
        else:
            # A key change is a new module; a label that still belongs to the
            # old key follows the new key's own label.
            item = {'type': key, 'key': (label.upper() if label != str(row.get('olabel', '') or '') else catalog_label(key))}
        modules.append(item)
    if modules or 'modules' in original:
        config['modules'] = modules
    return config


def _private_text_file(directory, prefix):
    """An exclusively created 0600 temp file in `directory` (same dir as the
    target, so os.replace stays atomic). Returns (path, fd)."""
    fd, name = tempfile.mkstemp(prefix=prefix, suffix='.jsonc', dir=str(directory))
    os.fchmod(fd, 0o600)
    return Path(name), fd


def _write_atomic(target, body, mode):
    """Write `body` (str or bytes) to `target` via a private temp file +
    os.replace, with the given permission bits, fsync'd before the rename."""
    tmp, fd = _private_text_file(target.parent, target.name + '.cedar-')
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(body.encode('utf-8') if isinstance(body, str) else body)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def _prepare_atomic(target, body, mode):
    """The prepare half of _write_atomic: the fully written, fsync'd private
    temp file, not yet renamed. Splitting the two lets save() revalidate the
    target at the true commit boundary — the only remaining window is the
    os.replace itself."""
    tmp, fd = _private_text_file(target.parent, target.name + '.cedar-')
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(body.encode('utf-8') if isinstance(body, str) else body)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        return tmp
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def preview(model):
    """Run fastfetch with the candidate (no user file written) and return its
    truecolor output for the in-panel specimen."""
    if not installed():
        raise RuntimeError('fastfetch is not installed.')
    config = candidate(model)
    path, fd = _private_text_file(Path(tempfile.gettempdir()), 'cedar-fastfetch-preview-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(config, handle, indent=2, ensure_ascii=False)
        text = run(['fastfetch', '-c', str(path), '--pipe', 'false'], timeout=20)
    finally:
        path.unlink(missing_ok=True)
    return {'preview': text}


def load_model():
    """Read config.jsonc and return (model, error_string-or-empty). Read-only:
    a missing config is reported, never generated. The baseline hashes the
    RAW bytes, so a CRLF config round-trips instead of failing every save."""
    try:
        raw = CONFIG.read_bytes()
        return normalize(json.loads(strip_comments(raw.decode('utf-8'))), raw), ''
    except FileNotFoundError:
        return None, 'No fastfetch config found. Run "fastfetch --gen-config" once in a terminal, then reopen this page.'
    except Exception as error:  # noqa: BLE001  jsonc malformed, unknown shape
        return None, 'fastfetch config could not be parsed: ' + str(error)


def get():
    if not installed():
        return {'installed': False, 'model': None, 'catalog': CATALOG, 'configPath': str(CONFIG)}
    model, error = load_model()
    return {'installed': True, 'model': model, 'catalog': CATALOG, 'configPath': str(CONFIG),
            'presets': list_presets(),
            **({'error': error} if error else {})}


# fastfetch ships curated presets with the package itself; they are the
# community's popular configurations, already on disk — nothing to download.
PRESETS_DIR = Path('/usr/share/fastfetch/presets')
PRESET_NOTES = {
    'neofetch': 'The classic Neofetch layout',
    'paleofetch': 'Paleofetch: the bare-minimum readout',
    'screenfetch': 'The Screenfetch layout',
    'archey': 'The Archey layout',
    'ci': 'A minimal one-line summary',
    'all': 'Every module fastfetch offers',
}


def list_presets():
    """The presets fastfetch installed: the named ones plus the numbered
    community examples. Empty when the package carries none. Entries outside
    the resolved base (a symlinked preset file) are skipped — preset_model
    would refuse them, so listing them would offer a button that errors."""
    out = []
    if not PRESETS_DIR.is_dir():
        return out
    base = PRESETS_DIR.resolve()
    for path in sorted(PRESETS_DIR.glob('*.jsonc')):
        if base not in path.resolve().parents:
            continue
        out.append({'name': path.stem, 'note': PRESET_NOTES.get(path.stem, 'Fastfetch preset')})
    examples = PRESETS_DIR / 'examples'
    if examples.is_dir():
        for path in sorted(examples.glob('*.jsonc'), key=lambda p: (len(p.stem), p.stem)):
            if base not in path.resolve().parents:
                continue
            out.append({'name': 'examples/' + path.stem, 'note': 'Community example ' + path.stem})
    return out


def preset_model(name):
    """A preset as an editable model. `orig` is the preset config (so the save
    starts from the preset, not the user's file); `baseline` is the hash of the
    user's live config.jsonc, so the save's conflict check still guards the
    file that will actually be replaced."""
    if not isinstance(name, str) or not name:
        raise ValueError('A preset name is required.')
    if not PRESETS_DIR.is_dir():
        raise RuntimeError('This machine has no fastfetch presets directory.')
    base = PRESETS_DIR.resolve()  # a symlinked presets dir must not fail the containment check below
    target = (base / (name + '.jsonc')).resolve()
    if base not in target.parents or not target.is_file():
        raise ValueError('Unknown fastfetch preset: ' + name)
    config = json.loads(strip_comments(target.read_text(encoding='utf-8')))
    try:
        raw = CONFIG.read_bytes()
    except OSError:  # missing OR unreadable: the preset still loads; save's hash check guards the real file
        raw = None
    model = normalize(config, raw if raw is not None else 'absent')
    if raw is None:
        model['baseline'] = 'absent'  # save() checks the same sentinel
    return model


@contextlib.contextmanager
def _save_lock():
    """Serialize CEDAR's own writers around the backup/replace sequence. The
    lock file is created without following symlinks (O_NOFOLLOW) and never
    truncated — an attacker-controlled symlink must not become a write."""
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    lock_path = CONFIG.parent / '.cedar-save.lock'
    try:
        fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError as error:
        raise RuntimeError('The fastfetch save lock could not be opened safely: ' + str(error))
    with contextlib.suppress(OSError):
        os.fchmod(fd, 0o600)  # an earlier lock file may predate the private mode
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _current_hash():
    try:
        return hashlib.sha256(CONFIG.read_bytes()).hexdigest()
    except FileNotFoundError:
        return 'absent'


def save(model):
    if test_mode():
        raise RuntimeError('Refusing to save: CEDAR is running under a test environment.')
    if not installed():
        raise RuntimeError('fastfetch is not installed.')
    if not isinstance(model, dict):
        raise ValueError('The model is not an object.')
    if CONFIG.is_symlink():
        raise RuntimeError('config.jsonc is a symlink. CEDAR refuses to replace it; point the link where you want and keep the target a regular file.')
    config = candidate(model)
    preview(model)  # refuse to save what fastfetch cannot run
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    baseline = model.get('baseline')
    mode = (CONFIG.stat().st_mode & 0o777) if CONFIG.exists() else 0o600
    body = json.dumps(config, indent=2, ensure_ascii=False) + '\n'
    backup = CONFIG.with_name(CONFIG.name + '.bak')
    with _save_lock():
        # The file must still be the one this model was read from — checked
        # again inside the lock. The replacement is prepared and fsync'd
        # BEFORE the final revalidation, so the only window left afterwards
        # is the os.replace itself (a non-cooperating external writer landing
        # inside it cannot be excluded without its cooperation; documented).
        if _current_hash() != baseline:
            raise RuntimeError('config.jsonc changed since it was read (outside this page). Nothing was written — reopen the page, check the config, and save again.')
        if CONFIG.exists():
            _write_atomic(backup, CONFIG.read_bytes(), mode)  # the file as it was, byte-exact (CRLF stays CRLF)
        prepared = _prepare_atomic(CONFIG, body, mode)
        try:
            # Commit-boundary revalidation: content AND file type. A symlink
            # swapped in during the preview hook must not be destroyed.
            if CONFIG.is_symlink():
                raise RuntimeError('config.jsonc became a symlink while the save was prepared. Nothing was written.')
            if _current_hash() != baseline:  # commit-boundary revalidation
                raise RuntimeError('config.jsonc changed while the save was prepared. Nothing was written — reopen the page and save again.')
            os.replace(prepared, CONFIG)
        except BaseException:
            prepared.unlink(missing_ok=True)
            raise
    return {'saved': True, 'configPath': str(CONFIG),
            'backup': str(backup) if backup.exists() else ''}


def action(req):
    name = req.get('action', 'get')
    if name == 'get':
        return get()
    if name == 'preset':
        return {'preset': req.get('name'), 'model': preset_model(req.get('name')),
                'catalog': CATALOG, 'configPath': str(CONFIG), 'presets': list_presets()}
    if name == 'preview':
        return preview(req.get('model'))
    if name == 'save':
        return save(req.get('model'))
    raise ValueError('Unknown fastfetch action')


if __name__ == '__main__':
    try:
        print(json.dumps({'ok': True, 'data': action(json.loads(sys.stdin.readline() or '{}'))}))
    except Exception as error:  # noqa: BLE001
        print(json.dumps({'ok': False, 'error': str(error)}))
