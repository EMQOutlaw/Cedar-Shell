#!/usr/bin/env python3
"""Opt-in, read-only process-group accounting. Never launch or stop providers.

Explicit roots include descendants; exact cgroups and source roots also capture
separately launched CEDAR helpers. Brain requires explicit inclusion. CPU means
percent of one logical CPU. PSS, not RSS sum or cgroup memory, is the budget.
"""
import argparse
import json
import math
import os
from pathlib import Path
import statistics
import time
import distribution as d


# These are developer tools, not shell services. Keep this narrow: for example
# the installer and native build helper are real costs during an update.
DIAGNOSTIC_SCRIPTS = frozenset({'measure_resources.py', 'audit_resources.py', 'audit_public.py',
                              'smoke.py', 'benchmark_release_validation.py'})
SAMPLER_ROOT = Path(__file__).resolve().parents[1]


def _boottime():
    try:
        return time.clock_gettime(time.CLOCK_BOOTTIME)
    except (AttributeError, OSError):
        return None


def clock_snapshot():
    """Read optional clocks at a run boundary, with a non-atomic read bound."""
    boot_before = _boottime()
    monotonic = time.monotonic()
    wall = time.time()
    read_span = max(0.0, time.monotonic() - monotonic)
    boot_after = _boottime()
    # A suspend between clock reads must also widen the uncertainty. A purely
    # monotonic read span would hide that boundary ambiguity on Linux.
    available = boot_before is not None and boot_after is not None
    if available:
        read_span = max(read_span, boot_after - boot_before)
    return {'monotonic': monotonic, 'wall': wall,
            'boottime': boot_before if available else None, 'readSpan': read_span}


def clock_metadata(start, end):
    """Never infer suspend from wall time: it can move with clock corrections."""
    awake = end['monotonic'] - start['monotonic']
    boot_elapsed = (end['boottime'] - start['boottime']
                    if start['boottime'] is not None and end['boottime'] is not None else None)
    return {'wallElapsedSeconds': end['wall'] - start['wall'],
            'boottimeElapsedSeconds': boot_elapsed,
            'boottimeClock': 'CLOCK_BOOTTIME' if boot_elapsed is not None else None,
            'inferredSuspendSeconds': max(0.0, boot_elapsed - awake) if boot_elapsed is not None else None,
            'clockReadUncertaintySeconds': start['readSpan'] + end['readSpan']}


def stat_fields(raw):
    head, tail = raw.rsplit(')', 1)
    fields = tail.split()
    return {'pid': int(head.split('(', 1)[0]), 'parent': int(fields[1]),
            'start': int(fields[19]), 'ticks': int(fields[11]) + int(fields[12]),
            'rss': int(fields[21]) * os.sysconf('SC_PAGE_SIZE')}


def memory_fields(raw):
    fields = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == 'kB':
            value = int(parts[1])
            if value < 0:
                raise ValueError('Negative memory reading')
            fields[parts[0].rstrip(':')] = value * 1024
    return {'pss': fields.get('Pss'), 'rss': fields.get('Rss'),
            'private': fields['Private_Clean'] + fields['Private_Dirty'] + fields.get('Private_Hugetlb', 0)
            if 'Private_Clean' in fields and 'Private_Dirty' in fields else None,
            'swapPss': fields.get('SwapPss')}


def cgroup_path(raw):
    return next((line[3:] for line in raw.splitlines() if line.startswith('0::')), '')


def in_group(path, groups):
    return any(path == group or path.startswith(group.rstrip('/') + '/') for group in groups)


def python_script(argv):
    """Find a script behind ordinary interpreter flags, never interpret -c/-m."""
    index = 1
    while index < len(argv):
        argument = argv[index]
        if argument in ('-c', '-m', '-'):
            return None
        if argument == '--':
            return argv[index + 1] if index + 1 < len(argv) else None
        if argument in ('-W', '-X', '--check-hash-based-pycs'):
            index += 2
            continue
        if argument in ('-u', '-B', '-E', '-I', '-s', '-S', '-O', '-OO', '-q', '-v', '-vv', '-b', '-bb', '-d', '-P') or argument.startswith(('-W', '-X')):
            index += 1
            continue
        return argument if argument and not argument.startswith('-') else None
    return None


def command_paths(argv, cwd=None):
    """Resolve entrypoint arguments using the process cwd, not the sampler cwd."""
    if not argv:
        return []
    executable = Path(argv[0]).name
    candidates = []
    if executable in ('qs', 'quickshell'):
        for flag in ('-p', '--path'):
            if flag in argv and argv.index(flag) + 1 < len(argv):
                candidates.append(argv[argv.index(flag) + 1])
            candidates.extend(argument[len(flag) + 1:] for argument in argv if argument.startswith(flag + '='))
    elif executable.startswith('python') and len(argv) > 1:
        script = python_script(argv)
        if script:
            candidates.append(script)
    elif executable in ('cedar-task-manager', 'cedar-taskd'):
        candidates.append(argv[0])
    paths = []
    for value in candidates:
        path = Path(value)
        if not path.is_absolute():
            if cwd is None:
                continue
            path = cwd / path
        try:
            paths.append(path.resolve())
        except (OSError, RuntimeError):
            continue
    return paths


