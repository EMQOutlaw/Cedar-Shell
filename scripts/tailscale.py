#!/usr/bin/env python3
"""Tailscale through its own `tailscale` CLI. One JSON request on stdin.

`tailscale status --json` is machine-readable and answered locally by
tailscaled, so the probe is cheap and touches no network. Up and down need the
operator (`sudo tailscale set --operator=$USER`) or root; the CLI's own refusal
is passed through as the error. Signing in is never handled here: `tailscale
up` prints a login link and waits, so that goes to a terminal.

Tailscale and Proton VPN are not allowed up together. Each tunnel claims
routes and DNS the other also wants, and Proton's kill switch cuts the tailnet.
The guard lives here as well as in the card, so two surfaces cannot race.
Every subprocess is an argv list.
"""
import json
import re
import shutil
import subprocess
import sys

CLI = 'tailscale'
# Proton's CLI brings its tunnel up as a "ProtonVPN <server>" (older: "pvpn-…") NetworkManager profile.
PROTON = re.compile(r'^(ProtonVPN|pvpn-)', re.I)
ANSI = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]')


def strip(text):
    return ANSI.sub('', text or '')


def short_name(dns_name, fallback=''):
    """'shadownight-1.tail7d0a1a.ts.net.' -> 'shadownight-1'."""
    return (dns_name or '').rstrip('.').split('.')[0] or fallback or ''


def parse_status(raw):
    """`tailscale status --json` -> the few fields a card shows. Anything missing is empty, never an error."""
    try:
        doc = json.loads(raw or '{}')
    except ValueError:
        doc = {}
    if not isinstance(doc, dict):
        doc = {}
    me = doc.get('Self') if isinstance(doc.get('Self'), dict) else {}
    peers = [p for p in (doc.get('Peer') or {}).values() if isinstance(p, dict)]
    exit_node = next((p for p in peers if p.get('ExitNode')), None)
    ips = [ip for ip in me.get('TailscaleIPs') or [] if isinstance(ip, str)]
    state = doc.get('BackendState') or 'NoState'
    tailnet = doc.get('CurrentTailnet') if isinstance(doc.get('CurrentTailnet'), dict) else {}
    return {'state': state, 'up': state == 'Running', 'needsLogin': state == 'NeedsLogin',
            'hostname': short_name(me.get('DNSName'), me.get('HostName', '')),
            'ip': next((ip for ip in ips if ':' not in ip), ips[0] if ips else ''),
            'tailnet': tailnet.get('Name') or '',
            'peers': len(peers), 'peersOnline': sum(1 for p in peers if p.get('Online')),
            'exitNode': short_name(exit_node.get('DNSName'), exit_node.get('HostName', '')) if exit_node else '',
            'health': [h for h in doc.get('Health') or [] if isinstance(h, str)][:3]}


def cli(*args, timeout=12):
    """Run the CLI; return (exit code, stdout, stderr). 124 means it timed out."""
    try:
        done = subprocess.run([CLI, *args], capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired:
        return 124, '', 'Tailscale timed out.'


def failure(stderr, stdout, fallback):
    text = strip(stderr).strip() or strip(stdout).strip()
    lines = [line for line in text.splitlines() if line.strip()]
    return lines[-1][:240] if lines else fallback


def active_connection_names():
    """Names of NetworkManager's active connections; nothing when nmcli is missing or silent."""
    if shutil.which('nmcli') is None:
        return []
    try:
        done = subprocess.run(['nmcli', '-t', '-f', 'NAME', 'connection', 'show', '--active'],
                              capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [line.replace('\\:', ':').strip() for line in done.stdout.splitlines() if line.strip()]


def proton_connected():
    """An active Proton tunnel as NetworkManager sees it: no keyring, no Proton CLI, well under a second."""
    return any(PROTON.match(name) for name in active_connection_names())


def snapshot():
    data = {'installed': shutil.which(CLI) is not None, 'running': False, 'status': parse_status(''), 'error': ''}
    if not data['installed']:
        return data
    code, out, err = cli('status', '--json')
    # The CLI prints its JSON even when stopped or signed out; only a dead tailscaled leaves it silent.
    data['running'] = out.strip() != ''
    data['status'] = parse_status(out)
    if not data['running']:
        data['error'] = failure(err, out, 'Tailscale did not answer. Is the tailscaled service running?')
    return data


def action(req):
    kind = req.get('action', 'status')
    if kind == 'status':
        return snapshot()
    if shutil.which(CLI) is None:
        raise RuntimeError('Tailscale is not installed.')
    if kind == 'up':
        if proton_connected():
            raise RuntimeError('Proton VPN is connected. Disconnect it before bringing Tailscale up; the two are not run together here.')
        if parse_status(cli('status', '--json')[1])['needsLogin']:
            raise RuntimeError('Tailscale is signed out. Sign in from a terminal with `tailscale up`.')
        # Bare `up` re-enables the existing preferences; flags would be a settings change.
        code, out, err = cli('up', '--timeout=45s', timeout=60)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Tailscale could not come up.'))
    elif kind == 'down':
        code, out, err = cli('down', timeout=30)
        if code != 0:
            raise RuntimeError(failure(err, out, 'Tailscale could not go down.'))
    else:
        raise ValueError('Unknown Tailscale action.')
    return snapshot()


def main():
    try:
        req = json.loads(sys.stdin.readline() or '{}')
        print(json.dumps({'ok': True, 'data': action(req)}))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}))


if __name__ == '__main__':
    main()
