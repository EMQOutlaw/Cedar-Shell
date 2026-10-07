#!/usr/bin/env python3
"""Discover, once, which providers this host offers for CEDAR's system services.

Read-only. One JSON reply on stdout: {"ok": true, "data": {...}}. Nothing here
needs privileges; each probe inspects installed binaries, unit files, systemd
state and readable configuration. The shell caches the result and asks again
only on an explicit refresh or when a provider's unit changes state.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ETC = Path('/etc')


def run(argv, timeout=6):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False,
                           env={**os.environ, 'LC_ALL': 'C'})
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 127, ''


def unit_state(unit, user=False):
    """(active, enabled) for a systemd unit; "not-found" when it does not exist."""
    base = ['systemctl', '--user'] if user else ['systemctl']
    _, active = run(base + ['is-active', unit])
    _, enabled = run(base + ['is-enabled', unit])
    return active or 'unknown', enabled or 'unknown'


def read(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ''


def firewall():
    """The firewall manager that owns this host, in the order a real system is
    inspected: a running firewalld, then UFW, then a plain nftables ruleset
    service. An existing configuration is authoritative; CEDAR never starts a
    second manager beside it."""
    found = []
    if shutil.which('firewall-cmd') or Path('/usr/lib/systemd/system/firewalld.service').exists():
        active, enabled = unit_state('firewalld.service')
        found.append(dict(provider='firewalld', active=active == 'active', enabled=enabled == 'enabled', unit='firewalld.service',
                          configured=(ETC / 'firewalld/firewalld.conf').exists()))
    if shutil.which('ufw'):
        active, enabled = unit_state('ufw.service')
        conf = read(ETC / 'ufw/ufw.conf')
        found.append(dict(provider='ufw', active=active == 'active', enabled=enabled == 'enabled', unit='ufw.service',
                          configured=bool(re.search(r'^ENABLED=yes', conf, re.M))))
    if shutil.which('nft'):
        active, enabled = unit_state('nftables.service')
        found.append(dict(provider='nftables', active=active == 'active', enabled=enabled == 'enabled', unit='nftables.service',
                          configured=(ETC / 'nftables.conf').exists()))
    # Owner: a manager that is active or configured wins, in detection order;
    # otherwise the first installed one is offered as the thing to enable.
    owner = next((f for f in found if f['active']), None) or next((f for f in found if f['configured'] or f['enabled']), None)
    offered = owner or (found[0] if found else None)
    return dict(available=bool(found), providers=found, provider=offered['provider'] if offered else 'none',
                owner=owner['provider'] if owner else 'none', unit=offered['unit'] if offered else '',
                active=bool(owner and owner['active']), competing=len([f for f in found if f['active']]) > 1)


def dns():
    """Who answers the system resolver, and whether it can speak DNS-over-TLS.
    systemd-resolved does (per link, driven by NetworkManager's connection
    settings); a static resolv.conf or NetworkManager's own dnsmasq cannot."""
    resolved_active, _ = unit_state('systemd-resolved.service')
    try:
        target = os.readlink('/etc/resolv.conf')
    except OSError:
        target = ''
    stub = 'stub-resolv.conf' in target or 'systemd/resolve' in target
    nm_active, _ = unit_state('NetworkManager.service')
    resolver = 'systemd-resolved' if resolved_active == 'active' and stub else 'NetworkManager' if nm_active == 'active' else 'static'
    return dict(resolver=resolver, resolvedActive=resolved_active == 'active', stub=stub, networkManager=nm_active == 'active',
                dotSupported=resolver == 'systemd-resolved' and nm_active == 'active' and bool(shutil.which('nmcli')),
                dohSupported=False, resolvectl=bool(shutil.which('resolvectl')))


def gaming():
    """Feral GameMode: a user service with a D-Bus name. Observed, never driven."""
    installed = bool(shutil.which('gamemoded'))
    active, _ = unit_state('gamemoded.service', user=True) if installed else ('inactive', 'unknown')
    return dict(gameModeAvailable=installed, gameModeRunning=active == 'active', gameModeRun=bool(shutil.which('gamemoderun')),
                hyprctl=bool(shutil.which('hyprctl')), systemdInhibit=bool(shutil.which('systemd-inhibit')))


def gpu():
    vendor, tool, path = 'unknown', 'none', ''
    for card in sorted(Path('/sys/class/drm').glob('card[0-9]*/device')):
        vid = read(card / 'vendor').strip().lower()
        vendor = {'0x10de': 'nvidia', '0x1002': 'amd', '0x8086': 'intel'}.get(vid, vendor)
        if vendor != 'unknown':
            path = str(card); break
    if vendor == 'nvidia' and shutil.which('nvidia-smi'):
        tool = 'nvidia-smi'
    elif path and (Path(path) / 'gpu_busy_percent').exists():
        tool = 'sysfs'
    return dict(vendor=vendor, tool=tool, supportsUtilization=tool != 'none', supportsTemperature=tool == 'nvidia-smi' or bool(path and list(Path(path).glob('hwmon/hwmon*/temp1_input'))),
                supportsPerformancePolicy=False, supportsPowerStateObservation=tool != 'none')


def power():
    ppd_active, _ = unit_state('power-profiles-daemon.service')
    tuned_active, _ = unit_state('tuned.service')
    provider = 'power-profiles-daemon' if ppd_active == 'active' and shutil.which('powerprofilesctl') else 'tuned' if tuned_active == 'active' else 'none'
    return dict(provider=provider, profiles=bool(provider != 'none'))


def privilege():
    agent = False
    code, out = run(['pgrep', '-f', 'polkit.*agent|hyprpolkitagent|polkit-gnome|polkit-kde|lxpolkit|mate-polkit|xfce-polkit'])
    agent = code == 0 and bool(out)
    return dict(helper='pkexec' if shutil.which('pkexec') else 'none', agent=agent)


def distro():
    release = dict(re.findall(r'^(\w+)=\"?([^\"\n]*)\"?$', read('/etc/os-release'), re.M))
    manager = next((m for m in ('pacman', 'apt', 'dnf', 'zypper', 'xbps-install', 'nix-env') if shutil.which(m)), 'unknown')
    return dict(id=release.get('ID', 'unknown'), name=release.get('PRETTY_NAME', release.get('NAME', 'Linux')), packageManager=manager)


def network():
    nm_active, _ = unit_state('NetworkManager.service')
    return dict(networkManager=nm_active == 'active', nmcli=bool(shutil.which('nmcli')),
                bluetooth=unit_state('bluetooth.service')[0] == 'active')


def snapshot():
    return dict(firewall=firewall(), dns=dns(), gaming=gaming(), gpu=gpu(), power=power(), privilege=privilege(),
                distro=distro(), network=network())


if __name__ == '__main__':
    try:
        sys.stdin.readline()  # one request line, ignored: there is only "snapshot"
    except OSError:
        pass
    try:
        print(json.dumps(dict(ok=True, data=snapshot())))
    except Exception as error:  # noqa: BLE001 - one reply, never a traceback on stdout
        print(json.dumps(dict(ok=False, error=str(error))))