def diagnostic_command(argv, paths, source_roots):
    if not argv or not Path(argv[0]).name.startswith('python'):
        return False
    # Also exclude a second sampler from this checkout when the measured scope
    # is a different installed release or a cgroup supplied without source roots.
    diagnostic_roots = [*source_roots, SAMPLER_ROOT]
    return any((path.parent == root / 'scripts' and path.name in DIAGNOSTIC_SCRIPTS)
               or path in (root / 'tools/profiling/surface_stress.py',
                           root / 'tools/profiling/task_manager_session.py')
               for path in paths for root in diagnostic_roots)


def owned_command(argv, source_roots, cwd=None):
    """Classify runtime entrypoints only; never persist potentially secret argv."""
    paths = command_paths(argv, cwd)
    if not argv or diagnostic_command(argv, paths, source_roots):
        return False
    executable = Path(argv[0]).name
    if executable in ('qs', 'quickshell') and any(argument in ('ipc', 'list', 'kill', 'log') for argument in argv[1:]):
        # A caller querying this release is not another shell instance. If a
        # runtime itself owns this short-lived helper it is still a descendant.
        return False
    for resolved in paths:
        for root in source_roots:
            try:
                relative = resolved.relative_to(root)
            except ValueError:
                continue
            if executable in ('qs', 'quickshell'):
                return not relative.parts or resolved.suffix == '.qml'
            if executable.startswith('python') and relative.parts[:1] == ('scripts',):
                return True
            if executable.startswith('python') and (relative == Path('installer/cedar_install.py')
                    or relative.parts[:1] == ('tools',)):
                return True
            if executable in ('cedar-task-manager', 'cedar-taskd'):
                return True
    return False


def snapshot(roots, proc=Path('/proc'), *, cgroups=(), source_roots=(), tracked=()):
    all_rows, selected, excluded = {}, set(), {os.getpid()}
    for path in proc.glob('[0-9]*/stat'):
        try:
            row = stat_fields(path.read_text())
        except (OSError, ValueError, IndexError):
            continue
        directory = path.parent
        # Optional metadata may disappear during exit. Keep the stat identity so
        # an observed root/child cannot silently vanish from accounting merely
        # because comm or cgroup could not be read.
        row.update(name='unavailable', cgroup='')
        all_rows[row['pid']] = row
        try:
            row['name'] = directory.joinpath('comm').read_text().strip()
        except OSError:
            pass
        try:
            row['cgroup'] = cgroup_path(directory.joinpath('cgroup').read_text())
        except OSError:
            pass
        argv, cwd = [], None
        try:
            argv = directory.joinpath('cmdline').read_bytes().decode(errors='replace').rstrip('\0').split('\0')
            cwd = directory.joinpath('cwd').resolve(strict=True)
        except (OSError, RuntimeError):
            pass
        if diagnostic_command(argv, command_paths(argv, cwd), source_roots):
            excluded.add(row['pid'])
        reason = ('explicit-root' if roots.get(row['pid']) == row['start'] else
                  'observed-identity' if (row['pid'], row['start']) in tracked else
                  'cgroup' if in_group(row['cgroup'], cgroups) else
                  'source-entrypoint' if owned_command(argv, source_roots, cwd) else '')
        if reason:
            row['scopeReason'] = reason
            selected.add(row['pid'])
    # Do not count subprocesses of concurrent profiling tools as CEDAR workers.
    # An explicit root can still intentionally select a test harness for its own
    # benchmark; its observing parent remains excluded.
    while True:
        children = {pid for pid, row in all_rows.items() if row['parent'] in excluded
                    and roots.get(pid) != row['start']}
        if children <= excluded:
            break
        excluded |= children
    selected -= excluded
    while True:
        children = {pid for pid, row in all_rows.items() if row['parent'] in selected and pid not in excluded}
        if children <= selected:
            break
        for pid in children - selected:
            all_rows[pid]['scopeReason'] = 'descendant'
        selected |= children
    result = {}
    for pid in sorted(selected):
        row = all_rows[pid]
        row.update(pss=None, private=None, swapPss=None, rssPeak=None)
        directory = proc / str(pid)
        try:
            row.update({k: v for k, v in memory_fields(directory.joinpath('smaps_rollup').read_text()).items() if v is not None})
        except (OSError, ValueError):
            row['memoryError'] = 'smaps_rollup unavailable or invalid'
        try:
            for line in directory.joinpath('status').read_text().splitlines():
                if line.startswith('VmHWM:'):
                    row['rssPeak'] = int(line.split()[1]) * 1024
            current = stat_fields(directory.joinpath('stat').read_text())
            if current['start'] != row['start']:
                row.update(pss=None, private=None, memoryError='PID reused during sample')
        except (OSError, ValueError, IndexError):
            row.update(pss=None, private=None, memoryError='process exited during sample')
        result[(pid, row['start'])] = row
    return result


