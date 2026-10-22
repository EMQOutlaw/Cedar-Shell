#!/usr/bin/env python3
"""Settings › Dictation's helper over Voxtype's own configuration commands.

One JSON request on stdin, one reply on stdout ({"ok": true, "data": …} or
{"ok": false, "error": …}). CEDAR never edits Voxtype's config.toml itself:
every change goes through `voxtype config set <key> <value>`, which type-checks
the value against Voxtype's schema and preserves comments, and the daemon is
restarted afterwards because every key in that schema needs one. Only the keys
in KEYS, Voxtype's everyday choices, are accepted; the rest stay in Voxtype's
own TUI (`voxtype configure`). Nothing here reads audio or transcripts.
"""
import json
import math
import re
import shutil
import subprocess
import sys

# key: (kind, constraint). Kinds: bool, int (min, max), float (min, max),
# choice (allowed values), text (regular expression), model, device.
KEYS = {
    'whisper.model': ('model', None),
    'whisper.language': ('text', r'^(auto|[a-z]{2,3}(,[a-z]{2,3})*)$'),
    'whisper.translate': ('bool', None),
    'audio.device': ('device', None),
    'audio.max_duration_secs': ('int', (5, 3600)),
    'audio.pause_media': ('bool', None),
    'audio.duck_media': ('bool', None),
    'audio.feedback.enabled': ('bool', None),
    'audio.feedback.theme': ('choice', ('default', 'subtle', 'mechanical')),
    'audio.feedback.volume': ('float', (0, 1)),
    'output.mode': ('choice', ('type', 'clipboard', 'paste')),
    'output.fallback_to_clipboard': ('bool', None),
    'output.auto_submit': ('bool', None),
    'output.shift_enter_newlines': ('bool', None),
    'output.pre_type_delay_ms': ('int', (0, 5000)),
    'output.append_text': ('text', r'^[^\r\n]{0,80}$'),
    'output.notification.on_recording_start': ('bool', None),
    'output.notification.on_recording_stop': ('bool', None),
    'output.notification.on_transcription': ('bool', None),
    'text.spoken_punctuation': ('bool', None),
    'text.smart_auto_submit': ('bool', None),
    'text.filter_filler_words': ('bool', None),
    'vad.enabled': ('bool', None),
    'osd.enabled': ('bool', None),
    'vad.threshold': ('float', (0, 1)),
}
MODEL_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
DEVICE_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._:,=-]{0,127}$')


def run(args, timeout=20, check=True):
    completed = subprocess.run(args, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    if check and completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or '').strip().splitlines()
        raise RuntimeError(' '.join(args[:3]) + ' failed' + (': ' + detail[-1][:200] if detail else ''))
    return completed.stdout


def installed():
    return shutil.which('voxtype') is not None


def version():
    try:
        return run(['voxtype', '--version'], timeout=5).strip().split()[-1]
    except Exception:  # noqa: BLE001 - the version is decoration
        return ''


def daemon_active():
    try:
        return run(['systemctl', '--user', 'is-active', 'voxtype'], timeout=5, check=False).strip() == 'active'
    except Exception:  # noqa: BLE001
        return False


def models():
    """Whisper models Voxtype knows, installed or downloadable; the engine CEDAR exposes."""
    try:
        catalog = json.loads(run(['voxtype', 'info', 'models', '--json'], timeout=20))
    except Exception:  # noqa: BLE001 - an older Voxtype without --json still works without a catalog
        return []
    if not isinstance(catalog, dict):
        return []
    whisper = (catalog.get('engines') or {}).get('whisper') or {}
    if not isinstance(whisper, dict):
        return []
    rows = []
    for m in whisper.get('models') or []:
        name = str(m.get('name', ''))
        if MODEL_NAME.match(name):
            rows.append({'name': name, 'installed': bool(m.get('installed')), 'downloadable': bool(m.get('downloadable', True)),
                         'download': str(m.get('download_arg') or name)})
    return rows


