"""The Field Station update: pull first, restore only an active session, never reset a checkout."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import distribution as d
import desktop_runtime as runtime
import update_checkout as u

def git(cwd,*args):
    env={**os.environ,'GIT_AUTHOR_NAME':'t','GIT_AUTHOR_EMAIL':'t@example.invalid','GIT_COMMITTER_NAME':'t','GIT_COMMITTER_EMAIL':'t@example.invalid','GIT_CONFIG_GLOBAL':os.devnull,'GIT_CONFIG_NOSYSTEM':'1'}
    return subprocess.run(['git','-C',str(cwd),*args],check=True,text=True,capture_output=True,env=env).stdout.strip()

class Checkout(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cedar update ');self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.origin=self.root/'origin.git';git(self.root,'init','-q','--bare','-b','main',str(self.origin))
        seed=self.root/'seed';seed.mkdir();git(seed,'init','-q','-b','main');(seed/'install.sh').write_text('#!/bin/sh\n');(seed/'VERSION').write_text('1\n')
        git(seed,'add','.');git(seed,'commit','-q','-m','one');git(seed,'remote','add','origin',str(self.origin));git(seed,'push','-q','-u','origin','main')
        self.seed=seed;self.checkout=self.root/'cedar-shell';git(self.root,'clone','-q',str(self.origin),str(self.checkout))
    def upstream(self,version):
        (self.seed/'VERSION').write_text(version+'\n');git(self.seed,'commit','-q','-am','v'+version);git(self.seed,'push','-q')
    def test_resolution_order_and_refusals(self):
        env={'HOME':str(self.root)}
        self.assertEqual(u.resolve_checkout([],env),self.checkout.resolve())
        self.assertEqual(u.resolve_checkout([],{**env,'CEDAR_CHECKOUT':str(self.checkout)}),self.checkout.resolve())
        self.assertEqual(u.resolve_checkout([str(self.checkout)],{'HOME':'/nonexistent'}),self.checkout.resolve())
        with self.assertRaises(d.Refused) as missing:u.resolve_checkout([],{'HOME':str(self.root/'elsewhere')})
        self.assertIn('git clone',str(missing.exception))
        plain=self.root/'plain';plain.mkdir();(plain/'install.sh').write_text('')
        with self.assertRaises(d.Refused):u.resolve_checkout([str(plain)],env)
        (self.checkout/'install.sh').unlink()
        with self.assertRaises(d.Refused):u.resolve_checkout([str(self.checkout)],env)
    def test_fast_forward_pull_updates_and_keeps_unrelated_edits(self):
        self.upstream('2');note=self.checkout/'notes.local';note.write_text('mine')
        with patch.object(u,'say'):u.pull(self.checkout)
        self.assertEqual((self.checkout/'VERSION').read_text(),'2\n');self.assertEqual(note.read_text(),'mine')
    def test_broken_orig_head_is_cleared_and_the_pull_proceeds(self):
        self.upstream('2');scratch=self.checkout/'.git/ORIG_HEAD';scratch.write_bytes(b'\x00garbage\n')
        with patch.object(u,'say') as said:u.pull(self.checkout)
        self.assertEqual((self.checkout/'VERSION').read_text(),'2\n')
        self.assertTrue(any('ORIG_HEAD' in str(call) for call in said.call_args_list))
        # A readable ORIG_HEAD is left alone.
        head=git(self.checkout,'rev-parse','HEAD');scratch.write_text(head+'\n')
        self.assertFalse(u.clear_broken_scratch_ref(self.checkout));self.assertEqual(scratch.read_text().strip(),head)
    def test_divergent_or_edited_history_is_refused_without_reset(self):
        self.upstream('2');(self.checkout/'VERSION').write_text('local\n');git(self.checkout,'commit','-q','-am','local work')
        with patch.object(u,'say'),self.assertRaises(d.Refused):u.pull(self.checkout)
        self.assertEqual((self.checkout/'VERSION').read_text(),'local\n');self.assertEqual(git(self.checkout,'log','--oneline').count('\n'),1)
        self.upstream('3');git(self.checkout,'reset','-q','--hard','origin/main');(self.checkout/'VERSION').write_text('edited\n')
        self.upstream('4')
        with patch.object(u,'say'),self.assertRaises(d.Refused):u.pull(self.checkout)
        self.assertEqual((self.checkout/'VERSION').read_text(),'edited\n')

class Restore(unittest.TestCase):
    def test_inactive_session_never_runs_restore(self):
        with patch.object(u.subprocess,'run') as run,patch.object(u,'say'):
            self.assertFalse(u.restore_if_active(active=False,command=['cedar']))
        run.assert_not_called()
    def test_active_session_restores_through_cedar_and_reports_failure(self):
        with patch.object(u.subprocess,'run') as run,patch.object(u,'say'):
            run.return_value.returncode=0
            self.assertTrue(u.restore_if_active(active=True,command=['cedar']))
            self.assertEqual(run.call_args.args[0],['cedar','restore'])
            run.return_value.returncode=1
            with self.assertRaises(d.Refused):u.restore_if_active(active=True,command=['cedar'])
    def test_active_session_without_launcher_is_refused(self):
        with patch.object(u,'cedar_command',return_value=None),patch.object(u,'say'),self.assertRaises(d.Refused):u.restore_if_active(active=True)
    def test_main_orders_pull_before_restore_before_install(self):
        order=[]
        with patch.object(u.sys.stdin,'isatty',return_value=True),patch.object(u,'input'),patch.object(u,'say'),\
             patch.object(u,'resolve_checkout',return_value=Path('/checkout')),patch.object(u,'describe'),\
             patch.object(u,'pull',side_effect=lambda c:order.append('pull')),\
             patch.object(u,'restore_if_active',side_effect=lambda:order.append('restore') or True),\
             patch.object(u,'install',side_effect=lambda c:order.append('install')):
            u.main([])
        self.assertEqual(order,['pull','restore','install'])
    def test_main_requires_a_terminal(self):
        with patch.object(u.sys.stdin,'isatty',return_value=False),self.assertRaises(d.Refused):u.main([])

class Terminal(unittest.TestCase):
    def argv(self,available,terminal_env='',command=('python3','x.py')):
        with patch.object(runtime.shutil,'which',side_effect=lambda n:'/usr/bin/'+n if n in available else None),patch.dict(os.environ,{'TERMINAL':terminal_env}):
            return runtime.terminal_argv(command)
    def test_positional_terminals(self):
        self.assertEqual(self.argv({'xdg-terminal-exec','alacritty'}),['xdg-terminal-exec','python3','x.py'])
        self.assertEqual(self.argv({'foot'}),['foot','python3','x.py'])
        self.assertEqual(self.argv({'kitty'}),['kitty','python3','x.py'])
    def test_flag_terminals_and_env_choice(self):
        self.assertEqual(self.argv({'alacritty'}),['alacritty','-e','python3','x.py'])
        self.assertEqual(self.argv({'ghostty'},terminal_env='ghostty --class=x'),['ghostty','--class=x','-e','python3','x.py'])
        self.assertEqual(self.argv({'wezterm'}),['wezterm','start','--','python3','x.py'])
        self.assertEqual(self.argv({'foot'},command=()),['foot'])
    def test_missing_terminal_and_wrong_role(self):
        with self.assertRaises(RuntimeError):self.argv(set())
        with self.assertRaises(ValueError):runtime.launch('browser',['x'])

if __name__=='__main__':unittest.main()
