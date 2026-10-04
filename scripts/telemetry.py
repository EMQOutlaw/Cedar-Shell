#!/usr/bin/env python3
"""Bounded, read-only telemetry for Quickshell Process. No shell interpolation."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request


def run(argv, timeout=3):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False,
                           env={**os.environ, 'LC_ALL': 'C'})
        return p.stdout.strip() if p.returncode == 0 else ''
    except (OSError, subprocess.TimeoutExpired):
        return ''


def stats(path):
    cpu = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:9]))
    mem = dict((k, int(v)) for k, v in re.findall(r'^(\w+):\s+(\d+)', Path('/proc/meminfo').read_text(), re.M))
    disk = shutil.disk_usage(path)
    net = [line.split(':',1) for line in Path('/proc/net/dev').read_text().splitlines()[2:] if ':' in line]
    counters = [fields.split() for name,fields in net if name.strip()!='lo']
    return dict(netBytes=sum(int(v[0])+int(v[8]) for v in counters), total=sum(cpu), idle=cpu[3] + cpu[4],
                ram=1 - mem['MemAvailable']/mem['MemTotal'],
                ramUsed=(mem['MemTotal']-mem['MemAvailable'])/1048576,
                ramTotal=mem['MemTotal']/1048576,
                disk=disk.used/disk.total, uptime=float(Path('/proc/uptime').read_text().split()[0]))


def temperatures():
    raw = run(['sensors', '-j'])
    values = []
    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if re.fullmatch(r'temp\d+_input', key) and isinstance(value, (float, int)) and -20 < value < 150:
                    values.append(value)
                else:
                    walk(value)
    try:
        walk(json.loads(raw))
    except ValueError:
        pass
    return dict(temperature=max(values) if values else None)


def network():
    devices = run(['nmcli', '-t', '-f', 'TYPE,STATE', 'device', 'status'])
    active = [line.split(':')[0] for line in devices.splitlines() if line.endswith(':connected')]
    if 'ethernet' in active:
        return dict(label='ETH online')
    if 'wifi' in active:
        rows = run(['nmcli', '-t', '-f', 'IN-USE,SIGNAL,FREQ', 'device', 'wifi', 'list', '--rescan', 'no'])
        for row in rows.splitlines():
            if row.startswith('*:'):
                fields = row.split(':')
                freq = int(re.sub(r'\D', '', fields[2]) or 0)
                band = '6 GHz' if freq >= 5925 else '5 GHz' if freq >= 4900 else '2.4 GHz'
                return dict(label=f'WI-FI {band} {fields[1]}%')
        return dict(label='WI-FI online')
    if any(t in active for t in ('gsm', 'cdma')):
        try:
            modems = json.loads(run(['mmcli', '-L', '-J'])).get('modem-list', [])
            for modem in modems:
                generic = json.loads(run(['mmcli', '-m', modem, '-J']))['modem']['generic']
                if generic.get('state') != 'connected':
                    continue
                tech = generic.get('access-technologies', [])
                if isinstance(tech, str): tech = [tech]
                label = '5G' if any('5gnr' in t.lower() for t in tech) else '/'.join(tech).upper() or 'CELL'
                signal = generic.get('signal-quality', {}).get('value', '?')
                return dict(label=f'{label} {signal}%')
        except (ValueError, KeyError, TypeError):
            pass
        return dict(label='CELL online')
    return dict(label='NET offline' if devices else 'NET unavailable')


def brightness(device, delta=0):
    args = ['brightnessctl'] + (['-d', device] if device else ['-c', 'backlight'])
    if delta:
        change = f'{abs(delta)}%+' if delta > 0 else f'{abs(delta)}%-'
        if not run(args + ['--min-value=1', 'set', change]):
            return dict(value=None, error='Brightness change failed')
    output = run(args + ['-m'])
    try:
        return dict(value=int(output.splitlines()[0].split(',')[3].rstrip('%'))/100)
    except (ValueError, IndexError):
        return dict(value=None, error='No writable backlight')


def weather(lat, lon, unit):
    lat, lon = float(lat), float(lon)
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError('Invalid coordinates')
    if unit not in ('celsius', 'fahrenheit'):
        raise ValueError('Invalid temperature unit')
    from network_policy import require
    require('weather')
    query = urllib.parse.urlencode(dict(latitude=lat, longitude=lon, current='temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
                                       temperature_unit=unit, timezone='auto', hourly='temperature_2m,precipitation_probability', daily='sunrise,sunset', forecast_days=2))
    request = urllib.request.Request('https://api.open-meteo.com/v1/forecast?' + query, headers={'User-Agent': 'cedar/1.0'})
    with urllib.request.urlopen(request, timeout=12) as response:
        data = json.load(response)
    return dict(current=data['current'], units=data['current_units'], hourly=data.get('hourly',{}), daily=data.get('daily',{}), utc_offset_seconds=data.get('utc_offset_seconds',0))


def main(args):
    kind = args[0]
    if kind == 'stats': return stats(args[1])
    if kind == 'temperature': return temperatures()
    if kind == 'network': return network()
    if kind == 'brightness': return brightness(args[1], int(args[2]) if len(args) > 2 else 0)
    if kind == 'weather': return weather(*args[1:4])
    raise ValueError('Unknown telemetry request')


if __name__ == '__main__':
    try:
        result = main(sys.argv[1:])
    except Exception as error:
        result = dict(error=str(error))
    print(json.dumps(result, allow_nan=False))
