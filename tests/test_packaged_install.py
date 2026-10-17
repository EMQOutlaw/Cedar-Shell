"""Package-to-user lifecycle without Git, system packages or a live desktop.

The package root and both launchers live in a temporary prefix. Real copying,
release verification, profile adoption, provenance and CLI update dispatch run;
only desktop discovery/import rendering are replaced by an absent runtime.
"""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'scripts'))
import distribution as d
from installer.engine import operations, steps, update
from installer.engine.host import FakeHost
from installer.engine.server import Engine


class PackagedInstall(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cedar packaged 雨 ')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.system = self.base / 'usr/share/cedar'
        self.home = self.base / 'home'
        self.home.mkdir()
        self.bin = self.base / 'tools'
        self.bin.mkdir()
        (self.bin / 'python3').symlink_to(sys.executable)
        # Any accidental call to a package, network or desktop command fails
        # locally and leaves evidence, never resolving a real host executable.
        self.blocked = self.base / 'forbidden-command'
        for command in ('git', 'curl', 'wget', 'sudo', 'dnf', 'pacman', 'qs', 'hyprctl', 'systemctl', 'busctl'):
            executable = self.bin / command
            executable.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> ' + shlex.quote(str(self.blocked)) + '\nexit 99\n')
            executable.chmod(0o755)
        environment = {'HOME': str(self.home), 'PATH': str(self.bin), 'PYTHONDONTWRITEBYTECODE': '1',
                       'PYTHONUTF8': '1', 'CEDAR_SYSTEM_SOURCE': str(self.system),
                       'XDG_RUNTIME_DIR': str(self.base / 'runtime'),
                       'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(self.base / 'no-bus')}
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            environment['XDG_' + kind + '_HOME'] = str(self.home / kind.lower())
        (self.base / 'runtime').mkdir(mode=0o700)
        guard = mock.patch.dict(os.environ, environment, clear=True)
        guard.start()
        self.addCleanup(guard.stop)
        for source, relative in d.files(ROOT):
            target = self.system / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        self.artifact_record()
        self.wrapper = self.base / 'usr/bin/cedar'
        self.wrapper.parent.mkdir(parents=True)
        self.wrapper.write_text('#!/bin/sh\nexec python3 ' + shlex.quote(str(self.system / 'scripts/distribution.py')) + ' "$@"\n')
        self.wrapper.chmod(0o755)

    def artifact_record(self):
        inventory = {str(rel): {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
                     for path, rel in d.files(self.system)}
        (self.system / 'ARTIFACT-CONTENTS.json').write_text(json.dumps(inventory, sort_keys=True) + '\n')

    def activate_files(self, source, handoff=None):
        environment = dict(os.environ)
        if handoff:
            environment.update(CEDAR_INSTALLER_CHANNEL=handoff['channel'], CEDAR_INSTALLER_COMMIT=handoff['commit'],
                               CEDAR_INSTALLER_SOURCE_DIGEST=handoff['sourceDigest'])
        host = FakeHost(home=str(self.home), environ=environment, which=[])
        version = (source / 'VERSION').read_text().strip()
        facts = {'cedarVersion': version, 'installerVersion': version, 'environment': {'id': 'plain-hyprland'}}
        context = steps.Context(host, source, facts, {}, {'session': False}, None, lambda *args: None)
        context._modules['distribution'] = d
        operation = operations.Operation('runtime', 'Runtime', '', steps.runtime_run)
        # No Qt session exists in this test; validate still checks real runtime
        # files, while all writes and release checks are the production code.
        with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(d.shutil, 'which', return_value=None), \
             mock.patch.object(d, 'ensure_unlocked'), mock.patch.object(d, 'release_in_use', return_value=False), \
             contextlib.redirect_stdout(io.StringIO()):
            steps.runtime_run(context, operation)
            self.assertTrue(steps.runtime_verify(context, operation))
            steps.verify_run(context, operation)
        return d.installed()

    def cli(self, executable, *arguments):
        result = subprocess.run([str(executable), *arguments], env=dict(os.environ), cwd=self.base,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.blocked.exists(), self.blocked.read_text() if self.blocked.exists() else '')
        return result.stdout

    @unittest.skipIf(os.getuid() == 0, 'CEDAR intentionally refuses root CLI activation')
    def test_package_install_upgrade_and_both_launchers_stay_offline(self):
        preserved = {
            self.home / 'config/hypr/hyprland.conf': b'# user desktop settings\n',
            self.home / 'config/cedar/preferences.json': b'{"custom": "keep"}\n',
            self.home / 'config/cedar/plugins/local.js': b'// user plugin\n',
            self.home / 'Pictures/wallpapers/personal.txt': b'user wallpaper library\n',
        }
        for path, content in preserved.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        initial = update.content_digest(self.system)
        artifact = (self.system / 'ARTIFACT-CONTENTS.json').read_bytes()
        self.assertIn('cedar-install', self.cli(self.wrapper, 'installer', '--version'))
        self.assertEqual(update.default_channel(self.system), 'package')
        first = self.activate_files(self.system)
        self.assertNotEqual(first, self.system)
        self.assertEqual(update.content_digest(first), initial)
        self.assertEqual(update.installed_channel(), 'package')
        profile = self.home / 'config/quickshell/cedar'
        self.assertEqual(profile.resolve(), first)
        self.assertEqual(update.content_digest(self.system), initial)
        self.assertEqual((self.system / 'ARTIFACT-CONTENTS.json').read_bytes(), artifact)
        for launcher in (self.wrapper, d.paths()['bin']):
            self.assertIn('up to date with the system package', self.cli(launcher, 'update', '--no-gui'))
            self.assertIn('up to date with the system package', self.cli(launcher, 'installer', '--update', '--no-gui'))

        # Model a package-manager upgrade in the private prefix. Both launchers
        # must select the new packaged installer, not the old per-user copy.
        (self.system / 'VERSION').write_text('99.0.1\n')
        self.artifact_record()
        upgraded_digest = update.content_digest(self.system)
        for launcher in (self.wrapper, d.paths()['bin']):
            self.assertIn('99.0.1', self.cli(launcher, 'installer', '--version'))
        with mock.patch.object(update.Updater, 'managed_git', side_effect=AssertionError('No Git for packages')), \
             mock.patch.object(update.subprocess, 'run', side_effect=AssertionError('No external command for package preparation')):
            result = update.Updater(first, channel=update.default_channel(first), environ=dict(os.environ)).run()
        self.assertFalse(result['current'])
        snapshot = Path(result['source'])
        self.assertEqual(snapshot.parent.name, 'package')
        self.assertEqual(update.content_digest(snapshot), upgraded_digest)
        second = self.activate_files(snapshot, result)
        self.assertNotEqual(first, second)
        self.assertEqual(profile.resolve(), second)
        self.assertEqual(update.installed_channel(), 'package')
        self.assertEqual(update.content_digest(first), initial, 'old immutable release remains intact')
        self.assertEqual(update.content_digest(self.system), upgraded_digest)
        self.assertIn('up to date with the system package', self.cli(d.paths()['bin'], 'update', '--no-gui'))
        engine = Engine(second, FakeHost(home=str(self.home), environ=dict(os.environ), which=[]))
        self.assertEqual(engine.selected_channel(), 'package')
        self.assertFalse((self.home / 'state/cedar/installer/update-cache').exists())
        self.assertFalse(self.blocked.exists())
        self.assertEqual({path: path.read_bytes() for path in preserved}, preserved)

    @unittest.skipIf(os.getuid() == 0, 'CEDAR intentionally refuses root CLI activation')
    def test_missing_system_package_never_falls_back_to_git(self):
        self.activate_files(self.system)
        os.environ['CEDAR_SYSTEM_SOURCE'] = str(self.base / 'missing package')
        result = subprocess.run([str(d.paths()['bin']), 'update', '--no-gui'], env=dict(os.environ), cwd=self.base,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('No CEDAR system package is installed', result.stdout)
        self.assertEqual(update.installed_channel(), 'package')
        self.assertFalse(self.blocked.exists())

    @unittest.skipIf(os.getuid() == 0, 'CEDAR intentionally refuses root CLI activation')
    def test_older_source_release_keeps_its_installer_and_archive_update(self):
        # An upgraded system launcher or a newer recovery launcher after a
        # rollback can select an installer written before the package channel.
        legacy = self.base / 'older-source'
        shutil.copytree(self.system, legacy)
        updater = legacy / 'installer/engine/update.py'
        updater.write_text(updater.read_text().replace('def default_channel(', 'def future_default_channel('))
        self.activate_files(legacy)
        self.assertEqual(update.installed_channel(), '')
        for launcher in (self.wrapper, d.paths()['bin']):
            self.assertIn('cedar-install', self.cli(launcher, 'installer', '--version'))
            result = subprocess.run([str(launcher), 'update'], env=dict(os.environ), cwd=self.base,
                                    text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('cedar update ARCHIVE --signature SIGNATURE', result.stderr)
            self.assertNotIn('Traceback', result.stderr)
        self.assertFalse(self.blocked.exists())

    def test_fedora_bootstrap_uses_rpm_status_not_translated_output(self):
        # These are temporary scripts, never the machine's package tools.
        (self.bin / 'pacman').unlink()
        (self.bin / 'python3').unlink()
        recorded = self.base / 'dnf-arguments'
        programs = {
            'id': 'printf "1000\\n"\n',
            'rpm': 'if [ "$2" = quickshell ]; then printf "Paket nicht installiert\\n" >&2; exit 1; fi\n',
            'sudo': 'exec "$@"\n',
            'dnf': 'printf "%s\\n" "$@" > ' + shlex.quote(str(recorded)) + '\n',
            'python3': 'exit 0\n',
        }
        for name, script in programs.items():
            (self.bin / name).write_text('#!/bin/sh\n' + script)
            (self.bin / name).chmod(0o755)
        for name in ('dirname', 'sed'):
            (self.bin / name).symlink_to('/usr/bin/' + name)
        result = subprocess.run(['/bin/sh', str(self.system / 'install.sh'), '--no-gui'], env=dict(os.environ),
                                cwd=self.base, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(recorded.read_text().splitlines(), ['install', 'quickshell'])
        self.assertFalse(self.blocked.exists())


if __name__ == '__main__':
    unittest.main()