def devices():
    try:
        rows = json.loads(run(['voxtype', 'info', 'devices', '--json'], timeout=20))
    except Exception:  # noqa: BLE001
        return []
    out = []
    for d in rows if isinstance(rows, list) else []:
        name = str(d.get('name', ''))
        if DEVICE_NAME.match(name):
            out.append({'name': name, 'default': bool(d.get('default'))})
    return out


def config():
    raw = json.loads(run(['voxtype', 'config', 'get', '--json'], timeout=20))
    return {k: raw.get(k) for k in KEYS}


def snapshot(message=''):
    if not installed():
        return {'installed': False, 'daemon': False, 'version': '', 'config': {}, 'models': [], 'devices': [], 'message': message}
    return {'installed': True, 'daemon': daemon_active(), 'version': version(), 'config': config(),
            'models': models(), 'devices': devices(), 'message': message}


def render(key, value):
    """The string `voxtype config set` receives, after CEDAR's own check; Voxtype checks again."""
    kind, constraint = KEYS[key]
    if kind == 'bool':
        if not isinstance(value, bool):
            raise ValueError(key + ' must be true or false')
        return 'true' if value else 'false'
    if kind == 'int':
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or int(value) != value:
            raise ValueError(key + ' must be a whole number')
        number = int(value)
        if not constraint[0] <= number <= constraint[1]:
            raise ValueError(key + ' must be between ' + str(constraint[0]) + ' and ' + str(constraint[1]))
        return str(number)
    if kind == 'float':
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(key + ' must be a number')
        if not constraint[0] <= value <= constraint[1]:
            raise ValueError(key + ' must be between ' + str(constraint[0]) + ' and ' + str(constraint[1]))
        number = round(float(value), 2)
        return str(number)
    if not isinstance(value, str):
        raise ValueError(key + ' must be text')
    text = value
    if kind == 'choice' and text not in constraint:
        raise ValueError(key + ' must be one of ' + ', '.join(constraint))
    if kind == 'text' and not re.fullmatch(constraint, text):
        raise ValueError(key + ' is not a valid value')
    if kind == 'model' and not MODEL_NAME.fullmatch(text):
        raise ValueError('That is not a model name')
    if kind == 'device' and not DEVICE_NAME.fullmatch(text):
        raise ValueError('That is not a device name')
    return text


def restart_daemon():
    run(['systemctl', '--user', 'restart', 'voxtype'], timeout=30)


def action(req):
    name = req.get('action', 'read')
    if name == 'read':
        return snapshot()
    if not installed():
        raise RuntimeError('Voxtype is not installed.')
    if name == 'set':
        key = str(req.get('key', ''))
        if key not in KEYS:
            raise ValueError('CEDAR does not change that Voxtype setting.')
        value = render(key, req.get('value'))
        run(['voxtype', 'config', 'set', key, value], timeout=20)
        restart_daemon()
        return snapshot('Applied; Voxtype restarted.')
    if name == 'unset':
        key = str(req.get('key', ''))
        if key not in KEYS:
            raise ValueError('CEDAR does not change that Voxtype setting.')
        run(['voxtype', 'config', 'unset', key], timeout=20)
        restart_daemon()
        return snapshot('Back to Voxtype\'s default; Voxtype restarted.')
    if name == 'download':
        wanted = str(req.get('model', ''))
        rows = [m for m in models() if m['name'] == wanted or m['download'] == wanted]
        if not rows or not rows[0]['downloadable']:
            raise ValueError('That model is not in Voxtype\'s catalog.')
        if rows[0]['installed']:
            return snapshot(wanted + ' is already installed.')
        run(['voxtype', 'setup', '--download', '--model', rows[0]['download'], '--quiet', '--no-post-install'], timeout=1800)
        return snapshot(wanted + ' downloaded. Choose it above to use it.')
    if name == 'restart':
        restart_daemon()
        return snapshot('Voxtype restarted.')
    raise ValueError('Unknown dictation action')


if __name__ == '__main__':
    try:
        print(json.dumps({'ok': True, 'data': action(json.loads(sys.stdin.readline() or '{}'))}))
    except Exception as error:  # noqa: BLE001 - one reply, never a traceback on stdout
        print(json.dumps({'ok': False, 'error': str(error)}))
