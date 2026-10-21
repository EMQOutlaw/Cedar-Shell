#!/usr/bin/env python3
"""Shield's system side: read the real protection state, change it through each
provider's own interface, verify, and roll back when verification fails.

One JSON request on stdin, one reply on stdout. Actions:
  snapshot                       every protection's current state (no privileges)
  firewall {enable}              the owning manager's native enable/disable via pkexec
  dns {mode, provider}           DNS-over-TLS on the active NetworkManager connection,
                                 served by systemd-resolved; captured, applied, verified
  wifi {policy}                  the Wi-Fi profile's MAC address policy (NetworkManager)
  ipv6 {enable}                  IPv6 privacy extensions on the active connection (NetworkManager)
  discovery {enable}             mDNS/LLMNR answering on the active connection (NetworkManager →
                                 systemd-resolved) and the Avahi daemon (pkexec)
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
OPERATION_ERRORS = (RuntimeError, OSError, subprocess.SubprocessError)
MANAGED_UNITS = {'avahi-daemon.service', 'avahi-daemon.socket', 'ufw.service', 'firewalld.service', 'nftables.service'}


def run(argv, timeout=20, check=True):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False, env={**os.environ, 'LC_ALL': 'C'})
    if check and p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or ' '.join(argv[:2]) + ' failed')
    return p.stdout


def requested_enable(request):
    value = request.get('enable')
    if not isinstance(value, bool):
        raise ValueError('enable must be a boolean.')
    return value


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
            # resolved prints "+DNSOverTLS" for strict, "DNSOverTLS=opportunistic"
            # for opportunistic and "-DNSOverTLS" for off.
            blocks[current]['dotMode'] = 'strict' if '+DNSOverTLS' in value or 'DNSOverTLS=yes' in value else 'opportunistic' if 'DNSOverTLS=opportunistic' in value else 'off'
            blocks[current]['dot'] = blocks[current]['dotMode'] != 'off'
            blocks[current]['dnssec'] = 'DNSSEC=yes' in value
            blocks[current]['mdns'] = '+mDNS' in value
            blocks[current]['llmnr'] = '+LLMNR' in value
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


def modify_connection(connection, values, device=''):
    """Apply one captured profile; reapply live settings only when requested."""
    argv = ['nmcli', 'connection', 'modify', connection]
    for key, value in values.items():
        argv.extend([key, value])
    run(argv)
    if device:
        try:
            run(['nmcli', 'device', 'reapply', device])
        except RuntimeError:
            run(['nmcli', 'connection', 'up', connection], timeout=45)


def restore_connection(connection, values, device=''):
    modify_connection(connection, values, device)
    if nm_fields(connection, list(values)) != values:
        raise RuntimeError('The restored connection profile did not verify.')


def recover_or_raise(label, failure, restore, restored_message='the previous settings were restored.'):
    try:
        restore()
    except OPERATION_ERRORS as error:
        raise RuntimeError(label + ' could not be applied and the previous settings could not be restored: ' + str(error)) from failure
    raise RuntimeError(label + ' could not be applied; ' + restored_message) from failure


def capture_units(units):
    """Only stable, reconstructable states may participate in a transaction."""
    states = {}
    for unit in units:
        if unit not in MANAGED_UNITS:
            raise ValueError('Unknown managed service.')
        active, enabled = capabilities.unit_state(unit)
        if enabled == 'not-found':
            continue
        if active not in ('active', 'inactive') or enabled not in ('enabled', 'disabled', 'static', 'indirect'):
            raise RuntimeError('Cannot safely change ' + unit + ' while its state is ' + active + '/' + enabled + '.')
        states[unit] = (active, enabled)
    return states


def restore_units(states):
    """Restore enablement and activity independently; check every affected unit."""
    errors = []
    def attempt(argv):
        try:
            run(['pkexec', 'systemctl', *argv], timeout=120)
        except OPERATION_ERRORS as error:
            errors.append(str(error))
    for unit, (_, enabled) in states.items():
        current = capabilities.unit_state(unit)
        if current[1] != enabled and enabled in ('enabled', 'disabled'):
            attempt(['enable' if enabled == 'enabled' else 'disable', unit])
    # Start first, then stop units that were inactive: dependencies may start
    # another unit, so completion is determined by the final state read.
    for wanted in ('active', 'inactive'):
        for unit, (active, _) in states.items():
            if active == wanted and capabilities.unit_state(unit)[0] != active:
                attempt(['start' if active == 'active' else 'stop', unit])
    for unit, before in states.items():
        if capabilities.unit_state(unit) != before:
            errors.append(unit + ' did not return to its captured active/enabled state')
    if errors:
        raise RuntimeError('; '.join(errors))


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
    info['mode'] = link.get('dotMode', 'off') if link else 'off'
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
    try:
        modify(wanted)
        verified = dns(caps)
        ok = (mode == 'off' and verified['mode'] == 'off') or (mode != 'off' and verified['mode'] == mode and verified['provider'] == provider)
        if not ok:
            raise RuntimeError('Encrypted DNS did not verify through systemd-resolved.')
    except (RuntimeError, OSError, subprocess.SubprocessError) as failure:
        # A successful profile write followed by a reapply/activation timeout
        # is still a change. Restore it when either application or verification
        # fails, not only when verification returns an unexpected value.
        restore = {k: (v if v not in ('', '-1') else ('default' if k == 'connection.dns-over-tls' else v)) for k, v in captured.items()}
        try:
            modify(restore)
            restored = nm_fields(uuid, DNS_FIELDS)
            restored = {k: (v if v not in ('', '-1') else ('default' if k == 'connection.dns-over-tls' else v)) for k, v in restored.items()}
            if restored != restore:
                raise RuntimeError('The restored connection profile did not verify.')
        except (RuntimeError, OSError, subprocess.SubprocessError) as error:
            raise RuntimeError('Encrypted DNS could not be applied and the previous settings could not be restored: ' + str(error)) from failure
        raise RuntimeError('Encrypted DNS could not be applied; the previous DNS settings were restored.') from failure
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
    field = '802-11-wireless.cloned-mac-address'
    try:
        modify_connection(before['connection'], {field: MAC_POLICIES[policy]})
        after = wifi_profile()
        if after.get('connection') != before['connection'] or after.get('policy') != policy:
            raise RuntimeError('The address policy did not verify on the selected profile.')
    except OPERATION_ERRORS as failure:
        recover_or_raise('Wi-Fi address policy', failure,
                         lambda: restore_connection(before['connection'], {field: before.get('raw', '')}))

    if after.get('connected'):
        after['note'] = 'Applies the next time this network connects.'
    return after


# -------------------------------------------------------------- ipv6 privacy
def ipv6_privacy(connection):
    """NetworkManager's ipv6.ip6-privacy on the connection: 2 prefers temporary
    addresses, 1 generates them but prefers public, 0 off, -1 the system
    default (then the kernel's use_tempaddr decides)."""
    if not connection:
        return dict(available=False, reason='No active connection.')
    value = nm_fields(connection['uuid'], ['ipv6.ip6-privacy']).get('ipv6.ip6-privacy', '-1')
    device = connection.get('device', '')
    kernel = ''
    try:
        kernel = Path('/proc/sys/net/ipv6/conf/' + device + '/use_tempaddr').read_text().strip() if device else ''
    except OSError:
        kernel = ''
    effective = value if value in ('0', '1', '2') else kernel or '0'
    return dict(available=True, setting=value, kernel=kernel, effective=effective, active=effective == '2', partial=effective == '1')


def apply_ipv6(request):
    enable = requested_enable(request)
    connection = active_connection(default_device())
    if not connection:
        raise RuntimeError('No active NetworkManager connection to configure.')
    before = nm_fields(connection['uuid'], ['ipv6.ip6-privacy'])
    before_live = ipv6_privacy(connection)
    def restore():
        restore_connection(connection['uuid'], before, connection['device'])
        restored = ipv6_privacy(connection)
        if before_live.get('kernel') and restored.get('kernel') != before_live['kernel']:
            raise RuntimeError('The restored live IPv6 privacy setting did not verify.')
    try:
        modify_connection(connection['uuid'], {'ipv6.ip6-privacy': '2' if enable else '0'}, connection['device'])
        after = ipv6_privacy(connection)
        if after['active'] != enable or (after.get('kernel') and after['kernel'] != ('2' if enable else '0')):
            raise RuntimeError('IPv6 privacy did not verify on the active connection.')
    except OPERATION_ERRORS as failure:
        recover_or_raise('IPv6 privacy', failure, restore)
    return after


# ------------------------------------------------------------------ discovery
def discovery(connection, link_block):
    """Whether this computer answers multicast name queries: resolved's mDNS and
    LLMNR responders on the link (NetworkManager's connection.mdns/llmnr) and
    the Avahi daemon. Answering is convenient at home and chatty elsewhere."""
    avahi = unit_state_pair('avahi-daemon.service')
    info = dict(available=True, avahi=avahi == 'active', mdns=None, llmnr=None, setting=dict(mdns='-1', llmnr='-1'))
    if link_block:
        info['mdns'] = bool(link_block.get('mdns')); info['llmnr'] = bool(link_block.get('llmnr'))
    if connection:
        fields = nm_fields(connection['uuid'], ['connection.mdns', 'connection.llmnr'])
        info['setting'] = dict(mdns=fields.get('connection.mdns', '-1'), llmnr=fields.get('connection.llmnr', '-1'))
    info['answering'] = bool(info['avahi'] or info['mdns'] or info['llmnr'])
    return info


def unit_state_pair(unit):
    return capabilities.unit_state(unit)[0]


def apply_discovery(request):
    enable = requested_enable(request)   # enable = answer queries; disable = quiet
    connection = active_connection(default_device())
    if not connection:
        raise RuntimeError('No active NetworkManager connection to configure.')
    before = nm_fields(connection['uuid'], ['connection.mdns', 'connection.llmnr'])
    units = capture_units(('avahi-daemon.socket', 'avahi-daemon.service')) if not enable else {}
    stop_avahi = any(active == 'active' or enabled == 'enabled' for active, enabled in units.values())
    if stop_avahi and capabilities.privilege()['helper'] != 'pkexec':
        raise RuntimeError('Avahi can answer and pkexec is not installed to stop it; nothing was changed.')
    def link_state():
        status = parse_resolvectl(run(['resolvectl', 'status']))
        link = status.get(connection['device'])
        if link is None:
            raise RuntimeError('The active resolver link is unavailable.')
        return link
    before_link = link_state()
    touched_units = False
    def restore():
        errors = []
        try:
            restore_connection(connection['uuid'], before, connection['device'])
            restored_link = link_state()
            if any(restored_link.get(key) != before_link.get(key) for key in ('mdns', 'llmnr')):
                raise RuntimeError('The restored resolver flags did not verify.')
        except OPERATION_ERRORS as error:
            errors.append(str(error))
        if touched_units:
            try:
                restore_units(units)
            except OPERATION_ERRORS as error:
                errors.append(str(error))
        if errors:
            raise RuntimeError('; '.join(errors))
    value = '2' if enable else '0'
    try:
        modify_connection(connection['uuid'], {'connection.mdns': value, 'connection.llmnr': value}, connection['device'])
        if stop_avahi:
            touched_units = True
            run(['pkexec', 'systemctl', 'disable', '--now', *units], timeout=120)
        after = discovery(connection, link_state())
        if after['answering'] != enable:
            raise RuntimeError('Network discovery did not verify.')
        if stop_avahi and any(capabilities.unit_state(unit)[0] != 'inactive'
                              or capabilities.unit_state(unit)[1] == 'enabled' for unit in units):
            raise RuntimeError('An Avahi unit can still answer or restart.')
        return after
    except OPERATION_ERRORS as failure:
        recover_or_raise('Network discovery', failure, restore)



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
    enable = requested_enable(request)
    before = capabilities.firewall()
    provider = before['provider']
    if provider == 'nftables' and not any(f['configured'] for f in before['providers'] if f['provider'] == 'nftables'):
        raise RuntimeError('nftables has no ruleset at /etc/nftables.conf to enable.')
    if capabilities.privilege()['helper'] != 'pkexec':
        raise RuntimeError('pkexec is not installed, so the firewall cannot be changed from here.')
    selected = next((row for row in before['providers'] if row['provider'] == provider), None)
    if selected is None:
        raise RuntimeError('The selected firewall manager is unavailable.')
    unit = {'ufw': 'ufw.service', 'firewalld': 'firewalld.service', 'nftables': 'nftables.service'}[provider]
    units = capture_units((unit,))
    if unit not in units:
        raise RuntimeError('The selected firewall service is unavailable.')
    def selected_state():
        snapshot = capabilities.firewall()
        row = next((row for row in snapshot['providers'] if row['provider'] == provider), None)
        if row is None:
            raise RuntimeError('The selected firewall manager disappeared.')
        return snapshot, row
    def restore():
        errors = []
        # UFW's persisted ENABLED flag is independent of systemd's enablement.
        # Attempt unit restoration even if its native rules command fails.
        if provider == 'ufw':
            try:
                _, current = selected_state()
                if current['configured'] != selected['configured']:
                    run(['pkexec', 'ufw', *(['--force', 'enable'] if selected['configured'] else ['disable'])], timeout=120)
            except OPERATION_ERRORS as error:
                errors.append(str(error))
        try:
            restore_units(units)
        except OPERATION_ERRORS as error:
            errors.append(str(error))
        try:
            _, current = selected_state()
            if any(current[key] != selected[key] for key in ('active', 'enabled', 'configured')):
                errors.append('The firewall did not return to its captured configuration')
        except OPERATION_ERRORS as error:
            errors.append(str(error))
        if errors:
            raise RuntimeError('; '.join(errors))
    try:
        run(['pkexec'] + firewall_commands(provider, enable), timeout=120)
        after, current = selected_state()
        expected = ('active', 'enabled') if enable else ('inactive', 'disabled')
        if current['active'] != enable or capabilities.unit_state(unit) != expected or (provider == 'ufw' and current['configured'] != enable):
            raise RuntimeError('The selected firewall did not report the requested active/enabled state.')
        return after
    except OPERATION_ERRORS as failure:
        recover_or_raise('Firewall', failure, restore,
                         'the previous firewall service state was restored. Runtime-only rules could not be verified; review the firewall rules before relying on this protection.')



# ------------------------------------------------------------------ snapshot
def snapshot(exposure_scan=True):
    import time
    caps = capabilities.snapshot()
    data = dict(firewall=caps['firewall'], dns=dns(caps['dns']), privilege=caps['privilege'], verifiedAt=time.time())
    device = default_device()
    connection = active_connection(device) if caps['network']['nmcli'] else None
    data['connection'] = connection
    try:
        data['ipv6'] = ipv6_privacy(connection) if connection else dict(available=False, reason='No active connection.')
    except RuntimeError as error:
        data['ipv6'] = dict(available=False, reason=str(error))
    try:
        link = parse_resolvectl(run(['resolvectl', 'status'], check=False)).get(device) if caps['dns'].get('resolvectl') else None
        data['discovery'] = discovery(connection, link or {})
    except RuntimeError as error:
        data['discovery'] = dict(available=False, reason=str(error))
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
        elif action == 'ipv6':
            apply_ipv6(request); data = snapshot(exposure_scan=False)
        elif action == 'discovery':
            apply_discovery(request); data = snapshot(exposure_scan=False)
        else:
            raise ValueError('Unknown Shield action.')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:  # noqa: BLE001
        print(json.dumps(dict(ok=False, error=str(error))))


if __name__ == '__main__':
    main()
