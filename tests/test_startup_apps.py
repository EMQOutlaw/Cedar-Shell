"""Exercise startup entry edits against isolated config and data directories."""
from pathlib import Path
import json,os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class StartupApps(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.home=Path(self.tmp.name)
        self.config=self.home/'config';self.system=self.home/'xdg';self.data=self.home/'data'
        (self.system/'autostart').mkdir(parents=True);(self.data/'applications').mkdir(parents=True);(self.config/'hypr').mkdir(parents=True)
        self.env={**os.environ,'HOME':str(self.home),'XDG_CONFIG_HOME':str(self.config),'XDG_CONFIG_DIRS':str(self.system),'XDG_DATA_HOME':str(self.data),'XDG_DATA_DIRS':str(self.home/'nowhere'),'XDG_CURRENT_DESKTOP':'Hyprland'}
        (self.system/'autostart/vendor-agent.desktop').write_text('[Desktop Entry]\nType=Application\nName=Vendor Agent\nExec=/usr/bin/true --agent %U\nIcon=agent\n')
        (self.system/'autostart/gnome-only.desktop').write_text('[Desktop Entry]\nType=Application\nName=GNOME Only\nExec=/usr/bin/true\nOnlyShowIn=GNOME;\n')
        (self.data/'applications/cedar-test-editor.desktop').write_text('[Desktop Entry]\nType=Application\nName=Test Editor\nExec=/usr/bin/true %U\nIcon=editor\nCategories=TextEditor;\n')
        (self.config/'hypr/autostart.lua').write_text('-- o.launch_on_start("commented")\no.launch_on_start("my-service")\no.exec_on_start(\'raw-cmd --flag\')\n')
    def request(self,value):
        p=subprocess.run(['python3',str(ROOT/'scripts/startup_apps.py')],input=json.dumps(value),capture_output=True,text=True,env=self.env,check=True)
        return json.loads(p.stdout)
    def rows(self,result):
        return {e['id']:e for e in result['data']['entries']}
    def test_lists_system_entries_with_desktop_filters_and_hyprland_lines(self):
        result=self.request({'action':'list'});self.assertTrue(result['ok'],result);rows=self.rows(result)
        agent=rows['vendor-agent.desktop']
        self.assertEqual((agent['source'],agent['enabled'],agent['removable'],agent['exec']),('system',True,False,'/usr/bin/true --agent'))
        self.assertEqual(agent['unit'],'app-vendor\\x2dagent@autostart.service')
        self.assertEqual((rows['gnome-only.desktop']['enabled'],rows['gnome-only.desktop']['reason']),(False,'other-desktop'))
        self.assertEqual([c['command'] for c in result['data']['hyprland']['commands']],['my-service','raw-cmd --flag'])
        self.assertNotIn(str(self.home),json.dumps(result['data']['hyprland']),'The Lua path is reported as a tilde path')
    def test_disable_system_entry_writes_hidden_override_and_remove_restores(self):
        rows=self.rows(self.request({'action':'set_enabled','id':'vendor-agent.desktop','enabled':False}))
        override=self.config/'autostart/vendor-agent.desktop'
        self.assertEqual(override.read_text().splitlines()[:2],['[Desktop Entry]','Hidden=true'])
        self.assertEqual((rows['vendor-agent.desktop']['enabled'],rows['vendor-agent.desktop']['overrides'],rows['vendor-agent.desktop']['name']),(False,True,'Vendor Agent'))
        self.assertTrue((self.system/'autostart/vendor-agent.desktop').exists(),'System files are never touched')
        rows=self.rows(self.request({'action':'set_enabled','id':'vendor-agent.desktop','enabled':True}))
        self.assertFalse(override.exists());self.assertTrue(rows['vendor-agent.desktop']['enabled'])
        self.request({'action':'set_enabled','id':'vendor-agent.desktop','enabled':False})
        rows=self.rows(self.request({'action':'remove','id':'vendor-agent.desktop'}))
        self.assertFalse(override.exists());self.assertEqual(rows['vendor-agent.desktop']['source'],'system')
    def test_add_app_copies_the_installed_entry(self):
        rows=self.rows(self.request({'action':'add_app','id':'cedar-test-editor.desktop'}))
        text=(self.config/'autostart/cedar-test-editor.desktop').read_text()
        self.assertIn('Exec=/usr/bin/true %U',text);self.assertIn('X-CEDAR-Startup=true',text)
        row=rows['cedar-test-editor.desktop']
        self.assertEqual((row['source'],row['kind'],row['removable'],row['enabled'],row['icon']),('cedar','app',True,True,'editor'))
        result=self.request({'action':'add_app','id':'missing.desktop'});self.assertFalse(result['ok'])
        result=self.request({'action':'add_app','id':'../escape.desktop'});self.assertFalse(result['ok'])
    def test_add_command_quotes_and_wraps_shell_syntax(self):
        rows=self.rows(self.request({'action':'add_command','command':'echo hi && sleep 1'}))
        path=self.config/'autostart/cedar-echo.desktop';text=path.read_text()
        self.assertIn("Exec=sh -c 'echo hi && sleep 1'",text);self.assertIn('X-CEDAR-Command=true',text)
        self.assertEqual((rows['cedar-echo.desktop']['kind'],rows['cedar-echo.desktop']['name']),('command','echo'))
        rows=self.rows(self.request({'action':'add_command','name':'Sync notes','command':'rsync -a "/tmp/a b" /tmp/c'}))
        self.assertIn("Exec=rsync -a '/tmp/a b' /tmp/c",(self.config/'autostart/cedar-sync-notes.desktop').read_text())
        self.assertEqual(rows['cedar-sync-notes.desktop']['name'],'Sync notes')
        for bad in ['','   ',"unbalanced 'quote",'two\nlines']:
            self.assertFalse(self.request({'action':'add_command','command':bad})['ok'],bad)
        self.request({'action':'add_command','command':'echo again'})
        self.assertTrue((self.config/'autostart/cedar-echo-2.desktop').exists(),'A second command with the same name gets its own file')
    def test_toggle_user_entry_keeps_its_content(self):
        self.request({'action':'add_command','name':'Hello','command':'echo hi'})
        path=self.config/'autostart/cedar-hello.desktop'
        rows=self.rows(self.request({'action':'set_enabled','id':'cedar-hello.desktop','enabled':False}))
        self.assertFalse(rows['cedar-hello.desktop']['enabled']);self.assertIn('Hidden=true',path.read_text());self.assertIn('Exec=echo hi',path.read_text())
        rows=self.rows(self.request({'action':'set_enabled','id':'cedar-hello.desktop','enabled':True}))
        self.assertTrue(rows['cedar-hello.desktop']['enabled']);self.assertNotIn('Hidden',path.read_text());self.assertIn('Exec=echo hi',path.read_text())
        rows=self.rows(self.request({'action':'remove','id':'cedar-hello.desktop'}))
        self.assertFalse(path.exists());self.assertNotIn('cedar-hello.desktop',rows)
    def test_system_entries_cannot_be_removed_and_unknown_actions_fail(self):
        self.assertFalse(self.request({'action':'remove','id':'vendor-agent.desktop'})['ok'])
        self.assertFalse(self.request({'action':'remove','id':'nothing.desktop'})['ok'])
        self.assertFalse(self.request({'action':'explode'})['ok'])
        self.assertFalse(self.request({'action':'run','id':'gnome-only.desktop'})['ok'],'A disabled entry is not launched')
if __name__=='__main__':unittest.main()
