"""Regression coverage for ownership, rollback, conflicts and untrusted values."""
from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('desktop',ROOT/'scripts/desktop.py')
d=importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

class Values(unittest.TestCase):
    def test_lua_strings_roundtrip_without_execution(self):
        value='"\\\n; os.execute("false"); -- café\x00'
        encoded=d.lua(value)
        script='local s='+encoded+'; for i=1,#s do io.write(string.byte(s,i)," ") end'
        result=subprocess.run(['lua','-'],input=script,text=True,capture_output=True,check=True)
        self.assertEqual(bytes(map(int,result.stdout.split())),value.encode())
    def test_input_rejects_unknown_and_nonfinite(self):
        for data in [{'exec':'oops'},{'sensitivity':float('nan')},{'repeat_rate':1.5},{'numlock_by_default':'false'},{'kb_layout':'us"; evil()'}]:
            with self.assertRaises((ValueError,TypeError)): d.validate_inputs(data)
    def test_nested_touchpad_is_valid_lua(self):
        text=d.render({'input':{'touchpad:tap-to-click':True,'kb_layout':'us'}})
        r=subprocess.run(['lua','-'],input='hl={config=function(c) assert(c.input.touchpad["tap-to-click"]==true) end}\n'+text,text=True,capture_output=True)
        self.assertEqual(r.returncode,0,r.stderr)
    def test_monitors_cannot_drop_output_or_inject_mode(self):
        current=[{'name':'DP-1','width':1920,'height':1080,'refreshRate':60,'availableModes':['1920x1080@60.00Hz']}]
        with self.assertRaises(ValueError): d.validate_monitors([],current)
        with self.assertRaises(ValueError): d.validate_monitors([{'name':'DP-1','mode':'os.execute()'}],current)
        item={'name':'DP-1','mode':'1920x1080@60.00','scale':1.25,'x':0,'y':0,'transform':0}
        self.assertEqual(d.validate_monitors([item],current)[0]['scale'],1.25)
    def test_keys_canonicalized(self):
        self.assertEqual(d.validate_combo('shift + super + f'),'SUPER + SHIFT + F')
        with self.assertRaises(ValueError): d.validate_combo('SUPER + " ; os.execute()')

class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.main=self.root/'hypr/hyprland.lua'; self.main.parent.mkdir()
        self.original='-- personal config\n'; self.main.write_text(self.original)
        self.own=self.root/'cedar/hypr'; self.own.mkdir(parents=True)
        self.patches=[patch.object(d,'MAIN',self.main),patch.object(d,'OWN',self.own)]
        for p in self.patches: p.start(); self.addCleanup(p.stop)
        self.state={'input':{'sensitivity':.25},'monitors':[],'bindings':[]}
    def test_first_install_only_appends_and_keeps_user_file(self):
        user=self.own/'user.lua'; user.write_text('-- never rewrite me')
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.assertTrue(self.main.read_text().startswith(self.original))
        self.assertEqual(user.read_text(),'-- never rewrite me')
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.assertEqual(self.main.read_text().count('-- CEDAR graphical settings'),1)
    def test_failed_reload_restores_config(self):
        with patch.object(d,'reload_validate',side_effect=RuntimeError('bad config')):
            with self.assertRaises(RuntimeError): d.install(self.state)
        self.assertEqual(self.main.read_text(),self.original)
        self.assertFalse((self.own/'generated.lua').exists())
    def test_display_rollback_survives_shell_and_preserves_new_user_edits(self):
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen') as process:
            result=d.install(self.state,True)
            self.assertTrue(process.call_args.kwargs['start_new_session'])
            self.main.write_text(self.main.read_text()+'-- user edit during trial\n')
            d.restore_pending('wrong-token')
            self.assertTrue((self.own/'pending.json').exists())
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_text(),self.original+'-- user edit during trial\n')
        self.assertFalse((self.own/'generated.lua').exists())
    def test_conflicting_binding_is_not_written(self):
        with patch.object(d,'snapshot',return_value={'bindings':[{'keys':'SUPER + F','description':'Files','submap':''}]}):
            with self.assertRaisesRegex(ValueError,'Files'):
                d.action({'action':'binding','keys':'SUPER + F','command':'kitty'})
        self.assertFalse((self.own/'generated.lua').exists())
    def test_keep_cannot_save_expired_trial(self):
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result=d.install(self.state,True)
            file=self.own/'pending.json'; pending=json.loads(file.read_text()); pending['deadline']=0; file.write_text(json.dumps(pending))
            d.action({'action':'keep','token':result['pending']['token']})
        self.assertFalse((self.own/'generated.lua').exists())


class PrimaryDisplay(unittest.TestCase):
    setUp = Transactions.setUp
    def test_primary_render_preserves_layout_and_runs_x11_only_on_login(self):
        state={**self.state,'mainDisplay':'DP-2'}
        text=d.render(state)
        lua_test='''
local startup
hl={
 config=function(c) if c.cursor then assert(c.cursor.default_monitor=="DP-2") end end,
 on=function(event, callback) assert(event=="hyprland.start"); startup=callback end,
 exec_cmd=function(command) assert(command=="xrandr --output DP-2 --primary") end,
 monitor=function() error("Primary selection must not change layout") end
}
'''+text+'\nassert(startup); startup()\n'
        result=subprocess.run(['lua','-'],input=lua_test,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
    def test_disconnected_primary_does_not_write(self):
        with patch.object(d,'hypr',return_value=[{'name':'DP-1'}]):
            with self.assertRaisesRegex(ValueError,'disconnected'): d.apply_primary(self.state,'DP-2')
        self.assertFalse((self.own/'generated.lua').exists())
    def test_x11_primary_parser(self):
        self.assertEqual(d.x11_outputs('DP-1 connected primary 3440x1440+0+0\nDP-2 connected 2560x1440+3440+0\nHDMI-A-1 disconnected'),(['DP-1','DP-2'],'DP-1'))
    def test_x11_failure_restores_files_and_previous_primary(self):
        calls=[]
        def command(args):
            calls.append(args)
            if args==['xrandr','--query']: return 'DP-1 connected primary 3440x1440+0+0\nDP-2 connected 2560x1440+3440+0'
            if args==['xrandr','--output','DP-2','--primary']: raise RuntimeError('x11 failed')
            if 'getoption' in args: return '{"str":"DP-2"}'
            return ''
        with patch.object(d,'hypr',return_value=[{'name':'DP-2'}]), patch.object(d,'command',side_effect=command), patch.object(d,'reload_validate'), patch.object(d.shutil,'which',return_value='/usr/bin/xrandr'), patch.dict(d.os.environ,{'DISPLAY':':0'}):
            with self.assertRaisesRegex(RuntimeError,'x11 failed'): d.apply_primary(self.state,'DP-2')
        self.assertEqual(self.main.read_text(),self.original)
        self.assertFalse((self.own/'generated.lua').exists())
        self.assertIn(['xrandr','--output','DP-1','--primary'],calls)
    def test_wayland_only_session_saves_cursor_with_clear_x11_status(self):
        with patch.object(d,'hypr',return_value=[{'name':'DP-2'}]), patch.object(d,'command',return_value='{"str":"DP-2"}'), patch.object(d,'reload_validate'), patch.dict(d.os.environ,{'DISPLAY':''}):
            result=d.apply_primary(self.state,'DP-2')
        self.assertIn('X11 is unavailable',result['message'])
        self.assertEqual(json.loads((self.own/'settings.json').read_text())['mainDisplay'],'DP-2')

if __name__=='__main__': unittest.main()
