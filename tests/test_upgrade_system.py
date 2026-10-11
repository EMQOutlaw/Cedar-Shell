"""Check the interactive launcher without changing installed packages."""
from pathlib import Path
import contextlib
import io
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import upgrade_system as upgrade


class UpgradeSystem(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.output))

    def test_installed_topgrade_runs_without_forced_answers(self):
        with patch.object(upgrade.shutil, 'which', return_value='/usr/bin/topgrade'), patch.object(upgrade.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(upgrade.upgrade(), 0)
        run.assert_called_once_with(['/usr/bin/topgrade'], cwd=Path.home())

    def test_first_use_installs_then_runs_topgrade(self):
        with patch.object(upgrade.shutil, 'which', side_effect=[None, '/usr/bin/topgrade']), patch.object(upgrade, 'omarchy', return_value=True), patch('builtins.input', return_value='y'), patch.object(upgrade.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(upgrade.upgrade(), 0)
        self.assertEqual([call.args[0] for call in run.call_args_list], [['omarchy', 'pkg', 'aur', 'add', 'topgrade-bin'], ['/usr/bin/topgrade']])

    def test_declining_install_does_not_run_any_command(self):
        with patch.object(upgrade.shutil, 'which', return_value=None), patch.object(upgrade, 'omarchy', return_value=True), patch('builtins.input', return_value='n'), patch.object(upgrade.subprocess, 'run') as run:
            self.assertEqual(upgrade.upgrade(), 0)
        run.assert_not_called()

    def test_failed_install_does_not_start_upgrade(self):
        with patch.object(upgrade.shutil, 'which', return_value=None), patch.object(upgrade, 'omarchy', return_value=True), patch('builtins.input', return_value='y'), patch.object(upgrade.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)) as run:
            self.assertEqual(upgrade.upgrade(), 1)
        self.assertEqual(run.call_count, 1)

    def test_upgrade_failure_is_preserved(self):
        with patch.object(upgrade.shutil, 'which', return_value='/usr/bin/topgrade'), patch.object(upgrade.subprocess, 'run', return_value=subprocess.CompletedProcess([], 2)):
            self.assertEqual(upgrade.upgrade(), 2)
