"""State integrity checks for Settings' new transactional interactions."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj
d=module('desktop');info=module('settings_info');net=module('connections')
class RemasterTransactions(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.own=Path(temp.name);p=patch.object(d,'OWN',self.own);p.start();self.addCleanup(p.stop)
        self.state={'input':{'sensitivity':.2},'monitors':[],'bindings':[],'mainDisplay':'DP-2'}
        (self.own/'settings.json').write_text(json.dumps(self.state))
    def test_external_input_change_is_not_overwritten(self):
        with patch.object(d,'snapshot',return_value={'input':{'sensitivity':.7}}),patch.object(d,'install') as install:
            with self.assertRaisesRegex(ValueError,'outside Settings'):d.action({'action':'input','values':{'sensitivity':.4},'expected':{'sensitivity':.2}})
            install.assert_not_called()
    def test_unrelated_external_input_change_is_preserved(self):
        with patch.object(d,'snapshot',return_value={'input':{'sensitivity':.2,'kb_layout':'de'}}),patch.object(d,'install') as install:
            d.action({'action':'input','values':{'sensitivity':.4},'expected':{'sensitivity':.2,'kb_layout':'us'}})
            self.assertEqual(install.call_args.args[0]['input'],{'sensitivity':.4})
    def test_input_reset_keeps_display_and_bindings(self):
        with patch.object(d,'install') as install:
            d.action({'action':'reset-input'})
            saved=install.call_args.args[0]
            self.assertEqual(saved['input'],{});self.assertEqual(saved['mainDisplay'],'DP-2')
    def test_changed_display_geometry_is_not_applied(self):
        live={'name':'DP-2','width':2560,'height':1440,'refreshRate':240,'x':100,'y':0,'scale':1,'transform':0}
        with patch.object(d,'hypr',return_value=[live]),patch.object(d,'install') as install:
            with self.assertRaisesRegex(ValueError,'Displays changed'):d.action({'action':'displays','monitors':[],'expected':[{**live,'x':0}]})
            install.assert_not_called()
    def test_confirmed_replacement_only_matches_reviewed_binding(self):
        bind={'keys':'SUPER + B','arg':'browser','dispatcher':'exec','editable':True}
        with patch.object(d,'snapshot',return_value={'bindings':[bind]}),patch.object(d,'install') as install:
            d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[bind]})
            self.assertEqual(install.call_args.args[0]['bindings'][0]['command'],'kitty')
            install.reset_mock()
            with self.assertRaisesRegex(ValueError,'changed'):d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[{**bind,'arg':'old browser'}]})
            install.assert_not_called()
    def test_callback_replacement_is_rejected(self):
        bind={'keys':'SUPER + B','arg':'callback','dispatcher':'lua','editable':False}
        with patch.object(d,'snapshot',return_value={'bindings':[bind]}),patch.object(d,'install') as install:
            with self.assertRaises(ValueError):d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[bind]})
            install.assert_not_called()
    def test_later_input_override_is_reported(self):
        with patch.object(d,'command',return_value='{"float":0.8}'):
            with self.assertRaisesRegex(ValueError,'later override'):d.verify_inputs({'sensitivity':.3})
        with patch.object(d,'command',return_value='{"float":0.300000001}'):
            d.verify_inputs({'sensitivity':.3})
    def test_vrr_written_only_after_explicit_choice(self):
        live={'name':'DP-2','width':2560,'height':1440,'refreshRate':240,'vrr':False,'availableModes':['2560x1440@240.00Hz']}
        draft={'name':'DP-2','mode':'2560x1440@240.00','x':0,'y':0,'scale':1,'transform':0}
        self.assertNotIn('vrr',d.render({'monitors':d.validate_monitors([draft],[live])}))
        saved=d.validate_monitors([{**draft,'vrrPolicy':2}],[live])
        self.assertIn('["vrr"]=2',d.render({'monitors':saved}))
        with self.assertRaises(ValueError):d.validate_monitors([{**draft,'vrrPolicy':99}],[live])
    def test_service_actions_are_whitelisted(self):
        with patch.object(info,'run') as run:
            with self.assertRaises(ValueError):info.action({'action':'restart','unit':'sshd.service'})
            run.assert_not_called()
    def test_health_distinguishes_missing_failed_and_active(self):
        for state,label in [('LoadState=not-found','Unavailable'),('LoadState=loaded\nActiveState=failed','Failed'),('LoadState=loaded\nActiveState=active','Healthy')]:
            with patch.object(info,'run',return_value=state):self.assertEqual(info.service(('PipeWire','pipewire.service',True))['status'],label)
    def test_autoconnect_edits_one_uuid_property(self):
        obj=net.Network.__new__(net.Network)
        with patch.object(obj,'saved',return_value=[{'path':'/connection/1','uuid':'a-b-c'}]),patch.object(net.subprocess,'run') as run:
            run.return_value.returncode=0
            obj.action({'action':'autoconnect','path':'/connection/1','enabled':False})
            self.assertEqual(run.call_args.args[0],['nmcli','connection','modify','uuid','a-b-c','connection.autoconnect','no'])
