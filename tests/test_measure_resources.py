"""Accounting failures must not produce a false memory-budget pass."""
import json
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import measure_resources as m


class RunClocks(unittest.TestCase):
    def test_optional_clocks_do_not_change_awake_sampling_or_cpu_rates(self):
        before = {(123, 1): {'rss': 20, 'pss': 10, 'private': 10, 'ticks': 0}}
        after = {(123, 1): {'rss': 20, 'pss': 10, 'private': 10, 'ticks': 100}}
        for enabled in (False, True):
            with self.subTest(enabled=enabled), tempfile.TemporaryDirectory() as tmp:
                argv = ['measure_resources.py', '--cgroup', '/fixture', '--output', str(Path(tmp) / 'report.json'),
                        '--warmup', '0', '--seconds', '1', '--interval', '1', '--runs', '1']
                if enabled:
                    argv.append('--clock-metadata')
                boundaries = [
                    {'monotonic': 100, 'wall': 1000, 'boottime': 200, 'readSpan': 0},
                    {'monotonic': 101, 'wall': 1061, 'boottime': 261, 'readSpan': 0}]
                with mock.patch.object(sys, 'argv', argv), \
                        mock.patch.object(m, 'snapshot', side_effect=[before, after]), \
                        mock.patch.object(m, 'cgroup_metrics', return_value={}), \
                        mock.patch.object(m, 'clock_snapshot', side_effect=boundaries) as clocks, \
                        mock.patch.object(m.time, 'sleep'), \
                        mock.patch.object(m.time, 'monotonic', side_effect=[100, 101] if enabled else [100, 100, 101, 101]), \
                        mock.patch.object(m.os, 'sysconf', return_value=100), \
                        mock.patch.object(m.d, 'write_json') as write, contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(m.main(), 0)
                    run = write.call_args.args[1]['runs'][0]
                    self.assertEqual(run['durationSeconds'], 1)
                    self.assertEqual(run['samples'][0]['elapsedSeconds'], 1)
                    self.assertEqual(run['samples'][0]['cpuOneCorePercent'], 100)
                    self.assertEqual(len(run['samples']), 1)
                    self.assertEqual(clocks.call_count, 2 if enabled else 0)
                    if enabled:
                        self.assertEqual(run['clockMetadata']['inferredSuspendSeconds'], 60)
                    else:
                        self.assertNotIn('clockMetadata', run)

    def test_suspend_estimate_uses_boottime_not_adjusted_wall_clock(self):
        start = {'monotonic': 10, 'wall': 1000, 'boottime': 100, 'readSpan': .001}
        end = {'monotonic': 70, 'wall': 500, 'boottime': 460, 'readSpan': .002}
        clocks = m.clock_metadata(start, end)
        self.assertEqual(clocks['wallElapsedSeconds'], -500)
        self.assertEqual(clocks['boottimeElapsedSeconds'], 360)
        self.assertEqual(clocks['inferredSuspendSeconds'], 300)
        self.assertAlmostEqual(clocks['clockReadUncertaintySeconds'], .003)

    def test_missing_boottime_at_either_boundary_leaves_suspend_unknown(self):
        for first, last in ((None, None), (None, 200), (100, None)):
            with self.subTest(first=first, last=last):
                clocks = m.clock_metadata(
                    {'monotonic': 10, 'wall': 1000, 'boottime': first, 'readSpan': 0},
                    {'monotonic': 70, 'wall': 2000, 'boottime': last, 'readSpan': 0})
                self.assertEqual(clocks['wallElapsedSeconds'], 1000)
                self.assertIsNone(clocks['boottimeElapsedSeconds'])
                self.assertIsNone(clocks['boottimeClock'])
                self.assertIsNone(clocks['inferredSuspendSeconds'])

    def test_non_atomic_clock_jitter_cannot_report_negative_suspend(self):
        clocks = m.clock_metadata(
            {'monotonic': 10, 'wall': 10, 'boottime': 20.001, 'readSpan': .002},
            {'monotonic': 70, 'wall': 70, 'boottime': 80, 'readSpan': .002})
        self.assertEqual(clocks['inferredSuspendSeconds'], 0)
        self.assertGreater(clocks['clockReadUncertaintySeconds'], .001)

    def test_suspend_during_boundary_reads_widens_uncertainty(self):
        with mock.patch.object(m.time, 'monotonic', side_effect=[10, 10.001]), \
                mock.patch.object(m.time, 'time', return_value=1060), \
                mock.patch.object(m, '_boottime', side_effect=[100, 160]):
            clocks = m.clock_snapshot()
            self.assertEqual(clocks['boottime'], 100)
            self.assertEqual(clocks['readSpan'], 60)

    def test_unavailable_boottime_clock_is_optional(self):
        for failure in (AttributeError('unsupported clock'), OSError('clock unavailable')):
            with self.subTest(failure=type(failure).__name__), \
                    mock.patch.object(m.time, 'monotonic', side_effect=[10, 10.001]), \
                    mock.patch.object(m.time, 'time', return_value=1000), \
                    mock.patch.object(m.time, 'clock_gettime', side_effect=failure, create=True):
                clocks = m.clock_snapshot()
                self.assertEqual(clocks['monotonic'], 10)
                self.assertEqual(clocks['wall'], 1000)
                self.assertIsNone(clocks['boottime'])
                self.assertAlmostEqual(clocks['readSpan'], .001)


