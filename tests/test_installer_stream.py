"""Real subprocess regressions for the installer's output and timeout owner."""
import os
import pty
from pathlib import Path
import subprocess
import sys
import time
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.engine.host import Host


class InstallerStream(unittest.TestCase):
    def test_privilege_wrappers_keep_controlling_terminal_and_foreground_group(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ('sudo', 'pkexec'):
                with self.subTest(wrapper=name):
                    wrapper = Path(directory) / name
                    wrapper.write_text('#!' + sys.executable + '\nimport os\nfd=os.open("/dev/tty", os.O_RDWR)\nassert os.tcgetpgrp(fd)==os.getpgrp()\nos.close(fd)\n')
                    wrapper.chmod(0o700)
                    pid, terminal = pty.fork()
                    if pid == 0:
                        try:
                            result = Host().stream([str(wrapper)], lambda line: None, timeout=2)
                        except Exception:
                            result = 1
                        os._exit(result)
                    try:
                        deadline = time.monotonic() + 4
                        while time.monotonic() < deadline:
                            ended, status = os.waitpid(pid, os.WNOHANG)
                            if ended:
                                break
                            time.sleep(.02)
                        else:
                            os.kill(pid, 9)
                            os.waitpid(pid, 0)
                            self.fail('privilege wrapper terminal test timed out')
                        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
                    finally:
                        os.close(terminal)

    def test_package_timeout_reports_uncertain_elevated_process_state(self):
        from types import SimpleNamespace
        from unittest.mock import Mock, patch
        from installer.engine import steps
        host = Mock()
        host.stream.side_effect = subprocess.TimeoutExpired(['sudo', 'pacman'], 3600)
        provider = SimpleNamespace(check=lambda *args: None, argv=lambda missing: ['pacman', '-S', *missing])
        context = SimpleNamespace(host=host, plan={'packages': ['fixture']}, facts={}, log=None,
                                  emit=Mock(), progress=Mock(), output=Mock())
        with patch.object(steps.package_providers, 'select', return_value=provider), \
             patch.object(steps.privilege, 'method', return_value='sudo'):
            with self.assertRaisesRegex(RuntimeError, 'may still be running or may have been interrupted'):
                steps.dependencies_run(context, SimpleNamespace(id='dependencies'))

    def test_timeout_stops_owned_grandchild_before_it_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'survived'
            child = 'import time; from pathlib import Path; time.sleep(.4); Path(' + repr(str(marker)) + ').write_text("survived")'
            parent = 'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",' + repr(child) + ']); time.sleep(2)'
            with self.assertRaises(subprocess.TimeoutExpired):
                Host().stream([sys.executable, '-c', parent], lambda line: None, timeout=0.15)
            time.sleep(0.5)
            self.assertFalse(marker.exists())

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
