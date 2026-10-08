#!/usr/bin/env python3
"""CEDAR Station's collector. One JSON request on stdin, one reply.

snapshot      failed systemd units (user and system), recent shell-log issues
              since the last launch (redacted, deduplicated), configuration
              files that do not parse, the GPU reading where a supported path
              exists, and the shell's own memory. Read-only.
restart       restart one unit: `systemctl --user` for a user unit, `pkexec
              systemctl` for a system unit (polkit asks the user).
logs          the last 60 journal lines of a unit, redacted.
report        a plain-text diagnostic report built from the request's own
              `sections` plus this snapshot, redacted; nothing is uploaded.

Nothing here polls or keeps running.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
STATE = Path(os.environ.get('XDG_STATE_HOME', HOME / '.local/state')) / 'cedar'
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config')) / 'cedar'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from redaction import redact  # noqa: E402

UNIT = re.compile(r'^[A-Za-z0-9@._:\\-]{1,200}$')


def run(args, timeout=10):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False, env={**os.environ, 'LC_ALL': 'C'})
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or 'Command failed')
    return p.stdout


def failed_units():
    out = []
    for user in (True, False):
        try:
            text = run(['systemctl'] + (['--user'] if user else []) + ['--failed', '--no-legend', '--plain', '--no-pager'])
        except Exception:  # noqa: BLE001  systemd absent or not reachable
            continue
        for line in text.splitlines():
            parts = line.split(None, 4)
            if len(parts) < 4:
                continue
            unit = parts[0].lstrip('●* ')
            out.append({'unit': unit, 'user': user, 'load': parts[1], 'active': parts[2], 'sub': parts[3], 'description': parts[4] if len(parts) > 4 else '', 'result': 'failed'})
    return out[:40]


def log_issues():
    """Issues since the last launch line: load failures and binding errors, deduplicated with counts."""
    path = STATE / 'shell.log'
    try:
        lines = path.read_text(errors='replace').splitlines()[-4000:]
    except OSError:
        return []
    start = 0
    for i, line in enumerate(lines):
        if 'Launching config' in line:
            start = i
    counts, kinds = {}, {}
    for raw in lines[start:]:
        line = re.sub(r'\x1b\[[0-9;]*m', '', raw).strip()
        if 'Failed to load configuration' in line or 'caused by @' in line:
            kind = 'load'
        elif re.search(r'ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign', line):
            kind = 'binding'
        else:
            continue
        key = re.sub(r'^\s*(ERROR|WARN)\s*', '', line)[:240]
        counts[key] = counts.get(key, 0) + 1
        kinds[key] = kind
    rows = [{'line': redact(k), 'count': c, 'kind': kinds[k]} for k, c in counts.items()]
    rows.sort(key=lambda r: (r['kind'] != 'load', -r['count']))
    return rows[:20]


def config_problems():
    out = []
    for name in ('settings.json', 'theme.json', 'profiles.json', 'audio-scenes.json'):
        p = CONFIG / name
        if not p.exists():
            continue
        try:
            json.loads(p.read_text() or '{}')
        except ValueError as error:
            out.append({'file': name, 'problem': 'Not valid JSON: ' + str(error)})
        except OSError as error:
            out.append({'file': name, 'problem': 'Could not be read: ' + str(error)})
    link = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config')) / 'quickshell/cedar'
    if link.is_symlink() and not (link / 'shell.qml').exists():
        out.append({'file': 'quickshell/cedar', 'problem': 'The profile link points at ' + os.readlink(link) + ', which has no shell.qml.'})
    return out


def gpu_reading():
    """Utilisation and temperature where a supported path exists; otherwise absent, never guessed."""
    for card in sorted(Path('/sys/class/drm').glob('card[0-9]*/device')):
        busy = card / 'gpu_busy_percent'
        if busy.exists():
            try:
                value = int(busy.read_text().strip())
            except (OSError, ValueError):
                continue
            temp = None
            for t in card.glob('hwmon/hwmon*/temp1_input'):
                try:
                    temp = int(t.read_text().strip()) / 1000
                except (OSError, ValueError):
                    pass
                break
            return {'available': True, 'source': 'sysfs', 'utilization': value, 'temperature': temp}
    import shutil
    if shutil.which('nvidia-smi'):
        try:
            text = run(['nvidia-smi', '--query-gpu=utilization.gpu,temperature.gpu', '--format=csv,noheader,nounits'], timeout=6)
            util, temp = [x.strip() for x in text.strip().split(',')[:2]]
            return {'available': True, 'source': 'nvidia-smi', 'utilization': int(util), 'temperature': float(temp)}
        except Exception:  # noqa: BLE001
            return {'available': False, 'source': 'nvidia-smi', 'reason': 'nvidia-smi did not answer'}
    return {'available': False, 'source': 'none', 'reason': 'No supported GPU telemetry path'}


def shell_memory():
    pid = os.environ.get('CEDAR_SHELL_PID') or str(os.getppid())
    try:
        for line in (Path('/proc') / pid / 'status').read_text().splitlines():
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) / 1024
    except (OSError, ValueError, IndexError):
        pass
    return -1


def snapshot():
    return {'failedUnits': failed_units(), 'logIssues': log_issues(), 'config': config_problems(), 'gpu': gpu_reading(), 'shellMemoryMb': shell_memory(),
            'logPath': str(STATE / 'shell.log'), 'readAt': __import__('time').time()}


def check_unit(unit):
    if not UNIT.match(unit or '') or '/' in unit:
        raise ValueError('Not a unit name.')
    return unit


def action(req):
    name = req.get('action', 'snapshot')
    if name == 'snapshot':
        return snapshot()
    if name == 'restart':
        unit, user = check_unit(req.get('unit')), req.get('user') is True
        run((['systemctl', '--user'] if user else ['pkexec', 'systemctl']) + ['restart', unit], timeout=120)
        return {'message': unit + ' restarted.', **snapshot()}
    if name == 'reset-failed':
        unit, user = check_unit(req.get('unit')), req.get('user') is True
        run((['systemctl', '--user'] if user else ['pkexec', 'systemctl']) + ['reset-failed', unit], timeout=120)
        return {'message': unit + ' reset.', **snapshot()}
    if name == 'logs':
        unit, user = check_unit(req.get('unit')), req.get('user') is True
        try:
            text = run(['journalctl'] + (['--user'] if user else []) + ['-u', unit, '-n', '60', '--no-pager'])
        except Exception as error:  # noqa: BLE001
            text = 'Unavailable: ' + str(error)
        return {'logs': redact(text)}
    if name == 'report':
        sections = req.get('sections')
        if not isinstance(sections, list):
            raise ValueError('A report needs sections.')
        snap = snapshot()
        body = ['CEDAR Station diagnostic report', '']
        for s in sections[:40]:
            if not isinstance(s, dict):
                continue
            body.append('## ' + str(s.get('title', ''))[:80])
            for line in str(s.get('text', '')).splitlines()[:200]:
                body.append(line[:400])
            body.append('')
        body.append('## Failed units')
        body += [('user ' if u['user'] else 'system ') + u['unit'] + ' · ' + u['sub'] + ' · ' + u['description'] for u in snap['failedUnits']] or ['none']
        body.append('')
        body.append('## Shell log issues since the last launch')
        body += [str(l['count']) + '× ' + l['line'] for l in snap['logIssues']] or ['none']
        body.append('')
        body.append('## Configuration problems')
        body += [c['file'] + ': ' + c['problem'] for c in snap['config']] or ['none']
        return {'report': redact('\n'.join(body))}
    raise ValueError('Unknown station action')


if __name__ == '__main__':
    try:
        print(json.dumps({'ok': True, 'data': action(json.loads(sys.stdin.readline() or '{}'))}))
    except Exception as error:  # noqa: BLE001
        print(json.dumps({'ok': False, 'error': str(error)}))
