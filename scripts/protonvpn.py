#!/usr/bin/env python3
"""Proton VPN through Proton's own `protonvpn` CLI. One JSON request on stdin.

The CLI has no machine-readable output, so every parser here is tolerant:
unknown lines are skipped, and a renamed field shows up as a missing value
rather than an error. Sign-in is never handled here; the password and 2FA go
to Proton's own prompt in a terminal. Every subprocess is an argv list.

Proton and Tailscale are not allowed up together (each claims routes and DNS
the other wants; Proton's kill switch cuts the tailnet), so `connect` first
asks tailscaled, locally and cheaply, whether Tailscale is running. The card
holds the same guard; this one stops two surfaces racing.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CLI = 'protonvpn'
CACHE = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'cedar' / 'proton-countries.json'
COUNTRY_TTL = 7 * 86400
# Settings this card may change, and the values Proton's CLI accepts for them.
SETTINGS = {'kill-switch': ('off', 'standard'),
            'netshield': ('off', 'malware-only', 'malware-ads-trackers')}
ANSI = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]')


def strip(text):
    return ANSI.sub('', text or '')


def key_values(raw):
    """'Label: value' lines -> {label.lower(): value}; prose and tables are skipped."""
    out = {}
    for line in strip(raw).splitlines():
        label, sep, value = line.strip().partition(':')
        label, value = label.strip(), value.strip()
        if not sep or not label or not value or len(label) > 28 or '  ' in label:
            continue
        out.setdefault(label.lower(), value)
    return out


def parse_status(raw):
    kv = key_values(raw)
    status = kv.get('status', '')
    server = kv.get('server', '')
    match = re.match(r'^(\S+)\s+in\s+(.+)$', server)
    # "Disconnected" contains "connect": anchor at the start.
    return {'connected': bool(re.match(r'connected', status, re.I)),
            'connecting': bool(re.match(r'connecting', status, re.I)),
            'text': status or 'Unknown',
            'server': match.group(1) if match else server,
            'location': match.group(2) if match else '',
            'load': kv.get('load', ''), 'protocol': kv.get('protocol', '')}


def parse_account(raw):
    kv = key_values(raw)
    account = kv.get('account', '').strip('\'"').strip()
    plan = kv.get('plan', '').strip('\'"').strip()
    signed_in = account != '' and account.lower() != 'none'
    return {'signedIn': signed_in, 'account': account if signed_in else '',
            'plan': plan if signed_in else '',
            'paid': signed_in and bool(re.search(r'plus|visionary|unlimited|business|family|\bduo\b', plan, re.I))}


def parse_countries(raw):
    out = []
    for line in strip(raw).splitlines():
        match = re.match(r'^\s*(.+?)\s{2,}([A-Za-z]{2})\s*$', line)
        if match and match.group(1).strip().lower() != 'country' and not re.fullmatch(r'[-+=|\s]+', line):
            out.append({'name': match.group(1).strip(), 'code': match.group(2).upper()})
    return out


def parse_config(raw):
    out = {}
    for line in strip(raw).splitlines():
        match = re.match(r'^\s*([a-z][a-z0-9-]*)\s{2,}(\S+)\s*$', line, re.I)
        if match and match.group(1).lower() != 'setting':
            out[match.group(1).lower()] = match.group(2).lower()
    return out


def cli(*args, timeout=12):
    """Run the CLI; return (exit code, stdout, stderr). 124 means it timed out."""
    try:
        done = subprocess.run([CLI, *args], capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired:
        return 124, '', 'The Proton CLI timed out (it may be waiting on the keyring).'


def tailscale_up():
    """Whether Tailscale is running, from its own local status. Absent or silent counts as down."""
    if shutil.which('tailscale') is None:
        return False
    try:
        done = subprocess.run(['tailscale', 'status', '--json'], capture_output=True, text=True, timeout=8, stdin=subprocess.DEVNULL)
        return json.loads(done.stdout or '{}').get('BackendState') == 'Running'
    except (OSError, subprocess.TimeoutExpired, ValueError, AttributeError):
        return False


def failure(stderr, stdout, fallback):
    text = strip(stderr).strip() or strip(stdout).strip()
    lines = [line for line in text.splitlines() if line.strip()]
    return lines[-1][:240] if lines else fallback


def countries(force=False):
    try:
        cached = json.loads(CACHE.read_text())
        if not force and time.time() - cached['at'] < COUNTRY_TTL and cached['rows']:
            return cached['rows']
    except (OSError, ValueError, KeyError, TypeError):
        pass
    code, out, _ = cli('countries', 'list', timeout=20)
    rows = parse_countries(out) if code == 0 else []
    if rows:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE.with_suffix('.tmp')
        tmp.write_text(json.dumps({'at': time.time(), 'rows': rows}))
        tmp.replace(CACHE)
    return rows


def snapshot(want_countries=False):
    data = {'installed': shutil.which(CLI) is not None,
            # The GTK app shares the CLI's backend and refuses to run beside it.
            'conflict': shutil.which('protonvpn-app') is not None,
            'signedIn': False, 'account': '', 'plan': '', 'paid': False,
            'status': parse_status(''), 'config': {}, 'countries': [], 'error': ''}
    if not data['installed']:
        return data
    with ThreadPoolExecutor(3) as pool:
        info, status, config = pool.submit(cli, 'info'), pool.submit(cli, 'status'), pool.submit(cli, 'config', 'list')
        info, status, config = info.result(), status.result(), config.result()
    if info[0] == 124:
        data['error'] = failure(info[2], '', 'The Proton CLI timed out.')
    data.update(parse_account(info[1]) if info[0] == 0 else {})
    if status[0] == 0:
        data['status'] = parse_status(status[1])
    if data['signedIn']:
        data['config'] = parse_config(config[1]) if config[0] == 0 else {}
        if want_countries:
            data['countries'] = countries()
    return data


def connect_args(req):
    target = req.get('target', 'fastest')
    if target == 'fastest':
        return []
    if target in ('p2p', 'securecore', 'tor'):
        return ['--' + target]
    if target == 'country':
        code = str(req.get('country', ''))
        if not re.fullmatch(r'[A-Za-z]{2}', code):
            raise ValueError('Choose a country.')
        return ['--country', code.upper()]
    raise ValueError('Unknown connection target.')


def action(req):
    kind = req.get('action', 'status')
    if kind == 'status':
        return snapshot(req.get('countries') is True)
    if kind == 'countries':
        return {'countries': countries(force=True)}
    if shutil.which(CLI) is None:
        raise RuntimeError('The Proton VPN CLI is not installed.')
    if kind == 'connect':
        args = connect_args(req)
        if tailscale_up():
            raise RuntimeError('Tailscale is up. Bring it down before connecting Proton VPN; the two are not run together here.')
        code, out, err = cli('connect', *args, timeout=90)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Proton could not connect.'))
    elif kind == 'disconnect':
        code, out, err = cli('disconnect', timeout=30)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Proton could not disconnect.'))
    elif kind == 'config':
        key, value = str(req.get('key', '')), str(req.get('value', ''))
        if value not in SETTINGS.get(key, ()):
            raise ValueError('That Proton setting is not available here.')
        code, out, err = cli('config', 'set', key, value, timeout=20)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Proton refused the setting.'))
    elif kind == 'signout':
        code, out, err = cli('signout', timeout=20)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Proton could not sign out.'))
    else:
        raise ValueError('Unknown Proton action.')
    return snapshot()


def main():
    try:
        req = json.loads(sys.stdin.readline() or '{}')
        print(json.dumps({'ok': True, 'data': action(req)}))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}))


if __name__ == '__main__':
    main()