def complete_sum(rows, field):
    return sum(r[field] for r in rows) if rows and all(r.get(field) is not None for r in rows) else None


def compare(previous, current, elapsed, ticks):
    common = previous.keys() & current.keys()
    cpu = sum(max(0, current[k]['ticks'] - previous[k]['ticks']) for k in common) / ticks / elapsed * 100
    rows = list(current.values())
    return {'cpuOneCorePercent': cpu, 'rssSumBytes': sum(r['rss'] for r in rows),
            'pssBytes': complete_sum(rows, 'pss'), 'privateBytes': complete_sum(rows, 'private'),
            'processes': len(current), 'newIdentities': len(current.keys() - previous.keys()),
            'missingPssProcesses': sum(r.get('pss') is None for r in rows)}


def cgroup_metrics(groups, root=Path('/sys/fs/cgroup')):
    result = {}
    for group in groups:
        row = {}
        for field in ('memory.current', 'memory.peak'):
            try:
                row[field] = int((root / group.lstrip('/') / field).read_text())
            except (OSError, ValueError):
                row[field] = None
        result[group] = row
    return result


def summarize(samples, budget, max_processes=0):
    known = [s for s in samples if s['pssBytes'] is not None]
    complete = len(known) == len(samples) and bool(samples)
    window = max(1, len(known) // 10)
    result = {'sampleCount': len(samples), 'completePss': complete,
              'budgetBytes': budget, 'budgetViolations': sum(s['pssBytes'] > budget for s in known),
              'maxProcesses': max((s['processes'] for s in samples), default=0),
              'processLimitViolations': sum(s['processes'] > max_processes for s in samples) if max_processes else None,
              'medianCpuOneCorePercent': statistics.median(s['cpuOneCorePercent'] for s in samples) if samples else None,
              'maxCpuOneCorePercent': max((s['cpuOneCorePercent'] for s in samples), default=None),
              'peakPssBytes': max((s['pssBytes'] for s in known), default=None),
              'medianPssBytes': statistics.median(s['pssBytes'] for s in known) if known else None,
              'peakRssSumBytes': max((s['rssSumBytes'] for s in samples), default=None),
              'peakPrivateBytes': max((s['privateBytes'] for s in samples if s['privateBytes'] is not None), default=None),
              'retentionDeltaBytes': (statistics.median(s['pssBytes'] for s in known[-window:])
                                      - statistics.median(s['pssBytes'] for s in known[:window])) if known else None,
              'pssSlopeBytesPerHour': None}
    if len(known) > 1:
        xs = [s['elapsedSeconds'] for s in known]
        ys = [s['pssBytes'] for s in known]
        mean_x, mean_y = statistics.mean(xs), statistics.mean(ys)
        denominator = sum((x - mean_x) ** 2 for x in xs)
        if denominator:
            result['pssSlopeBytesPerHour'] = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / denominator * 3600
    result['budgetStatus'] = 'exceeded' if result['budgetViolations'] else 'within-sampled-scope' if complete else 'unknown'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, action='append', default=[])
    parser.add_argument('--cgroup', action='append', default=[], help='Exact unified cgroup path from /proc/PID/cgroup')
    parser.add_argument('--source-root', type=Path, action='append', default=[], help='Discover detached runtime entrypoints under this release')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', default='unspecified workload')
    parser.add_argument('--warmup', type=float, default=120)
    parser.add_argument('--seconds', type=float, default=180)
    parser.add_argument('--interval', type=float, default=2)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--budget-mb', type=float, default=500, help='Decimal MB, not MiB; report only, never kill')
    parser.add_argument('--max-processes', type=int, default=0, help='Optional diagnostic limit; zero disables')
    parser.add_argument('--fail-on-budget', action='store_true', help='Exit nonzero on exceeded or unknown accounting after writing evidence')
    parser.add_argument('--clock-metadata', action='store_true', help='Record run-boundary wall/boottime clocks and inferred suspend time; scheduling still uses monotonic time')
    args = parser.parse_args()
    if not (args.pid or args.cgroup or args.source_root):
        parser.error('Specify at least one root PID, cgroup or release directory')
    if (not all(math.isfinite(v) for v in (args.seconds, args.interval, args.warmup, args.budget_mb))
            or not 1 <= args.runs <= 10 or not 1 <= args.seconds <= 14400
            or not .1 <= args.interval <= 60 or not 0 <= args.warmup <= 600
            or args.budget_mb <= 0 or args.max_processes < 0
            or math.ceil(args.seconds / args.interval) * args.runs > 10000):
        parser.error('Invalid duration/budget or more than 10000 samples; increase the interval')
    if any(not group.startswith('/') or any(part in ('', '.', '..') for part in group.split('/')[1:]) for group in args.cgroup):
        parser.error('Use specific canonical absolute cgroup paths without empty/dot components')
    args.output = args.output.absolute()
    d.private_directory(args.output.parent)
    roots = {pid: stat_fields((Path('/proc') / str(pid) / 'stat').read_text())['start'] for pid in args.pid}
    source_roots = [path.resolve(strict=True) for path in args.source_root]
    report = {'format': 2, 'label': args.label, 'startedUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'scope': {'rootIdentities': roots, 'cgroups': args.cgroup, 'sourceRoots': list(map(str, source_roots))},
              'units': 'bytes; 1 MB = 1000000 bytes; 1 MiB = 1048576 bytes',
              'limitations': ['Non-atomic samples; between-sample peaks and short-lived helpers may be missed',
                              'CPU deltas cover surviving identities only; 100% means one logical CPU',
                              'RSS sum double-counts shared pages; USS is private clean+dirty+hugetlb',
                              'Cgroup memory includes kernel charges/page cache and is not group PSS',
                              'VmHWM and cgroup peaks are lifetime counters, not this run alone',
                              'GPU allocations, frame timing, errors and visual correctness require separate tools',
                              'Detached processes outside configured scopes are not accounted; Brain needs explicit inclusion',
                              'Source discovery needs readable cmdline/cwd; qs -c profiles, Python -m/-c and wrappers require an explicit root or cgroup',
                              'Descendants and cgroup members must be reviewed for unrelated user applications',
                              'Known source profiling tools and their subprocesses are excluded; other diagnostic roots require scope review'],
              'runs': []}
    if args.clock_metadata:
        report['limitations'].extend([
            'Run duration, CPU rates and PSS slopes use monotonic time; Linux system suspend is excluded',
            'Optional run clockMetadata excludes warmup; CLOCK_BOOTTIME includes Linux suspend when available',
            'Wall elapsed can jump with clock corrections; suspend is estimated only from boottime minus monotonic',
            'Clock reads are non-atomic; estimates within clockReadUncertaintySeconds are inconclusive, not proof of suspend'])
    ticks = os.sysconf('SC_CLK_TCK')
    failed = False
    for _ in range(args.runs):
        time.sleep(args.warmup)
        previous = snapshot(roots, cgroups=args.cgroup, source_roots=source_roots)
        tracked = set(previous)
        clock_start = clock_snapshot() if args.clock_metadata else None
        started = last = clock_start['monotonic'] if clock_start is not None else time.monotonic()
        samples = []
        run = {'warmupSeconds': args.warmup, 'intervalSeconds': args.interval, 'samples': samples}
        report['runs'].append(run)
        while last - started < args.seconds:
            time.sleep(max(0, min(args.interval, args.seconds - (last - started)) - (time.monotonic() - last)))
            current = snapshot(roots, cgroups=args.cgroup, source_roots=source_roots, tracked=tracked)
            now = time.monotonic()
            sample = compare(previous, current, now - last, ticks)
            sample.update(elapsedSeconds=now-started, processesDetail=list(current.values()), cgroups=cgroup_metrics(args.cgroup))
            samples.append(sample)
            tracked.update(current)
            if len(tracked) > 100000:
                run['error'] = 'More than 100000 process identities; sampling stopped without touching providers'
                break
            if any((pid, start) not in current for pid, start in roots.items()):
                run['error'] = 'An explicit root exited or changed identity; run is incomplete'
                break
            previous, last = current, now
        clock_end = clock_snapshot() if args.clock_metadata else None
        run['durationSeconds'] = (clock_end['monotonic'] if clock_end is not None else time.monotonic()) - started
        if clock_start is not None:
            run['clockMetadata'] = clock_metadata(clock_start, clock_end)
        run['summary'] = summarize(samples, args.budget_mb * 1000000, args.max_processes)
        run['summary']['observedIdentities'] = len(tracked)
        if run.get('error') and run['summary']['budgetStatus'] != 'exceeded':
            run['summary']['budgetStatus'] = 'unknown'
        failed |= run['summary']['budgetStatus'] != 'within-sampled-scope' or bool(run['summary']['processLimitViolations'])
        d.write_json(args.output, report)
        print(json.dumps(run['summary']), flush=True)
        if run.get('error'):
            break
    return 2 if failed and args.fail_on_budget else 0


if __name__ == '__main__':
    raise SystemExit(main())
