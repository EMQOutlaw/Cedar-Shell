"""Real proc format fixtures; no desktop or process mutation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('task_monitor', ROOT / 'scripts/task_monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class Sampling(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        self.now = 0
        self.sampler = monitor.Sampler(self.proc, lambda: self.now, hz=100, page_size=4096)
        self.core(100, 100)

    def core(self, busy, idle):
        (self.proc / 'stat').write_text(f'cpu {busy} 0 0 {idle} 0 0 0 0\ncpu0 {busy} 0 0 {idle} 0 0 0 0\n')

    def process(self, pid=42, ticks=10, start=500, name='editor (worker)', rss=12):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        fields = ['S'] + ['0'] * 21
        fields[11], fields[12], fields[17], fields[19], fields[21] = str(ticks), '0', '3', str(start), str(rss)
        (directory / 'stat').write_text(f'{pid} ({name}) ' + ' '.join(fields))

    def test_first_sample_and_percentages(self):
        self.process()
        first = self.sampler.sample()
        self.assertIsNone(first['processes'][0]['cpu'])
        self.assertIsNone(first['cores'][0]['cpu'])
        self.now = 2
        self.process(ticks=310)
        self.core(250, 150)
        second = self.sampler.sample()
        row = second['processes'][0]
        self.assertEqual(row['cpu'], 150)  # 100% is one fully occupied logical core.
        self.assertEqual(row['rss'], 12 * 4096)
        self.assertEqual(row['threads'], 3)
        self.assertEqual(row['name'], 'editor (worker)')
        self.assertEqual(second['cores'][0]['cpu'], 75)

    def test_pid_reuse_does_not_inherit_cpu(self):
        self.process(ticks=900)
        self.sampler.sample()
        self.now = 2
        self.process(ticks=1000, start=501)
        self.assertIsNone(self.sampler.sample()['processes'][0]['cpu'])

    def test_vanished_and_malformed_processes_are_skipped(self):
        self.process()
        (self.proc / '43').mkdir()
        (self.proc / '44').mkdir()
        (self.proc / '44/stat').write_text('invalid')
        self.assertEqual(self.sampler.sample()['total'], 1)
        (self.proc / '42/stat').unlink()
        self.now = 2
        self.assertEqual(self.sampler.sample()['processes'], [])
        self.assertFalse(self.sampler.previous)

    def test_counter_reset_and_zero_time_are_unavailable(self):
        self.process(ticks=100)
        self.sampler.sample()
        self.process(ticks=10)
        self.now = 2
        self.assertIsNone(self.sampler.sample()['processes'][0]['cpu'])
        self.process(ticks=20)
        self.assertIsNone(self.sampler.sample()['processes'][0]['cpu'])


if __name__ == '__main__':
    unittest.main()
