#!/usr/bin/env python3
"""Shield's system side: read the real protection state, change it through each
provider's own interface, verify, and roll back when verification fails.

One JSON request on stdin, one reply on stdout. Actions:
  snapshot                       every protection's current state (no privileges)
  firewall {enable}              the owning manager's native enable/disable via pkexec
  dns {mode, provider}           DNS-over-TLS on the active NetworkManager connection,
                                 served by systemd-resolved; captured, applied, verified
  wifi {policy}                  the Wi-Fi profile's MAC address policy (NetworkManager)
  exposure                       a fresh listener scan from /proc/net

Nothing is polled: the shell asks when Shield opens, when the user refreshes,
after an action, and when the network state materially changes.
"""
import json
import os
import re
import socket
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capabilities  # noqa: E402

DOT_PROVIDERS = {
    'cloudflare': dict(label='Cloudflare', v4=['1.1.1.1#cloudflare-dns.com', '1.0.0.1#cloudflare-dns.com'],
                       v6=['2606:4700:4700::1111#cloudflare-dns.com', '2606:4700:4700::1001#cloudflare-dns.com']),
    'quad9': dict(label='Quad9', v4=['9.9.9.9#dns.quad9.net', '149.112.112.112#dns.quad9.net'],
                  v6=['2620:fe::fe#dns.quad9.net', '2620:fe::9#dns.quad9.net']),
    'mullvad': dict(label='Mullvad', v4=['194.242.2.2#dns.mullvad.net'], v6=['2a07:e340::2#dns.mullvad.net']),
}
MAC_POLICIES = {'stable': 'stable', 'random': 'random', 'hardware': 'permanent', 'default': 'preserve'}


def run(argv, timeout=20, check=True):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False, env={**os.environ, 'LC_ALL': 'C'})
    if check and p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or ' '.join(argv[:2]) + ' failed')
    return p.stdout


# ------------------------------------------------------------------ exposure
def parse_proc_net(text, proto, listening_only=True):
    """Rows of /proc/net/tcp{,6}/udp{,6}: (ip, port, inode) for listeners."""
    rows = []
    for line in text.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 10:
            continue
        local, state, inode = fields[1], fields[3], fields[9]
        if proto.startswith('tcp') and listening_only and state != '0A':
            continue
        if proto.startswith('udp') and state not in ('07',):
            continue
        hexip, hexport = local.rsplit(':', 1)
        port = int(hexport, 16)
        if len(hexip) == 8:
            ip = socket.inet_ntop(socket.AF_INET, struct.pack('<I', int(hexip, 16)))
        else:
            packed = b''.join(struct.pack('<I', int(hexip[i:i + 8], 16)) for i in range(0, 32, 8))
            ip = socket.inet_ntop(socket.AF_INET6, packed)
        rows.append((ip, port, inode))
    return rows


def scope_of(ip):
    if ip.startswith('127.') or ip == '::1' or ip.startswith('::ffff:127.'):
        return 'local'
    if ip in ('0.0.0.0', '::'):
        return 'all'
    return 'lan'


