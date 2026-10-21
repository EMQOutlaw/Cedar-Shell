#!/usr/bin/env python3
"""Isolated real-QML surface lifecycle benchmark, with test-mode backend fixtures.

Does not replace/reload the installed shell. --native opens a disposable window;
otherwise Qt software/offscreen is used. Neither certifies full-shell/GPU budget.
"""
import argparse
import bisect
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import measure_resources as measure
import distribution as distribution

HARNESS = '''
import QtQuick
import Quickshell
import "."
import "services"
ShellRoot {
    settings.watchFiles: false
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 960; implicitHeight: 800
        color: Theme.background
        property int count: 0
        property int total: Number(Quickshell.env("CEDAR_BENCH_CYCLES"))
        property bool opened: false
        property bool finished: false
        property var topics: ["quick", "audio", "network", "bluetooth", "power", "weather", "calendar", "clipboard", "notifications", "trails", "station", "go", "startup", "workspaces", "keybinds"]
        property var extras: ["modules/FieldStation.qml", "components/core/CoreHub.qml", "modules/ShieldPages.qml", "modules/ProfilesPages.qml", "modules/StationPages.qml"]
        property int baselinePulse: 0
        property int baselineWindows: 0
        Loader { id: content; anchors.fill: parent; active: false }
        function mark(phase, feature) { console.log("CEDAR_BENCH " + JSON.stringify({phase: phase, feature: feature || "", cycle: count, at: Date.now()})); }
        function fail(message) { console.error("FAIL: " + message); Qt.exit(1); }
        Timer {
            interval: 1000; running: true
            onTriggered: {
                window.baselinePulse = Pulse.demand;
                window.baselineWindows = Canopy.controlWindows.length;
                window.mark("ready"); cycle.start();
            }
        }
        Timer {
            id: cycle
            interval: Number(Quickshell.env("CEDAR_BENCH_HOLD_MS")); repeat: true
            onTriggered: {
                if (window.opened) {
                    content.active = false; Canopy.close(); CoreService.collapse();
                    window.opened = false; window.count++;
                    if (Pulse.demand !== window.baselinePulse) window.fail("Visualizer demand retained after close");
                    if (Canopy.controlWindows.length !== window.baselineWindows) window.fail("Window registry grew");
                    window.mark("closed");
                    if (window.count >= window.total) {
                        stop(); window.finished = true; settle.start();
                    }
                    return;
                }
                const i = window.count % (window.topics.length + window.extras.length);
                let source, props = {}, feature;
                if (i < window.topics.length) {
                    feature = window.topics[i]; Canopy.open(feature);
                    source = "modules/CanopyPanel.qml"; props = { active: true };
                } else {
                    source = window.extras[i-window.topics.length]; feature = source;
                    if (source.indexOf("FieldStation") >= 0) props = {active: true};
                }
                // Exercise both responsive sizes and ordinary/reduced motion settings.
                window.implicitWidth = window.count % 2 ? 480 : 960;
                Config.saved.reducedMotion = Math.floor(window.count / 20) % 2 === 1;
                content.setSource(Qt.resolvedUrl(source), props); content.active = true;
                if (content.status === Loader.Error || !content.item) window.fail("Cannot load " + source);
                window.opened = true; window.mark("open", feature);
            }
        }
        Timer {
            id: settle; interval: Number(Quickshell.env("CEDAR_BENCH_SETTLE_MS"))
            onTriggered: { window.mark("settled"); console.log("PASS: isolated surface lifecycle benchmark"); Qt.quit(); }
        }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cycles', type=int, default=200)
    parser.add_argument('--hold-ms', type=int, default=300)
    parser.add_argument('--settle-seconds', type=int, default=10)
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.cycles <= 2000 or not 100 <= args.hold_ms <= 2000 or not 1 <= args.settle_seconds <= 600:
        parser.error('Bounded cycles/hold/settle required')
    args.output = args.output.absolute()
    distribution.private_directory(args.output.parent)
    with tempfile.TemporaryDirectory(prefix='cedar-surface-bench-') as directory:
        base = Path(directory)
        source = base / 'source'
        shutil.copytree(args.source.resolve(), source, ignore=shutil.ignore_patterns('.git', '.local', '__pycache__', 'runtime.log'))
        (source / 'audit-surface.qml').write_text(HARNESS)
        for name in ('runtime', 'config', 'state', 'cache', 'data'):
            (base / name).mkdir(mode=0o700)
        env = {**os.environ, 'CEDAR_TEST': '1', 'CEDAR_LOCAL_ONLY': '1', 'CEDAR_ADAPTER': 'hyprland',
               'QT_FORCE_STDERR_LOGGING': '1', 'QT_QPA_PLATFORM': 'wayland' if args.native else 'offscreen',
               'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QPA_PLATFORMTHEME': 'basic',
               'CEDAR_BENCH_CYCLES': str(args.cycles), 'CEDAR_BENCH_HOLD_MS': str(args.hold_ms),
               'CEDAR_BENCH_SETTLE_MS': str(args.settle_seconds * 1000),
               **{'XDG_' + name.upper() + '_HOME': str(base / name) for name in ('config', 'state', 'cache', 'data')}}
        if not args.native:
            env.update(XDG_RUNTIME_DIR=str(base / 'runtime'), QT_QUICK_BACKEND='software', QSG_RENDER_LOOP='basic')
            env.pop('QSG_RHI_BACKEND', None)
        log = base / 'runtime.log'
        samples = []
        started = time.monotonic()
        wall_started = time.time() * 1000
        with log.open('w') as output:
            process = subprocess.Popen(['qs', '-p', str(source / 'audit-surface.qml'), '--no-color'],
                                       env=env, stdout=output, stderr=output, start_new_session=True)
            try:
                identity = measure.stat_fields(Path(f'/proc/{process.pid}/stat').read_text())['start']
                roots = {process.pid: identity}
                previous = measure.snapshot(roots)
                tracked = set(previous)
                last = started
                deadline = started + args.cycles * args.hold_ms / 500 + args.settle_seconds + 40
                while process.poll() is None:
                    if time.monotonic() > deadline:
                        raise RuntimeError('Surface benchmark exceeded its deadline')
                    time.sleep(.2)
                    current = measure.snapshot(roots, tracked=tracked)
                    now = time.monotonic()
                    if process.poll() is not None:
                        break
                    sample = measure.compare(previous, current, now-last, os.sysconf('SC_CLK_TCK'))
                    sample.update(elapsedSeconds=now-started, processesDetail=list(current.values()))
                    samples.append(sample)
                    tracked.update(current)
                    previous, last = current, now
                code = process.wait(timeout=3)
            finally:
                # Only this benchmark's private process group is terminated.
                try: os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError: pass
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait()
        text = log.read_text()
        events = []
        for line in text.splitlines():
            if 'CEDAR_BENCH ' in line:
                events.append(json.loads(line.split('CEDAR_BENCH ', 1)[1]))
        errors = [line for line in text.splitlines() if re.search(r'FAIL:|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|Failed to load configuration', line)]
        warnings = [line for line in text.splitlines() if re.search(r'\bWARN\b|\bERROR\b', line)]
        passed = code == 0 and not errors and 'PASS: isolated surface lifecycle benchmark' in text
        event_times = [(e['at'] - wall_started) / 1000 for e in events]
        for sample in samples:
            index = bisect.bisect_right(event_times, sample['elapsedSeconds']) - 1
            event = events[index] if index >= 0 else {}
            sample['phase'] = event.get('phase', 'startup')
            sample['cycle'] = event.get('cycle', 0)
        warm_closed = [s for s in samples if s['phase'] == 'closed' and s['cycle'] >= 20]
        ready = next((e for e in events if e['phase'] == 'ready'), None)
        report = {'format': 1, 'workload': 'isolated production surfaces with test-mode backends',
                  'source': str(args.source.resolve()), 'renderer': 'native Wayland' if args.native else 'software/offscreen',
                  'cycles': args.cycles, 'holdMs': args.hold_ms, 'settleSeconds': args.settle_seconds,
                  'passed': passed, 'exitCode': code, 'errorCount': len(errors), 'warningLineCount': len(warnings),
                  'errors': errors, 'events': events, 'samples': samples,
                  'summary': measure.summarize(samples, 500_000_000),
                  'closedAfterFirstSweep': measure.summarize(warm_closed, 500_000_000),
                  'timeToHarnessReadySeconds': (ready['at'] - wall_started) / 1000 if ready else None,
                  'limitations': 'Not full shell, live backends, real monitor hotplug, frame timing, or whole-desktop acceptance.'}
        distribution.write_json(args.output, report)
        distribution.atomic(args.output.with_suffix('.log'), text.encode())
        print(json.dumps({k: report[k] for k in ('passed', 'cycles', 'errorCount', 'warningLineCount', 'summary')}, indent=2))
        return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