class Accounting(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)

    def process(self, pid, parent=1, start=100, group='/other', args=None, memory=True, cwd=None):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        fields = ['0'] * 22
        fields[0], fields[1], fields[11], fields[12], fields[19], fields[21] = 'S', str(parent), '40', '10', str(start), '8'
        (directory / 'stat').write_text(f'{pid} (name with ) parentheses) ' + ' '.join(fields))
        (directory / 'comm').write_text('test-runtime\n')
        (directory / 'cgroup').write_text('0::' + group + '\n')
        (directory / 'cmdline').write_bytes('\0'.join(args or ['/usr/bin/test']).encode() + b'\0')
        (directory / 'status').write_text('VmHWM:\t64 kB\n')
        if cwd is not None:
            (directory / 'cwd').symlink_to(cwd, target_is_directory=True)
        if memory:
            (directory / 'smaps_rollup').write_text('Rss: 32 kB\nPss: 16 kB\nPrivate_Clean: 2 kB\nPrivate_Dirty: 8 kB\nPrivate_Hugetlb: 4 kB\nSwapPss: 1 kB\n')

    def test_pss_private_and_rss_use_rollup_not_double_counted_rss(self):
        self.process(100)
        row = m.snapshot({100: 100}, self.proc)[(100, 100)]
        self.assertEqual((row['rss'], row['pss'], row['private'], row['swapPss'], row['rssPeak']),
                         (32768, 16384, 14336, 1024, 65536))

    def test_descendants_and_reparented_observed_helpers_are_retained(self):
        self.process(100)
        self.process(101, parent=100)
        before = m.snapshot({100: 100}, self.proc)
        self.process(101, parent=1)
        after = m.snapshot({100: 100}, self.proc, tracked=set(before))
        self.assertEqual(set(after), {(100, 100), (101, 100)})

    def test_pid_reuse_never_counts_an_unrelated_replacement(self):
        self.process(100, start=200)
        self.assertEqual(m.snapshot({100: 100}, self.proc, tracked={(100, 100)}), {})

    def test_cgroup_boundary_captures_detached_worker_not_similar_prefix(self):
        self.process(100, group='/user/cedar.service')
        self.process(101, group='/user/cedar.service/worker')
        self.process(102, group='/user/cedar.service-other')
        selected = m.snapshot({}, self.proc, cgroups=['/user/cedar.service'])
        self.assertEqual({pid for pid, start in selected}, {100, 101})

    def test_source_scope_finds_native_and_python_but_not_editors(self):
        root = self.proc / 'release'
        self.process(100, args=['/usr/bin/python3', str(root / 'scripts/connections.py'), '--watch'])
        self.process(101, args=[str(root / 'libexec/cedar-task-manager'), '--source', str(root)])
        self.process(102, args=['vim', str(root / 'shell.qml')])
        self.process(103, args=['qs', '-p', str(root / 'shell.qml')])
        self.process(104, args=['python3', str(self.proc / 'another/scripts/connections.py')])
        selected = m.snapshot({}, self.proc, source_roots=[root])
        self.assertEqual({pid for pid, start in selected}, {100, 101, 103})
        self.assertFalse(any('command' in r or 'argv' in r for r in selected.values()))

    def test_new_benchmarks_are_excluded_from_runtime_discovery(self):
        root = self.proc / 'release'
        for relative in ('scripts/benchmark_release_validation.py', 'tools/profiling/surface_stress.py',
                         'tools/profiling/task_manager_session.py'):
            with self.subTest(relative=relative):
                self.assertFalse(m.owned_command(['python3', str(root / relative)], [root]))

    def test_concurrent_diagnostics_and_children_are_excluded_from_source_and_cgroup(self):
        root = self.proc / 'release'
        self.process(100, args=['python3', str(root / 'scripts/connections.py')], group='/cedar')
        self.process(101, args=['python3', str(root / 'scripts/measure_resources.py')], group='/cedar')
        self.process(102, parent=101, args=['python3', str(root / 'scripts/audit_resources.py')], group='/cedar')
        self.process(103, parent=102, args=['qs', '-p', str(root / 'shell.qml')], group='/cedar')
        selected = m.snapshot({}, self.proc, source_roots=[root], cgroups=['/cedar'])
        self.assertEqual(set(selected), {(100, 100)})
        self.assertFalse(m.owned_command(['python3', str(root / 'scripts/measure_resources.py')], [root]))
        # Explicit benchmark roots remain available even beneath an observer.
        selected = m.snapshot({103: 100}, self.proc, source_roots=[root], cgroups=['/cedar'])
        self.assertEqual(set(selected), {(100, 100), (103, 100)})

    def test_relative_flagged_runtime_and_installer_paths_use_process_cwd(self):
        root = self.proc / 'release'
        root.mkdir()
        self.process(100, args=['python3', '-u', '-W', 'ignore', 'scripts/connections.py'], cwd=root)
        self.process(101, args=['qs', '--path=./shell.qml'], cwd=root)
        self.process(102, args=['python3', 'installer/cedar_install.py'], cwd=root)
        self.process(103, args=['python3', 'tools/wallpapers/apply.py'], cwd=root)
        self.process(104, args=['python3', '-m', str(root / 'scripts/connections.py')], cwd=root)
        self.process(105, args=['python3', '-c', str(root / 'scripts/connections.py')], cwd=root)
        self.assertEqual(set(m.snapshot({}, self.proc, source_roots=[root])),
                         {(100, 100), (101, 100), (102, 100), (103, 100)})

    def test_external_ipc_observer_is_not_a_second_shell(self):
        root = self.proc / 'release'
        self.process(100, args=['qs', '-p', str(root / 'shell.qml')])
        self.process(101, args=['qs', '-p', str(root / 'shell.qml'), 'ipc', 'call', 'shell', 'isLocked'])
        self.process(102, parent=100, args=['qs', '-p', str(root / 'shell.qml'), 'ipc', 'call', 'shell', 'isLocked'])
        selected = m.snapshot({}, self.proc, source_roots=[root])
        self.assertEqual(set(selected), {(100, 100), (102, 100)})
        self.assertEqual(selected[(100, 100)]['scopeReason'], 'source-entrypoint')
        self.assertEqual(selected[(102, 100)]['scopeReason'], 'descendant')

    def test_lost_optional_metadata_does_not_drop_known_child(self):
        self.process(100)
        self.process(101, parent=100, memory=False)
        (self.proc / '101/comm').unlink()
        (self.proc / '101/cgroup').unlink()
        rows = m.snapshot({100: 100}, self.proc)
        self.assertEqual(set(rows), {(100, 100), (101, 100)})
        sample = m.compare({}, rows, 1, 100)
        sample['elapsedSeconds'] = 1
        self.assertEqual(m.summarize([sample], 500_000_000)['budgetStatus'], 'unknown')

    def test_identity_change_during_rollup_read_invalidates_memory(self):
        self.process(100)
        read_text = Path.read_text

        def race(path, *args, **kwargs):
            result = read_text(path, *args, **kwargs)
            if path == self.proc / '100/smaps_rollup':
                self.process(100, start=200)
            return result

        with mock.patch.object(Path, 'read_text', race):
            row = m.snapshot({100: 100}, self.proc)[(100, 100)]
        self.assertIsNone(row['pss'])
        self.assertIn('PID reused', row['memoryError'])

    def test_invalid_negative_memory_is_unknown(self):
        self.process(100)
        (self.proc / '100/smaps_rollup').write_text('Pss: -1 kB\n')
        self.assertIsNone(m.snapshot({100: 100}, self.proc)[(100, 100)]['pss'])

    def test_missing_rollup_is_unknown_not_zero(self):
        self.process(100, memory=False)
        sample = m.compare({}, m.snapshot({100: 100}, self.proc), 1, 100)
        sample['elapsedSeconds'] = 1
        self.assertIsNone(sample['pssBytes'])
        self.assertIsNone(sample['privateBytes'])
        self.assertEqual(m.summarize([sample], 500_000_000)['budgetStatus'], 'unknown')

    def test_empty_scope_cannot_pass_budget(self):
        sample = m.compare({}, {}, 1, 100)
        sample['elapsedSeconds'] = 1
        self.assertEqual(m.summarize([sample], 500_000_000)['budgetStatus'], 'unknown')

    def test_decimal_budget_and_retention_trend(self):
        samples = []
        for index, size in enumerate([490_000_000, 500_000_000, 510_000_000]):
            sample = m.compare({}, {(100, 1): {'rss': size, 'pss': size, 'private': size, 'ticks': 1}}, 1, 100)
            sample['elapsedSeconds'] = index * 60
            samples.append(sample)
        summary = m.summarize(samples, 500_000_000, max_processes=1)
        self.assertEqual(summary['budgetStatus'], 'exceeded')
        self.assertEqual(summary['budgetViolations'], 1)
        self.assertEqual(summary['retentionDeltaBytes'], 20_000_000)
        self.assertEqual(summary['pssSlopeBytesPerHour'], 600_000_000)
        self.assertEqual(summary['processLimitViolations'], 0)

    def test_cgroup_metrics_are_separate_not_substituted_for_pss(self):
        folder = self.proc / 'group'
        folder.mkdir()
        (folder / 'memory.current').write_text('600000000\n')
        (folder / 'memory.peak').write_text('700000000\n')
        self.assertEqual(m.cgroup_metrics(['/group'], self.proc),
                         {'/group': {'memory.current': 600_000_000, 'memory.peak': 700_000_000}})

    def test_cli_empty_cgroup_fails_after_writing_private_evidence(self):
        output = self.proc / 'private' / 'report.json'
        completed = subprocess.run([sys.executable, str(ROOT / 'scripts/measure_resources.py'),
            '--cgroup', '/cedar-nonexistent-accounting-test', '--output', str(output),
            '--warmup', '0', '--seconds', '1', '--interval', '1', '--runs', '1', '--fail-on-budget', '--clock-metadata'],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(completed.returncode, 2, completed.stderr)
        run = json.loads(output.read_text())['runs'][0]
        self.assertEqual(run['summary']['budgetStatus'], 'unknown')
        self.assertGreater(run['durationSeconds'], 0)
        self.assertGreater(run['clockMetadata']['wallElapsedSeconds'], 0)
        self.assertIn('inferredSuspendSeconds', run['clockMetadata'])
        self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_cli_rejects_cgroup_aliases_that_could_select_the_whole_host(self):
        for group in ('/', '//', '/./', '/user/../', '/user//cedar', '/user/cedar/'):
            with self.subTest(group=group):
                completed = subprocess.run([sys.executable, str(ROOT / 'scripts/measure_resources.py'),
                    '--cgroup', group, '--output', str(self.proc / 'unused/report.json'),
                    '--warmup', '0', '--seconds', '1', '--runs', '1'],
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(completed.returncode, 2)
                self.assertIn('canonical absolute cgroup', completed.stderr)


if __name__ == '__main__':
    unittest.main()
