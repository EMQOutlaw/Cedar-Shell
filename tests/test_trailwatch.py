"""Lockscreen boundary cases with no external services."""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('trailwatch',ROOT/'scripts/trailwatch.py')
t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)

class TrailwatchSources(unittest.TestCase):
    def test_agenda_missing_and_corrupt_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'agenda.json'
            self.assertEqual(t.agenda(path,time.time())['status'],'unconfigured')
            path.write_text('{broken')
            self.assertEqual(t.agenda(path,time.time())['status'],'unavailable')

    def test_agenda_excludes_past_and_ambiguous_times(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'agenda.json';now=dt.datetime.now(dt.timezone.utc)
            path.write_text(json.dumps({'updatedAt':now.isoformat(),'events':[
                {'start':(now-dt.timedelta(hours=1)).isoformat(),'title':'past'},
                {'start':(now+dt.timedelta(hours=1)).replace(tzinfo=None).isoformat(),'title':'ambiguous'},
                {'start':(now+dt.timedelta(hours=2)).isoformat(),'title':'later'},
                {'start':(now+dt.timedelta(hours=1)).isoformat(),'title':'next'}]}))
            self.assertEqual([e['title'] for e in t.agenda(path,now.timestamp())['events']],['next','later'])
            self.assertEqual(t.agenda(path,now.timestamp()+86401)['status'],'stale')

    def test_agenda_rejects_oversized_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'agenda.json';path.write_text(' '*65537)
            self.assertEqual(t.agenda(path,time.time())['status'],'unavailable')

    def test_reminder_failure_is_not_an_empty_schedule(self):
        with patch.object(t,'command',return_value=None):self.assertIsNone(t.reminders())
        with patch.object(t,'command',return_value='[]'):self.assertEqual(t.reminders(),[])

    def test_reminders_validate_units_and_filter_expired(self):
        with patch.object(t,'command',return_value=json.dumps([
            {'unit':'omarchy-reminder-1m-test.timer','next':(time.time()+300)*1e6},
            {'unit':'omarchy-reminder-1m-old.timer','next':1},
            {'unit':'omarchy-reminder-/bad.timer','next':(time.time()+300)*1e6}])):
            values=t.reminders();self.assertEqual(len(values),1)
            self.assertEqual(values[0]['title'],'Reminder')

    def test_failed_service_query_distinguishes_unknown(self):
        with patch.object(t,'command',return_value=None):self.assertIsNone(t.failed(True))
        with patch.object(t,'command',return_value=''):self.assertEqual(t.failed(False),0)
        with patch.object(t,'command',return_value='broken.service loaded failed failed\n'):
            self.assertEqual(t.failed(True),1)

if __name__=='__main__':unittest.main()
