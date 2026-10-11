#!/usr/bin/env python3
"""Read-only process and per-core samples for Field Station; no command lines or signals."""
import argparse
import json
import os
from pathlib import Path
import pwd
import time


class Sampler:
    def __init__(self, proc=Path('/proc'), clock=time.monotonic, hz=None, page_size=None):
        self.proc = Path(proc)
        self.clock = clock
        self.hz = hz or os.sysconf('SC_CLK_TCK')
        self.page_size = page_size or os.sysconf('SC_PAGE_SIZE')
        self.previous = {}
        self.cores = {}
        self.at = None
        self.users = {}

    def sample(self):
        now = self.clock()
        elapsed = now - self.at if self.at is not None else 0
        cores, next_cores = [], {}
        for line in (self.proc / 'stat').read_text().splitlines():
            fields = line.split()
            if not fields or not fields[0].startswith('cpu') or fields[0] == 'cpu':
                continue
            ticks = [int(v) for v in fields[1:9]]
            if len(ticks) < 5:
                continue
            total, idle = sum(ticks), ticks[3] + ticks[4]
            old = self.cores.get(fields[0])
            usage = None
            if old and total > old[0]:
                usage = round(max(0, min(100, 100 * (1 - (idle - old[1]) / (total - old[0])))), 1)
            next_cores[fields[0]] = (total, idle)
            cores.append({'name': fields[0], 'cpu': usage})
        rows, previous = [], {}
        for directory in self.proc.iterdir():
            if not directory.name.isdecimal():
                continue
            try:
                raw = (directory / 'stat').read_text()
                # comm can contain spaces and parentheses; fields follow the final ')'.
                end = raw.rindex(')')
                name = raw[raw.index('(') + 1:end][:160]
                fields = raw[end + 2:].split()
                pid, start = int(directory.name), int(fields[19])
                ticks = int(fields[11]) + int(fields[12])
                uid = directory.stat().st_uid
                if uid not in self.users:
                    try:
                        self.users[uid] = pwd.getpwuid(uid).pw_name
                    except KeyError:
                        self.users[uid] = str(uid)
                key = (pid, start)
                old = self.previous.get(key)
                cpu = None if old is None or elapsed <= 0 or ticks < old else round(100 * (ticks - old) / self.hz / elapsed, 1)
                previous[key] = ticks
                rows.append({'pid': pid, 'start': str(start), 'name': name, 'user': self.users[uid],
                             'state': fields[0], 'cpu': cpu, 'rss': max(0, int(fields[21])) * self.page_size,
                             'threads': int(fields[17])})
            except (OSError, ValueError, IndexError):
                # Processes may exit, become unreadable or be replaced during enumeration.
                continue
        self.at, self.previous, self.cores = now, previous, next_cores
        rows.sort(key=lambda p: (-(p['cpu'] or 0), -p['rss'], p['pid']))
        return {'processes': rows[:4096], 'total': len(rows), 'omitted': max(0, len(rows) - 4096),
                'cores': cores, 'sampledAt': time.time(), 'interval': elapsed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    args = parser.parse_args()
    sampler = Sampler()
    gpus, gpu_at, gpu_error = [], -10, ''
    while True:
        started = time.monotonic()
        try:
            data = sampler.sample()
            if started - gpu_at >= 10:
                try:
                    from performance import snapshot
                    gpus, gpu_error = snapshot().get('gpus', []), ''
                except Exception:
                    gpus, gpu_error = [], 'GPU readings are unavailable.'
                gpu_at = started
            data.update(gpus=gpus, gpuError=gpu_error)
            print(json.dumps({'ok': True, 'data': data}, allow_nan=False), flush=True)
        except (OSError, ValueError) as error:
            print(json.dumps({'ok': False, 'error': 'Process readings are unavailable: ' + str(error)}), flush=True)
        if not args.watch:
            break
        time.sleep(max(.1, 2 - (time.monotonic() - started)))


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
