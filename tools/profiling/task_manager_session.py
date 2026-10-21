#!/usr/bin/env python3
"""Read-only Task Manager workload with private settings and measured cleanup.

Build the native binaries first with scripts/build_task_manager.py. The default
uses an offscreen window. Optional --shell-pid includes an existing shell group
in the same samples; it is observed only, never stopped or reconfigured.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import distribution as d
import measure_resources as measure


def fixture_scope(samples, root_identity):
    """Remember observed fixture descendants even if they later reparent."""
    identities = {root_identity}
    valid = bool(samples)
    for sample in samples:
        rows = sample['processesDetail']
        while True:
            current_parents = {r['pid'] for r in rows if (r['pid'], r['start']) in identities}
            children = {(r['pid'], r['start']) for r in rows if r['parent'] in current_parents}
            if children <= identities:
                break
            identities |= children
        fixture = [r for r in rows if (r['pid'], r['start']) in identities]
        valid &= (any((r['pid'], r['start']) == root_identity for r in fixture)
                  and sum(r['name'] == 'cedar-taskd' for r in fixture) == 1)
    return identities, bool(valid)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--shell-pid', type=int, action='append', default=[])
    parser.add_argument('--seconds', type=int, default=30)
    args = parser.parse_args()
    if not 5 <= args.seconds <= 600:
        parser.error('Duration must be between 5 and 600 seconds')
    source = args.source.resolve()
    binary = next((p for p in (source / 'libexec/cedar-task-manager', source / '.local/task-manager/cedar-task-manager') if p.is_file()), None)
    if binary is None:
        parser.error('Native binaries missing; run python3 scripts/build_task_manager.py first')
    args.output = args.output.absolute()
    d.private_directory(args.output.parent)
    with tempfile.TemporaryDirectory(prefix='cedar-task-bench-') as directory:
        base = Path(directory)
        for name in ('runtime', 'config', 'state', 'cache', 'data'):
            (base / name).mkdir(mode=0o700)
        env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
               'QSG_RENDER_LOOP': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QPA_PLATFORMTHEME': 'basic',
               'HYPRLAND_INSTANCE_SIGNATURE': '', 'XDG_RUNTIME_DIR': str(base / 'runtime'),
               **{'XDG_' + name.upper() + '_HOME': str(base / name) for name in ('config', 'state', 'cache', 'data')}}
        env.pop('CEDAR_TASK_TEST_LOCAL_COLLECTOR', None)
        with (base / 'runtime.log').open('w') as log:
            child = subprocess.Popen([str(binary), '--source', str(source)], env=env,
                                     stdout=log, stderr=log, start_new_session=True)
            identities = set()
            completed_measurement = False
            try:
                start = measure.stat_fields(Path(f'/proc/{child.pid}/stat').read_text())['start']
                command = [sys.executable, str(ROOT / 'scripts/measure_resources.py'), '--pid', str(child.pid),
                           '--output', str(args.output), '--label', 'Task Manager active; explicit shell roots included if supplied',
                           '--warmup', '3', '--seconds', str(args.seconds), '--interval', '1', '--runs', '1', '--fail-on-budget']
                for pid in args.shell_pid:
                    command.extend(['--pid', str(pid)])
                measured = subprocess.run(command, capture_output=True, text=True, timeout=args.seconds + 20)
                if not args.output.is_file():
                    raise RuntimeError(measured.stdout + measured.stderr + (base / 'runtime.log').read_text())
                report = json.loads(args.output.read_text())
                identities, fixture_valid = fixture_scope(report['runs'][0]['samples'], (child.pid, start))
                if not fixture_valid:
                    for run in report['runs']:
                        summary = run['summary']
                        if summary['budgetStatus'] != 'exceeded':
                            summary['budgetStatus'] = 'unknown'
                identities.update(measure.snapshot({child.pid: start}, tracked=identities))
                completed_measurement = True
            finally:
                child.terminate()
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL); child.wait()
                if not completed_measurement:
                    try: os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
            deadline = time.monotonic() + 6
            survivors = []
            while time.monotonic() < deadline:
                survivors = []
                for pid, start in identities:
                    try:
                        if measure.stat_fields(Path(f'/proc/{pid}/stat').read_text())['start'] == start:
                            survivors.append(pid)
                    except (OSError, ValueError): pass
                if not survivors: break
                time.sleep(.1)
            sockets = list((base / 'runtime').rglob('*.sock'))
            if survivors:
                try: os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
            report['fixture'] = {'source': str(source), 'renderer': 'software/offscreen',
                                 'validRealCollectorWorkload': fixture_valid,
                                 'shellRootsIncluded': args.shell_pid, 'cleanupPassed': not survivors and not sockets,
                                 'survivorsAtDeadline': survivors, 'socketCountAfterClose': len(sockets),
                                 'limitations': 'Real read-only collector; no process actions, native rendering or full-shell replacement.'}
            d.write_json(args.output, report)
            d.atomic(args.output.with_suffix('.log'), (base / 'runtime.log').read_bytes())
            print(json.dumps({'summary': report['runs'][0]['summary'], 'fixture': report['fixture']}, indent=2))
            return measured.returncode if fixture_valid and not survivors and not sockets else 1


if __name__ == '__main__':
    raise SystemExit(main())
