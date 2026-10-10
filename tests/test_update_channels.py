"""Branch update integration tests; all remotes, installed releases and homes are local fixtures."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from installer.engine import update
from installer.engine.host import Host
from installer.engine.server import Engine
from installer import cedar_install


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cedar branches 雨 ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home), 'XDG_STATE_HOME': str(self.home / 'state'),
                    'XDG_CONFIG_HOME': str(self.home / 'config'), 'XDG_DATA_HOME': str(self.home / 'data'),
                    'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1',
                    'GIT_AUTHOR_NAME': 'CEDAR Test', 'GIT_AUTHOR_EMAIL': 'test@example.invalid',
                    'GIT_COMMITTER_NAME': 'CEDAR Test', 'GIT_COMMITTER_EMAIL': 'test@example.invalid'}
        for key in ('CEDAR_INSTALLER_CHANNEL', 'CEDAR_INSTALLER_SOURCE_DIGEST', 'CEDAR_INSTALLER_COMMIT', 'CEDAR_INSTALLER_UPDATE_ID'):
            self.env.pop(key, None)
        self.state = self.home / 'state/cedar/installer'
        self.origin = self.root / 'origin.git'
        self.git(self.root, 'init', '--bare', '--quiet', '--initial-branch=main', str(self.origin))
        self.seed = self.root / 'seed'
        self.seed.mkdir()
        self.git(self.seed, 'init', '--quiet', '--initial-branch=main')
        (self.seed / 'installer').mkdir()
        (self.seed / 'data').mkdir()
        (self.seed / 'installer/cedar_install.py').write_text('# fixture installer\n')
        (self.seed / 'VERSION').write_text('1.0.0\n')
        (self.seed / 'shell.qml').write_text('stable\n')
        (self.seed / 'data/source-files.json').write_text(json.dumps(['VERSION', 'shell.qml', 'installer/cedar_install.py', 'data/source-files.json']))
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '--quiet', '-m', 'stable')
        self.git(self.seed, 'remote', 'add', 'origin', str(self.origin))
        self.git(self.seed, 'push', '--quiet', '-u', 'origin', 'main')
        self.git(self.seed, 'switch', '--quiet', '-c', 'dev')
        self.advance('development')
        self.source = self.root / 'user checkout'
        self.git(self.root, 'clone', '--quiet', str(self.origin), str(self.source))
        self.events = []

    def git(self, cwd, *args):
        return subprocess.run(['git', '-C', str(cwd), *args], check=True, capture_output=True, text=True, env=self.env).stdout.strip()

    def advance(self, text, branch='dev'):
        self.git(self.seed, 'switch', '--quiet', branch)
        (self.seed / 'shell.qml').write_text(text + '\n')
        self.git(self.seed, 'commit', '--quiet', '-am', text)
        self.git(self.seed, 'push', '--quiet', '-u', 'origin', branch)

    def updater(self, channel='stable', source=None, **kwargs):
        return update.Updater(source or self.source, channel=channel, repository=self.origin,
                              environ=self.env, state_dir=self.state,
                              emit=lambda event, data: self.events.append((event, data)), **kwargs)

    def install(self, result):
        """Simulate the existing verified distribution copy, then use the real final record helper."""
        destination = self.home / 'data/cedar/releases' / result['sourceDigest']
        if not destination.exists():
            shutil.copytree(result['source'], destination)
        current = self.home / 'data/cedar/current'
        current.unlink(missing_ok=True)
        current.symlink_to(destination)
        env = {**self.env, 'CEDAR_INSTALLER_CHANNEL': result['channel'], 'CEDAR_INSTALLER_COMMIT': result['commit'],
               'CEDAR_INSTALLER_SOURCE_DIGEST': result['sourceDigest']}
        marker = self.home / 'config/cedar/installation.json'
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(json.dumps({'update': update.install_provenance(result['source'], destination, env)}))
        return current

    def test_main_dev_main_and_same_version_new_commits(self):
        stable = self.updater().run()
        self.assertEqual(stable['branch'], 'main')
        self.assertFalse(stable['current'])
        self.install(stable)
        self.assertTrue(self.updater().run()['current'])
        development = self.updater('development').run()
        self.assertEqual(development['version'], stable['version'])
        self.assertFalse(development['current'])
        self.install(development)
        self.assertEqual(update.installed_channel(self.env), 'development')
        self.assertTrue(self.updater('development').run()['current'])
        self.advance('new behavior, same version')
        later = self.updater('development').run()
        self.assertNotEqual(later['commit'], development['commit'])
        self.assertFalse(later['current'])
        self.install(later)
        back = self.updater('stable').run()
        self.assertEqual(back['commit'], stable['commit'])
        self.assertFalse(back['current'])
        self.install(back)
        self.assertEqual(update.installed_channel(self.env), 'stable')
        self.assertTrue(self.updater().run()['current'])

    def test_identical_branch_tips_still_allow_persisting_selection(self):
        self.git(self.seed, 'push', '--quiet', '--force', 'origin', 'main:dev')
        stable = self.updater().run()
        self.install(stable)
        dev = self.updater('development').run()
        self.assertEqual(dev['commit'], stable['commit'])
        self.assertFalse(dev['changed'])
        self.assertFalse(dev['current'])
        self.install(dev)
        self.assertTrue(self.updater('development').run()['current'])

    def test_cancelled_and_failed_install_same_version_still_needs_install(self):
        self.install(self.updater().run())
        updater = self.updater('development')
        result = updater.run()
        updater.cancel()
        with self.assertRaises(update.Guidance):
            updater.proceed()
        self.assertEqual(update.installed_channel(self.env), 'stable')
        self.assertFalse(self.updater('development').run()['current'])
        # Failed verification: no channel can be inferred from a release copied
        # before the final record was written, even though VERSION is unchanged.
        current = self.home / 'data/cedar/current'
        candidate = self.home / 'data/cedar/releases/incomplete'
        shutil.copytree(result['source'], candidate)
        current.unlink()
        current.symlink_to(candidate)
        self.assertEqual(update.installed_channel(self.env), '')
        self.assertFalse(self.updater('development').run()['current'])

    def test_user_checkout_dirty_detached_and_local_history_untouched(self):
        (self.source / 'shell.qml').write_text('my local commit\n')
        self.git(self.source, 'commit', '--quiet', '-am', 'my branch')
        self.git(self.source, 'checkout', '--quiet', '--detach')
        (self.source / 'VERSION').write_text('my dirty version\n')
        (self.source / 'notes').write_text('my note\n')
        before = (self.git(self.source, 'rev-parse', 'HEAD'), self.git(self.source, 'status', '--porcelain'),
                  self.git(self.source, 'remote', '-v'), self.git(self.source, 'reflog'), self.git(self.source, 'stash', 'list'))
        self.updater('development').run()
        self.updater('stable').run()
        after = (self.git(self.source, 'rev-parse', 'HEAD'), self.git(self.source, 'status', '--porcelain'),
                 self.git(self.source, 'remote', '-v'), self.git(self.source, 'reflog'), self.git(self.source, 'stash', 'list'))
        self.assertEqual(before, after)
        self.assertEqual((self.source / 'VERSION').read_text(), 'my dirty version\n')

    def test_archive_source_and_missing_branch_failure_leave_installed_state(self):
        archive = self.root / 'archive'
        shutil.copytree(self.source, archive, ignore=shutil.ignore_patterns('.git'))
        self.install(self.updater(source=archive).run())
        self.git(self.seed, 'push', '--quiet', 'origin', '--delete', 'dev')
        with self.assertRaises(update.Guidance) as stopped:
            self.updater('development', source=archive).run()
        self.assertEqual(stopped.exception.code, 'branch-missing')
        self.assertEqual(update.installed_channel(self.env), 'stable')
        self.assertEqual(self.events[-1][0], 'update-error')
        self.assertEqual(self.events[-1][1]['channel'], 'development')

    def test_unavailable_remote_does_not_offer_stale_cached_candidate(self):
        self.install(self.updater('development').run())
        remote = self.origin.with_suffix('.gone')
        self.origin.rename(remote)
        with self.assertRaises(update.Guidance):
            self.updater('development').run()
        self.assertEqual(update.installed_channel(self.env), 'development')

    def test_invalid_channels_and_concurrent_operations_are_rejected(self):
        for channel in ('main', 'dev', '--upload-pack=bad', '../dev', '', [], {}):
            with self.assertRaises(update.Guidance):
                self.updater(channel)
        with update.update_lock(self.state):
            with self.assertRaises(update.Guidance) as stopped:
                self.updater().run()
        self.assertEqual(stopped.exception.code, 'busy')

    def test_snapshot_tamper_blocks_reuse_and_handoff(self):
        updater = self.updater('development')
        result = updater.run()
        (Path(result['source']) / 'shell.qml').write_text('changed after fetch\n')
        with self.assertRaises(update.Guidance):
            updater.proceed()
        with self.assertRaises(update.Guidance):
            self.updater('development').run()
        self.assertEqual(update.installed_channel(self.env), '')

    def test_archive_link_is_rejected(self):
        (self.seed / 'outside').symlink_to('/etc/passwd')
        self.git(self.seed, 'add', 'outside')
        self.git(self.seed, 'commit', '--quiet', '-m', 'unsafe link')
        self.git(self.seed, 'push', '--quiet')
        with self.assertRaises(update.Guidance) as stopped:
            self.updater('development').run()
        self.assertEqual(stopped.exception.code, 'archive')

    def test_handoff_sessions_are_isolated_and_source_is_rechecked(self):
        self.env['CEDAR_INSTALLER_UPDATE_ID'] = 'a' * 32
        first = self.updater()
        first.run()
        first.proceed()
        self.env['CEDAR_INSTALLER_UPDATE_ID'] = 'b' * 32
        second = self.updater('development')
        result = second.run()
        second.proceed()
        taken = update.take_handoff(self.state, session_id='a' * 32)
        self.assertEqual(taken['channel'], 'stable')
        self.assertIsNone(update.take_handoff(self.state, session_id='a' * 32))
        (Path(result['source']) / 'shell.qml').write_text('corrupt\n')
        self.assertIsNone(update.take_handoff(self.state, session_id='b' * 32))

    def test_record_is_bound_to_path_content_and_valid_shape(self):
        result = self.updater().run()
        current = self.install(result)
        (current / 'shell.qml').write_text('modified installed runtime\n')
        self.assertEqual(update.installed_channel(self.env), '')
        marker = self.home / 'config/cedar/installation.json'
        for record in ([], {'update': []}, {'update': None}, {'update': {'channel': []}}, 'x'):
            marker.write_text(json.dumps(record))
            self.assertEqual(update.installed_channel(self.env), '')

    def test_verified_provenance_is_not_written_for_an_arbitrary_source_install(self):
        result = self.updater('development').run()
        self.install(result)
        self.assertEqual(update.install_provenance(self.source, result['source'], self.env), {})

    def test_handoff_strips_stale_source_channel_and_second_update(self):
        result = self.updater('development').run()
        with mock.patch.object(os, 'execve') as execute:
            cedar_install.start_updated(result, ['--source', '/old checkout', '--channel=stable', '--update', '--source=/older', '--channel', 'stable', '--yes'])
        executable, argv, env = execute.call_args.args
        self.assertEqual(argv.count('--source'), 1)
        self.assertEqual(argv[argv.index('--source') + 1], result['source'])
        self.assertNotIn('--channel', argv)
        self.assertNotIn('--update', argv)
        self.assertEqual(argv.count('--updated'), 1)
        self.assertIn('--yes', argv)
        self.assertEqual(env['CEDAR_INSTALLER_CHANNEL'], 'development')
        self.assertEqual(env['CEDAR_INSTALLER_COMMIT'], result['commit'])

    def test_engine_defaults_to_successfully_installed_channel_and_validates_input(self):
        self.install(self.updater('development').run())
        engine = Engine(self.source, Host(environ=self.env))
        self.addCleanup(lambda: engine.log.close() if engine.log else None)
        self.assertEqual(engine.selected_channel(), 'development')
        with self.assertRaises(update.Guidance):
            engine.update('some-other-branch')
        self.assertEqual(engine.selected_channel(), 'development')
        self.assertEqual(engine.updater().channel, 'development')

    def test_resume_restores_exact_update_context_or_refuses_another_revision(self):
        result = self.updater('development').run()
        context = {key: result[key] for key in ('source', 'channel', 'commit', 'sourceDigest')}
        wrong = Engine(self.source, Host(environ=self.env))
        with self.assertRaisesRegex(RuntimeError, 'different prepared revision'):
            wrong.restore_update_context({'updateContext': context})
        self.assertNotIn('CEDAR_INSTALLER_CHANNEL', wrong.host.environ)
        resumed = Engine(result['source'], Host(environ=self.env))
        resumed.restore_update_context({'updateContext': context})
        self.assertEqual(resumed.host.environ['CEDAR_INSTALLER_CHANNEL'], 'development')
        self.assertEqual(resumed.host.environ['CEDAR_INSTALLER_COMMIT'], result['commit'])
        for malformed in ([], {'channel': 'development'}, {**context, 'sourceDigest': 'not a digest'}):
            with self.assertRaises((RuntimeError, update.Guidance)):
                resumed.restore_update_context({'updateContext': malformed})

    def test_cancellation_during_fetch_preserves_runtime_and_next_check_can_retry(self):
        self.install(self.updater().run())
        updater = self.updater('development')
        def cancel_on_fetch(event, data):
            if event == 'operation' and data['id'] == 'fetch' and data['state'] == 'running':
                updater.cancel()
        updater.emit = cancel_on_fetch
        with self.assertRaises(update.Guidance) as stopped:
            updater.run()
        self.assertEqual(stopped.exception.code, 'cancelled')
        self.assertEqual(update.installed_channel(self.env), 'stable')
        self.assertFalse(updater.prepared)
        updater.emit = lambda *_: None
        self.assertFalse(updater.run()['current'])

    def test_cli_channel_requires_an_update(self):
        with mock.patch('sys.stderr'):
            with self.assertRaises(SystemExit) as stopped:
                cedar_install.main(['--channel', 'development', '--no-gui'])
        self.assertEqual(stopped.exception.code, 2)

    def test_claimed_channel_without_checked_revision_is_refused(self):
        result = self.updater().run()
        with self.assertRaisesRegex(RuntimeError, 'checked update'):
            update.install_provenance(result['source'], result['source'], {**self.env, 'CEDAR_INSTALLER_CHANNEL': 'development'})

    def test_mode_only_update_gets_its_own_release_and_verifies_permissions(self):
        from scripts import distribution
        stable = self.updater().run()
        self.install(stable)
        self.git(self.seed, 'switch', '--quiet', 'main')
        installer = self.seed / 'installer/cedar_install.py'
        installer.chmod(0o755)
        self.git(self.seed, 'commit', '--quiet', '-am', 'make installer executable')
        self.git(self.seed, 'push', '--quiet')
        executable = self.updater().run()
        self.assertFalse(executable['current'])
        self.assertEqual(stable['version'], executable['version'])
        self.assertNotEqual(distribution.plan_install(Path(stable['source']))['release'],
                            distribution.plan_install(Path(executable['source']))['release'])
        candidate = Path(executable['source'])
        inventory = {'installer/cedar_install.py': {'sha256': distribution.digest(candidate / 'installer/cedar_install.py'), 'mode': 0o755}}
        self.assertTrue(distribution.verify_tree(candidate, inventory))
        (candidate / 'installer/cedar_install.py').chmod(0o644)
        with self.assertRaises(distribution.Refused):
            distribution.verify_tree(candidate, inventory)


if __name__ == '__main__':
    unittest.main()
