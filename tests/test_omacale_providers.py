"""Provider fixtures; no real PAM or compositor certification."""
import copy,hashlib,os,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import distribution as d
import omarchy_providers as p
import omarchy_session as s

class OmacaleProviders(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cedar providers 雨 ');self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name)
        env=patch.dict(os.environ,{'HOME':str(self.base/'home')});env.start();self.addCleanup(env.stop)
        self.root=self.base/'source';self.plugins=Path.home()/'.config/omarchy/plugins'
        self.config={'version':1,'bar':{'id':'omacale.bar'},'plugins':[{'id':'local.lock'},{'id':'local.notifications'},{'id':'local.osd'}],'disabledPlugins':['omarchy.lock','omarchy.idle','omarchy.osd']}
        self.rows=[{'id':'omacale.bar','active':True,'enabled':True,'firstParty':False}]
        self.rules={'version':'fixture','barFiles':{},'roles':{}}
        bar=self.plugins/'omacale.bar';bar.mkdir(parents=True)
        (bar/'Bar.qml').write_text('fixture bar')
        self.rules['barFiles']['Bar.qml']=d.digest(bar/'Bar.qml')
        for role in ('lock','notifications','osd'):
            identity='local.'+role;directory=self.plugins/identity;directory.mkdir()
            (directory/'Service.qml').write_text('fixture '+role)
            contract={'schemaVersion':1,'kinds':['service'],'keepLoaded':True,'entryPoints':{'service':'Service.qml'}}
            manifest={**contract,'id':identity,'omarchy':{'clonedFrom':'omarchy.'+role,'capabilities':['authentication'] if role=='lock' else []}}
            d.write_json(directory/'manifest.json',manifest)
            self.rules['roles']['omarchy.'+role]={'contract':contract,'capabilities':manifest['omarchy']['capabilities'],'variants':[{'Service.qml':d.digest(directory/'Service.qml')}]}
            self.rows.append({'id':identity,'clonedFrom':'omarchy.'+role,'enabled':True,'firstParty':False,'kinds':['service']})
        d.write_json(self.root/'integrations/omarchy/omacale.json',self.rules)
    def inspect(self):return p.inspect(self.root,self.config,self.rows,self.base/'upstream')
    def test_preserves_locker_and_unknown_settings(self):
        record=self.inspect();original=copy.deepcopy(self.config)
        result=s.transformed(self.config,record)
        self.assertEqual(self.config,original)
        self.assertEqual(result['plugins'][:-1],original['plugins'])
        self.assertNotIn('local.lock',result['disabledPlugins'])
        self.assertIn('omarchy.lock',result['disabledPlugins'])
        self.assertIn('omarchy.idle',result['disabledPlugins'])
        self.assertEqual(record['disable'],['local.notifications','local.osd'])
        p.verify(self.root,record)
    def test_modified_locker_refused_without_writes(self):
        file=self.plugins/'local.lock/Service.qml';file.write_text('custom locker')
        before=d.info(file)
        with self.assertRaisesRegex(d.Refused,'Unreviewed or stale'):self.inspect()
        self.assertEqual(d.info(file),before)
    def test_authentication_capability_or_lifetime_change_refused(self):
        file=self.plugins/'local.lock/manifest.json';original=d.read_json(file)
        for changed in [{**original,'keepLoaded':False},{**original,'omarchy':{'clonedFrom':'omarchy.lock'}}]:
            d.write_json(file,changed)
            with self.assertRaises(d.Refused):self.inspect()
    def test_unknown_service_and_missing_or_duplicate_locker_refused(self):
        original=copy.deepcopy(self.rows)
        variants=[original+[{'id':'custom.service','enabled':True}], [r for r in original if r['id']!='local.lock'],original+[original[1]]]
        for value in variants:
            self.rows=value
            with self.assertRaises(d.Refused):self.inspect()
    def test_recheck_detects_later_source_change(self):
        record=self.inspect();(self.plugins/'omacale.bar/Bar.qml').write_text('update during trial')
        with self.assertRaises(d.Refused):p.verify(self.root,record)
    def test_symlink_and_extra_runtime_code_refused(self):
        extra=self.plugins/'local.lock/Unexpected.qml';extra.write_text('custom')
        with self.assertRaises(d.Refused):self.inspect()
        extra.unlink();bar=self.plugins/'omacale.bar/Bar.qml';bar.unlink();outside=self.base/'external';outside.write_text('fixture bar');bar.symlink_to(outside)
        with self.assertRaises(d.Refused):self.inspect()
    def test_no_authentication_clone_enabled_implicitly(self):
        self.config['disabledPlugins'].remove('omarchy.lock')
        with self.assertRaisesRegex(d.Refused,'Both stock and cloned'):self.inspect()
    def test_locker_remains_discoverable_after_switching_to_stock_bar(self):
        self.config['bar']['id']='omarchy.bar'
        self.rows[0].update(active=False,enabled=False)
        self.rows.append({'id':'omarchy.bar','enabled':True,'active':True,'firstParty':True})
        original=copy.deepcopy(self.config)
        record=self.inspect()
        self.assertEqual(record['lockId'],'local.lock')
        self.assertNotIn('local.lock',s.transformed(self.config,record)['disabledPlugins'])
        self.assertEqual(self.config,original)
        p.verify(self.root,record)
    def test_installed_but_disabled_omacale_is_not_adopted(self):
        self.config['bar']['id']='omarchy.bar'
        for row in self.rows:row.update(active=False,enabled=False)
        self.assertIsNone(self.inspect())
    def test_non_omacale_bar_does_not_bypass_locker_validation(self):
        self.config['bar']['id']='omarchy.bar';self.rows[0].update(active=False,enabled=False)
        (self.plugins/'local.lock/Service.qml').write_text('modified authentication')
        with self.assertRaisesRegex(d.Refused,'Unreviewed or stale'):self.inspect()
    def test_selected_omacale_still_requires_running_bar(self):
        self.rows[0].update(active=False,enabled=False)
        with self.assertRaisesRegex(d.Refused,'running bar'):self.inspect()

if __name__=='__main__':unittest.main()
