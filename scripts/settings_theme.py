"""Local theme previews and guarded, reversible CEDAR theme writes."""
import base64
import fcntl
import hashlib
import json
from contextlib import contextmanager
import desktop_runtime as runtime


def target():
    return runtime.config() / 'theme.json'


def journal():
    return runtime.xdg('STATE', '.local/state') / 'cedar/settings-theme-restore.json'


def contents():
    return target().read_bytes() if target().exists() else None


def digest(value):
    return hashlib.sha256(value if value is not None else b'CEDAR:absent-theme').hexdigest()


@contextmanager
def locked():
    path = journal().with_suffix('.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def preview(name, accent=''):
    if name not in [t['name'] for t in runtime.themes()]:
        raise ValueError('Theme is no longer installed.')
    base = runtime.read_json(runtime.ROOT / 'themes/palettes/cedar.json')['colors']
    colors = {} if name == 'cedar' else runtime.validate_palette(runtime.read_json(runtime.config() / 'themes' / (name + '.json')))
    palette = {**base, **colors}
    if accent:
        if accent not in ('green', 'teal', 'amber', 'ember'):
            raise ValueError('Choose an accent from this theme.')
        colors = {**colors, 'green': palette[accent]}
        palette['green'] = palette[accent]
    return {'name': name, 'accent': accent, 'colors': colors, 'palette': palette, 'expected': digest(contents())}


def can_restore():
    try:
        record = runtime.read_json(journal())
        return record['after'] == digest(contents())
    except (OSError, ValueError, KeyError, TypeError):
        return False


def apply(request):
    with locked():
        before = contents()
        if request.get('expected') != digest(before):
            raise ValueError('The theme changed outside Settings. Preview it again before applying.')
        chosen = preview(request.get('name'), request.get('accent', ''))
        after = (json.dumps({'name': chosen['name'], 'colors': chosen['colors']}, indent=2) + '\n').encode()
        record = {'before': None if before is None else base64.b64encode(before).decode(), 'after': digest(after)}
        previous_journal = journal().read_bytes() if journal().exists() else None
        runtime.atomic(journal(), (json.dumps(record) + '\n').encode())
        try:
            runtime.atomic(target(), after)
        except Exception:
            # Preserve the prior undo point when a new write never happened.
            if contents() == before:
                if previous_journal is None:
                    journal().unlink(missing_ok=True)
                else:
                    runtime.atomic(journal(), previous_journal)
            raise
        if contents() != after:
            raise RuntimeError('Theme write could not be verified.')
    return {'message': 'Theme applied. Restore previous theme is available.'}


def restore():
    with locked():
        record = runtime.read_json(journal())
        if record['after'] != digest(contents()):
            raise ValueError('The theme changed outside Settings. Restore would overwrite that change.')
        before = None if record['before'] is None else base64.b64decode(record['before'], validate=True)
        if before is None:
            target().unlink(missing_ok=True)
        else:
            runtime.atomic(target(), before)
        if contents() != before:
            raise RuntimeError('Theme restoration could not be verified.')
        journal().unlink()
    return {'message': 'Previous theme restored.'}
