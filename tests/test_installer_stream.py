"""Real subprocess regressions for the installer's output and timeout owner."""
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.engine.host import Host


class InstallerStream(unittest.TestCase):
    def test_silent_process_obeys_deadline_and_is_reaped(self):
        lines = []
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            Host().stream([sys.executable, '-c', 'import os,time; print(os.getpid(), flush=True); time.sleep(1)'],
                          lines.append, timeout=0.2)
        self.assertLess(time.monotonic() - started, 0.8)
        pid = int(lines[0])
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_continuous_output_cannot_extend_the_deadline(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            Host().stream([sys.executable, '-c',
                           'import time\nfor i in range(100):\n print(i, flush=True); time.sleep(.01)'],
                          lambda line: None, timeout=0.2)

    def test_partial_lines_and_utf8_survive_streaming(self):
        lines = []
        code = 'import os,time; os.write(1,b"first\\n\\xe2"); time.sleep(.05); os.write(1,b"\\x98\\x83\\nlast")'
        result = Host().stream([sys.executable, '-c', code], lines.append, timeout=2)
        self.assertEqual(result, 0)
        self.assertEqual(lines, ['first', '\u2603', 'last'])

    def test_large_unterminated_output_is_delivered_in_bounded_fragments(self):
        lines = []
        size = 2 * 1024 * 1024
        result = Host().stream([sys.executable, '-c', 'import sys; sys.stdout.write("x" * ' + str(size) + ')'],
                              lines.append, timeout=2)
        self.assertEqual(result, 0)
        self.assertEqual(sum(map(len, lines)), size)
        self.assertLessEqual(max(map(len, lines)), 64 * 1024)

    def test_callback_failure_reaps_owned_process(self):
        pids = []
        def reject(line):
            pids.append(int(line))
            raise ValueError('fixture callback failed')
        with self.assertRaisesRegex(ValueError, 'fixture callback failed'):
            Host().stream([sys.executable, '-c', 'import os,time; print(os.getpid(), flush=True); time.sleep(1)'],
                          reject, timeout=2)
        with self.assertRaises(ProcessLookupError):
            os.kill(pids[0], 0)


if __name__ == '__main__':
    unittest.main()