def socket_owners():
    """inode -> process name for this user's processes (others are not readable)."""
    owners = {}
    uid = os.getuid()
    for pid in Path('/proc').iterdir():
        if not pid.name.isdigit():
            continue
        try:
            if pid.stat().st_uid != uid:
                continue
            comm = (pid / 'comm').read_text().strip()
            for fd in (pid / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:['):
                    owners[target[8:-1]] = comm
        except OSError:
            continue
    return owners


def exposure(proc=Path('/proc/net')):
    owners = socket_owners()
    seen, listeners = set(), []
    for proto in ('tcp', 'tcp6', 'udp', 'udp6'):
        try:
            text = (proc / proto).read_text()
        except OSError:
            continue
        for ip, port, inode in parse_proc_net(text, proto):
            key = (proto[:3], port, scope_of(ip), ip)
            if key in seen:
                continue
            seen.add(key)
            listeners.append(dict(proto=proto[:3], port=port, bind=ip, scope=scope_of(ip), process=owners.get(inode, '')))
    listeners.sort(key=lambda r: ({'all': 0, 'lan': 1, 'local': 2}[r['scope']], r['port'], r['proto']))
    counts = {s: len([r for r in listeners if r['scope'] == s]) for s in ('local', 'lan', 'all')}
    return dict(listeners=listeners[:200], local=counts['local'], lan=counts['lan'], all=counts['all'],
                exposed=counts['lan'] + counts['all'], truncated=len(listeners) > 200)


# ----------------------------------------------------------------------- dns
def parse_resolvectl(text):
    """Blocks of `resolvectl status`: global and per link, with DoT and servers."""
    blocks, current = {}, None
    for line in text.splitlines():
        head = re.match(r'^(Global|Link \d+ \(([^)]+)\))', line.strip())
        if head:
            current = head.group(2) or 'global'
            blocks[current] = dict(dot=None, servers=[], current='')
            continue
        if current is None:
            continue
        key, _, value = line.strip().partition(':')
        key, value = key.strip(), value.strip()
        if key == 'Protocols':
            blocks[current]['dot'] = '+DNSOverTLS' in value
            blocks[current]['dnssec'] = 'DNSSEC=yes' in value
        elif key == 'DNS Servers':
            blocks[current]['servers'] = value.split()
        elif key == 'Current DNS Server':
            blocks[current]['current'] = value
        elif key == 'DNS Domain' or key == 'Fallback DNS Servers':
            pass
    return blocks


def default_device():
    out = run(['ip', '-o', 'route', 'show', 'default'], check=False)
    match = re.search(r'\bdev\s+(\S+)', out)
    return match.group(1) if match else ''


def active_connection(device=''):
    for line in run(['nmcli', '-t', '-f', 'NAME,UUID,TYPE,DEVICE', 'connection', 'show', '--active'], check=False).splitlines():
        parts = line.split(':')
        if len(parts) >= 4 and parts[2] in ('802-3-ethernet', '802-11-wireless') and (not device or parts[3] == device):
            return dict(name=parts[0], uuid=parts[1], type=parts[2], device=parts[3])
    return None


def nm_fields(uuid, fields):
    out = run(['nmcli', '-g', ','.join(fields), 'connection', 'show', uuid])
    values = out.rstrip('\n').split('\n')
    return {f: (values[i] if i < len(values) else '') for i, f in enumerate(fields)}


DNS_FIELDS = ['connection.dns-over-tls', 'ipv4.dns', 'ipv4.ignore-auto-dns', 'ipv6.dns', 'ipv6.ignore-auto-dns']


def provider_for(servers):
    for key, spec in DOT_PROVIDERS.items():
        if any(s in servers for s in spec['v4'] + spec['v6']):
            return key
    return 'custom' if servers else 'network'


def dns(caps):
    info = dict(resolver=caps['resolver'], supported=caps['dotSupported'], mode='off', provider='network', providerLabel='Your network',
                servers=[], link='', connection=None, reason='')
    if caps['resolver'] != 'systemd-resolved':
        info['reason'] = 'DNS-over-TLS needs systemd-resolved behind NetworkManager; this computer resolves names another way.'
        return info
    device = default_device()
    status = parse_resolvectl(run(['resolvectl', 'status'], check=False)) if caps.get('resolvectl', True) else {}
    link = status.get(device) or {}
    info['link'] = device
    info['servers'] = link.get('servers', [])
    info['provider'] = provider_for(info['servers'])
    info['providerLabel'] = DOT_PROVIDERS.get(info['provider'], {}).get('label', 'Your network' if info['provider'] == 'network' else 'Custom')
    connection = active_connection(device)
    if connection and caps['networkManager']:
        try:
            fields = nm_fields(connection['uuid'], DNS_FIELDS)
            connection.update(dict(dnsOverTls=fields['connection.dns-over-tls'], dns=fields['ipv4.dns'], ignoreAutoDns=fields['ipv4.ignore-auto-dns']))
        except RuntimeError as error:
            connection['error'] = str(error)
    info['connection'] = connection
    if link.get('dot'):
        info['mode'] = 'strict' if (connection or {}).get('dnsOverTls') == 'yes' else 'opportunistic'
    if not connection:
        info['reason'] = 'No active NetworkManager connection carries the default route.'
    return info


def apply_dns(request, caps):
    """Capture → modify the connection → reapply → verify through resolved → roll back."""
    mode, provider = request.get('mode', 'off'), request.get('provider', 'cloudflare')
    if mode not in ('off', 'opportunistic', 'strict') or (mode != 'off' and provider not in DOT_PROVIDERS):
        raise ValueError('Unknown DNS request.')
    if not caps['dotSupported']:
        raise RuntimeError('DNS-over-TLS is not supported by the current resolver.')
    device = default_device()
    connection = active_connection(device)
    if not connection:
        raise RuntimeError('No active NetworkManager connection to configure.')
    uuid = connection['uuid']
    captured = nm_fields(uuid, DNS_FIELDS)

    def modify(values):
        argv = ['nmcli', 'connection', 'modify', uuid]
        for key, value in values.items():
            argv += [key, value]
        run(argv)
        out = run(['nmcli', 'device', 'reapply', device], check=False)
        if 'successfully' not in out.lower():
            run(['nmcli', 'connection', 'up', uuid], timeout=45)

    if mode == 'off':
        wanted = {'connection.dns-over-tls': 'default', 'ipv4.dns': '', 'ipv4.ignore-auto-dns': 'no', 'ipv6.dns': '', 'ipv6.ignore-auto-dns': 'no'}
    else:
        spec = DOT_PROVIDERS[provider]
        wanted = {'connection.dns-over-tls': 'yes' if mode == 'strict' else 'opportunistic',
                  'ipv4.dns': ','.join(spec['v4']), 'ipv4.ignore-auto-dns': 'yes', 'ipv6.dns': ','.join(spec['v6']), 'ipv6.ignore-auto-dns': 'yes'}
    modify(wanted)
    verified = dns(caps)
    ok = (mode == 'off' and verified['mode'] == 'off') or (mode != 'off' and verified['mode'] != 'off' and verified['provider'] == provider)
    if not ok:
        restore = {k: (v if v not in ('', '-1') else ('default' if k == 'connection.dns-over-tls' else v)) for k, v in captured.items()}
        try:
            modify(restore)
        except RuntimeError as error:
            raise RuntimeError('Encrypted DNS did not verify and the previous settings could not be restored: ' + str(error))
        raise RuntimeError('Encrypted DNS did not verify through systemd-resolved; the previous DNS settings were restored.')
    return verified


# ---------------------------------------------------------------------- wifi
def wifi_profile():
    device = None
    for line in run(['nmcli', '-t', '-f', 'DEVICE,TYPE,STATE,CONNECTION', 'device', 'status'], check=False).splitlines():
        parts = line.split(':')
        if len(parts) >= 4 and parts[1] == 'wifi':
            device = dict(device=parts[0], state=parts[2], connection=parts[3])
            break
    if not device:
        return dict(available=False, reason='No Wi-Fi device.')
    name = device['connection']
    if not name:
        rows = []
        for line in run(['nmcli', '-t', '-f', 'NAME,TYPE,TIMESTAMP', 'connection', 'show'], check=False).splitlines():
            parts = line.split(':')
            if len(parts) >= 3 and parts[1] == '802-11-wireless':
                rows.append((int(parts[2] or 0), parts[0]))
        name = max(rows)[1] if rows else ''
    info = dict(available=True, device=device['device'], connected=device['state'] == 'connected', connection=name, policy='default', raw='')
    if not name:
        info['reason'] = 'No Wi-Fi network saved yet; the policy applies once one is.'
        return info
    raw = nm_fields(name, ['802-11-wireless.cloned-mac-address']).get('802-11-wireless.cloned-mac-address', '')
    info['raw'] = raw
    info['policy'] = {v: k for k, v in MAC_POLICIES.items()}.get(raw, 'default' if raw in ('', 'preserve') else 'custom')
    return info


def apply_wifi(request):
    policy = request.get('policy')
    if policy not in MAC_POLICIES:
        raise ValueError('Unknown address policy.')
    before = wifi_profile()
    if not before.get('available') or not before.get('connection'):
        raise RuntimeError(before.get('reason', 'No Wi-Fi profile to change.'))
    run(['nmcli', 'connection', 'modify', before['connection'], '802-11-wireless.cloned-mac-address', MAC_POLICIES[policy]])
    after = wifi_profile()
    if after.get('policy') != policy:
        run(['nmcli', 'connection', 'modify', before['connection'], '802-11-wireless.cloned-mac-address', before.get('raw') or 'preserve'], check=False)
        raise RuntimeError('The address policy did not verify; the previous policy was restored.')
    if after.get('connected'):
        after['note'] = 'Applies the next time this network connects.'
    return after


# ------------------------------------------------------------------ firewall
def firewall_commands(provider, enable):
    if provider == 'ufw':
        return ['/bin/sh', '-c', 'ufw --force enable && systemctl enable --now ufw.service' if enable else 'ufw disable && systemctl disable --now ufw.service']
    if provider == 'firewalld':
        return ['systemctl', 'enable' if enable else 'disable', '--now', 'firewalld.service']
    if provider == 'nftables':
        return ['systemctl', 'enable' if enable else 'disable', '--now', 'nftables.service']
    raise RuntimeError('No firewall manager is installed. Install ufw, firewalld or nftables first.')


def apply_firewall(request):
    enable = bool(request.get('enable'))
    before = capabilities.firewall()
    provider = before['provider']
    if provider == 'nftables' and not any(f['configured'] for f in before['providers'] if f['provider'] == 'nftables'):
        raise RuntimeError('nftables has no ruleset at /etc/nftables.conf to enable.')
    priv = capabilities.privilege()
    if priv['helper'] != 'pkexec':
        raise RuntimeError('pkexec is not installed, so the firewall cannot be changed from here.')
    if not priv['agent']:
        raise RuntimeError('No authentication agent is running to ask for permission. Start a polkit agent and try again.')
    argv = ['pkexec'] + firewall_commands(provider, enable)
    try:
        run(argv, timeout=120)
    except RuntimeError as error:
        text = str(error)
        if 'dismissed' in text.lower() or 'not authorized' in text.lower() or 'request dismissed' in text.lower():
            raise RuntimeError('Permission was not granted; the firewall was left as it was.')
        raise
    after = capabilities.firewall()
    if after['active'] != enable:
        run(['pkexec'] + firewall_commands(provider, not enable), timeout=120, check=False)
        raise RuntimeError(('Firewall could not be enabled' if enable else 'Firewall could not be disabled') + ': ' + provider + ' did not report the new state, so it was put back.')
    return after


# ------------------------------------------------------------------ snapshot
def snapshot(exposure_scan=True):
    caps = capabilities.snapshot()
    data = dict(firewall=caps['firewall'], dns=dns(caps['dns']), privilege=caps['privilege'])
    try:
        data['wifi'] = wifi_profile() if caps['network']['nmcli'] else dict(available=False, reason='NetworkManager is not running.')
    except RuntimeError as error:
        data['wifi'] = dict(available=False, reason=str(error))
    if exposure_scan:
        data['exposure'] = exposure()
    return data


def main():
    try:
        request = json.loads(sys.stdin.readline() or '{}')
        action = request.get('action', 'snapshot')
        if action == 'snapshot':
            data = snapshot()
        elif action == 'exposure':
            data = dict(exposure=exposure())
        elif action == 'firewall':
            apply_firewall(request); data = snapshot(exposure_scan=False)
        elif action == 'dns':
            apply_dns(request, capabilities.dns()); data = snapshot(exposure_scan=False)
        elif action == 'wifi':
            apply_wifi(request); data = snapshot(exposure_scan=False)
        else:
            raise ValueError('Unknown Shield action.')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:  # noqa: BLE001
        print(json.dumps(dict(ok=False, error=str(error))))


if __name__ == '__main__':
    main()
