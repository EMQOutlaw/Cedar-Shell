"""Exercise real GIO association writes with isolated home/config directories."""
from pathlib import Path
import json,os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class DefaultApps(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.home=Path(self.tmp.name)
        self.env={**os.environ,'HOME':str(self.home),'XDG_CONFIG_HOME':str(self.home/'config'),'XDG_DATA_HOME':str(self.home/'data'),'XDG_STATE_HOME':str(self.home/'state'),'XDG_DATA_DIRS':str(self.home/'empty')}
        apps=self.home/'data/applications';apps.mkdir(parents=True)
        (apps/'cedar-test-editor.desktop').write_text('[Desktop Entry]\nType=Application\nName=Test Editor\nExec=/usr/bin/true %U\nMimeType=text/plain;application/json;\nCategories=TextEditor;\n')
    def request(self,value):
        p=subprocess.run(['python3',str(ROOT/'scripts/default_apps.py')],input=json.dumps(value),capture_output=True,text=True,env=self.env,check=True)
        return json.loads(p.stdout)
    def test_apply_preserves_unrelated_associations_and_uses_real_defaults(self):
        config=self.home/'config';config.mkdir();mime=config/'mimeapps.list'
        mime.write_text('[Default Applications]\nx-scheme-handler/https=keep-browser.desktop;\napplication/pdf=keep-pdf.desktop;\n')
        result=self.request({'action':'apply','role':'editor','app':'cedar-test-editor.desktop'})
        self.assertTrue(result['ok'],result)
        self.assertIn('x-scheme-handler/https=keep-browser.desktop;',mime.read_text())
        self.assertIn('application/pdf=keep-pdf.desktop;',mime.read_text())
        self.assertIn('text/plain=cedar-test-editor.desktop;',mime.read_text())
        data=self.request({'action':'snapshot'})['data']
        self.assertEqual(next(r for r in data['roles'] if r['id']=='editor')['current'],'cedar-test-editor.desktop')
        self.assertEqual(result['data']['launchKey'],'editor')
        wrapper=self.home/'state/cedar/default-editor'
        self.assertIn('gtk-launch cedar-test-editor.desktop "$@"',wrapper.read_text())
        self.assertFalse((self.home/'state/omarchy').exists(), 'Standalone default-app edits must not create Omarchy state')
    def test_explicit_omarchy_adapter_preserves_editor_integration(self):
        self.env['CEDAR_ADAPTER']='omarchy'
        result=self.request({'action':'apply','role':'editor','app':'cedar-test-editor.desktop'})
        self.assertTrue(result['ok'],result)
        self.assertEqual((self.home/'state/omarchy/defaults/editor').read_text().strip(),str(self.home/'state/cedar/default-editor'))
    def test_unknown_application_or_role_does_not_write(self):
        for request in [{'action':'apply','role':'editor','app':'not-installed.desktop'},{'action':'apply','role':'unknown','app':'cedar-test-editor.desktop'}]:self.assertFalse(self.request(request)['ok'])
        self.assertFalse((self.home/'config/mimeapps.list').exists())
    def test_terminal_does_not_change_file_associations(self):
        result=self.request({'action':'apply','role':'terminal','app':'cedar-test-editor.desktop'})
        self.assertTrue(result['ok'],result);self.assertEqual(result['data']['launchKey'],'terminal')
        self.assertFalse((self.home/'config/mimeapps.list').exists())
    def test_catalog_has_no_conflicting_groups(self):
        roles=json.loads((ROOT/'data/default-apps.json').read_text());types=[t for r in roles for t in r['types']]
        self.assertEqual(len(types),len(set(types)));self.assertGreaterEqual(len(roles),18)
    def test_choices_are_installed_entries_and_never_change_defaults_on_read(self):
        choices={'browser':'zen.desktop','editor':'codium.desktop','files':'io.github.lgse.Strata.desktop','terminal':'kitty.desktop'}
        before=self.request({'action':'snapshot'})['data']
        self.assertTrue(all(not row['preferred'] for row in before['roles']))
        apps=self.home/'data/applications'
        for app in choices.values():
            (apps/app).write_text('[Desktop Entry]\nType=Application\nName=Preferred Fixture\nExec=/usr/bin/true %U\n')
        after=self.request({'action':'snapshot'})['data']
        for role,app in choices.items():
            row=next(r for r in after['roles'] if r['id']==role)
            self.assertEqual(row['preferred'],app)
            self.assertIn(app,row['recommended'])
        self.assertFalse((self.home/'config/mimeapps.list').exists())
        (apps/'zen.desktop').unlink()
        removed=self.request({'action':'snapshot'})['data']
        self.assertEqual(next(r for r in removed['roles'] if r['id']=='browser')['preferred'],'')
    def test_reselecting_existing_associations_still_returns_launch_target(self):
        request={'action':'apply','role':'editor','app':'cedar-test-editor.desktop'}
        self.assertTrue(self.request(request)['ok'])
        result=self.request(request)['data']
        self.assertEqual(result['status'],'unchanged')
        self.assertEqual(result['launchTarget'],{'kind':'desktop-entry','id':'cedar-test-editor.desktop'})
