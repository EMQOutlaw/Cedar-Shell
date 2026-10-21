"""Exercise the standalone bootstrap against local downloads, never GitHub."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / 'installer/bootstrap/install.sh'


class BootstrapSecurity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.script = BOOTSTRAP
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.archive = self.root / 'archive.tar.gz'
        self.checksum = self.root / 'archive.sha256'
        self.calls = self.root / 'calls'
        curl = self.bin / 'curl'
        curl.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args = sys.argv[1:]
with open(os.environ['BOOTSTRAP_CALLS'], 'a') as log:
    log.write(args[-1] + '\\n')
source = os.environ['BOOTSTRAP_CHECKSUM' if args[-1].endswith('.sha256') else 'BOOTSTRAP_ARCHIVE']
if '-o' in args:
    shutil.copyfile(source, args[args.index('-o') + 1])
else:
    sys.stdout.buffer.write(pathlib.Path(source).read_bytes())
if os.environ.get('BOOTSTRAP_FAIL'):
    raise SystemExit(22)
''')
        curl.chmod(0o755)
        self.env = {**os.environ, 'HOME': str(self.home), 'XDG_CACHE_HOME': str(self.home / '.cache'),
                    'PATH': str(self.bin) + os.pathsep + os.environ['PATH'], 'CEDAR_VERSION': 'v1.2.3',
                    'CEDAR_CHANNEL': 'stable', 'CEDAR_FETCH_ONLY': '1',
                    'BOOTSTRAP_ARCHIVE': str(self.archive), 'BOOTSTRAP_CHECKSUM': str(self.checksum),
                    'BOOTSTRAP_CALLS': str(self.calls)}
        for key in ('CEDAR_REPO', 'CEDAR_BRANCH'):
            self.env.pop(key, None)
        self.make_archive()

    def make_archive(self, extra=(), top='cedar-shell'):
        with tarfile.open(self.archive, 'w:gz') as archive:
            member = tarfile.TarInfo(top + '/installer/cedar_install.py')
            data = b'raise SystemExit("fetch-only must not execute the installer")\n'
            member.mode, member.size = 0o755, len(data)
            archive.addfile(member, io.BytesIO(data))
            for member in extra:
                archive.addfile(member, io.BytesIO(b'') if member.isfile() else None)
        self.checksum.write_text(hashlib.sha256(self.archive.read_bytes()).hexdigest() +
                                 '  cedar-1.2.3-x86_64.tar.gz\n')

    def run_bootstrap(self):
        return subprocess.run(['sh', str(self.script)], env=self.env, capture_output=True, text=True, timeout=15)

    def source(self, result):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return Path(next(line.removeprefix('CEDAR_SOURCE=') for line in result.stdout.splitlines()
                         if line.startswith('CEDAR_SOURCE=')))

    def test_stable_source_is_private_and_executable_modes_are_preserved(self):
        source = self.source(self.run_bootstrap())
        self.assertTrue((source / 'installer/cedar_install.py').is_file())
        self.assertEqual((source / 'installer/cedar_install.py').stat().st_mode & 0o777, 0o755)
        self.assertEqual(source.parent.stat().st_mode & 0o777, 0o700)

    def test_another_file_checksum_does_not_authenticate_the_archive(self):
        unrelated = self.root / 'unrelated'
        unrelated.write_text('unrelated')
        self.checksum.write_text(hashlib.sha256(unrelated.read_bytes()).hexdigest() + '  ' + str(unrelated) + '\n')
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('CEDAR_SOURCE=', result.stdout)

    def test_mismatched_checksum_refuses_extraction(self):
        self.checksum.write_text('0' * 64 + '  cedar-1.2.3-x86_64.tar.gz\n')
        self.assertNotEqual(self.run_bootstrap().returncode, 0)
        self.assertFalse(list(self.home.rglob('cedar_install.py')))

    def test_version_path_traversal_is_refused_before_download(self):
        self.env['CEDAR_VERSION'] = '../../escape'
        self.assertNotEqual(self.run_bootstrap().returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.home / '.cache/escape').exists())

    def test_cache_symlink_is_refused_without_chmod_or_writes(self):
        outside = self.root / 'outside'
        outside.mkdir(mode=0o755)
        cache = self.home / '.cache/cedar'
        cache.mkdir(parents=True)
        (cache / 'installer').symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.run_bootstrap().returncode, 0)
        self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlink_hardlink_fifo_and_duplicate_members_are_refused(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.REGTYPE):
            with self.subTest(kind=kind):
                member = tarfile.TarInfo('cedar-shell/link' if kind != tarfile.REGTYPE else 'cedar-shell/installer/cedar_install.py')
                member.type, member.linkname = kind, 'installer/cedar_install.py'
                self.make_archive([member])
                self.assertNotEqual(self.run_bootstrap().returncode, 0)

    def test_archive_member_count_is_bounded(self):
        self.make_archive([tarfile.TarInfo('cedar-shell/empty-' + str(i)) for i in range(10000)])
        self.assertNotEqual(self.run_bootstrap().returncode, 0)

    def test_development_has_one_root_and_a_real_installer(self):
        self.env['CEDAR_CHANNEL'] = 'development'
        self.make_archive(top='Cedar-Shell-dev')
        self.source(self.run_bootstrap())
        self.make_archive([tarfile.TarInfo('another-root/file')], top='Cedar-Shell-dev')
        self.assertNotEqual(self.run_bootstrap().returncode, 0)

    def test_prepared_sources_are_not_replaced_by_a_second_bootstrap(self):
        first = self.source(self.run_bootstrap())
        sentinel = first / 'retained-for-pending-installer'
        sentinel.write_text('pending')
        second = self.source(self.run_bootstrap())
        self.assertNotEqual(first, second)
        self.assertEqual(sentinel.read_text(), 'pending')

    def test_transport_failure_is_preserved_across_bounded_pipeline(self):
        self.env['BOOTSTRAP_FAIL'] = '1'
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Download failed', result.stderr)
        self.assertNotIn('CEDAR_SOURCE=', result.stdout)

    def test_checksum_download_is_stopped_at_its_byte_limit(self):
        self.checksum.write_bytes(b'x' * 8192)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Download exceeds', result.stderr)

    def test_archive_download_stops_without_waiting_for_archive_parsing(self):
        source = BOOTSTRAP.read_text()
        self.assertIn('MAX_DOWNLOAD=603979776', source)
        self.script = self.root / 'small-budget-bootstrap.sh'
        self.script.write_text(source.replace('MAX_DOWNLOAD=603979776', 'MAX_DOWNLOAD=1024'))
        self.archive.write_bytes(b'x' * 2048)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Download exceeds', result.stderr)
        self.assertNotIn('Verifying', result.stdout)

    def test_wget_fallback_preserves_download_and_limit_behavior(self):
        (self.bin / 'curl').rename(self.bin / 'wget')
        for name in ('sh', 'uname', 'id', 'python3', 'cat', 'rm'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env['PATH'] = str(self.bin)
        self.source(self.run_bootstrap())
        self.checksum.write_bytes(b'x' * 8192)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Download exceeds', result.stderr)

    def test_wget_has_a_total_deadline_even_without_idle_timeout(self):
        (self.bin / 'curl').rename(self.bin / 'wget')
        (self.bin / 'wget').write_text('#!/usr/bin/env python3\nimport sys,time\nfor i in range(100):\n sys.stdout.buffer.write(b"x"); sys.stdout.buffer.flush(); time.sleep(.1)\n')
        for name in ('sh', 'uname', 'id', 'python3', 'cat', 'rm'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env['PATH'] = str(self.bin)
        source = BOOTSTRAP.read_text()
        self.assertIn('DOWNLOAD_SECONDS=900', source)
        self.script = self.root / 'short-deadline-bootstrap.sh'
        self.script.write_text(source.replace('DOWNLOAD_SECONDS=900', 'DOWNLOAD_SECONDS=1'))
        started = time.monotonic()
        result = self.run_bootstrap()
        self.assertLess(time.monotonic() - started, 4)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Download timed out', result.stderr)
        self.assertNotIn('CEDAR_SOURCE=', result.stdout)


if __name__ == '__main__':
    unittest.main()
