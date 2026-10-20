import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import settings_updates as updates

class UpdateStatus(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.env=patch.dict(os.environ,XDG_STATE_HOME=self.tmp.name);self.env.start();self.addCleanup(self.env.stop)
        self.identity=patch.object(updates,'content_digest',return_value='source-one');self.identity.start();self.addCleanup(self.identity.stop)
        self.channel=patch.object(updates,'default_channel',return_value='stable');self.channel.start();self.addCleanup(self.channel.stop)

    def test_missing_state_is_unknown(self):
        self.assertEqual(updates.status()['state'],'unknown')

    def test_malformed_record_is_unknown(self):
        updates.state_path().parent.mkdir(parents=True)
        for payload in ('[]','null','{"state":"current"}','{"sourceDigest":"source-one","state":"invented"}'):
            updates.state_path().write_text(payload)
            self.assertEqual(updates.status()['state'],'unknown')

    def test_only_verified_success_can_report_current(self):
        with patch.object(updates,'Updater') as updater:
            updater.return_value.run.return_value={'current':True,'version':'1.2.3'}
            result=updates.check()
        self.assertEqual(result['state'],'current')
        self.assertGreater(result['checkedAt'],0)
        self.assertEqual(updates.status()['version'],'1.2.3')
        with patch.object(updates,'content_digest',return_value='source-two'):
            self.assertEqual(updates.status()['state'],'unknown')

    def test_failure_replaces_prior_success(self):
        with patch.object(updates,'Updater') as updater:
            updater.return_value.run.return_value={'current':True}
            updates.check()
            updater.return_value.run.side_effect=RuntimeError('offline')
            result=updates.check()
        self.assertEqual(result['state'],'error')
        self.assertNotIn('checkedAt',result)
        self.assertEqual(updates.status()['detail'],'offline')

    def test_available_is_distinct_from_current(self):
        with patch.object(updates,'Updater') as updater:
            updater.return_value.run.return_value={'current':False,'version':'2.0'}
            self.assertEqual(updates.check()['state'],'available')
