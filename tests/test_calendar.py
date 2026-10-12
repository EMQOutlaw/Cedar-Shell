"""Real iCalendar fixtures and mocked provider transport; no personal accounts."""
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import calendar_ical as ical
import calendar_service as service


def feed(*events, zone=''):
    return ('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n' + ('X-WR-TIMEZONE:' + zone + '\r\n' if zone else '') +
            ''.join('BEGIN:VEVENT\r\n' + event.replace('\n', '\r\n') + '\r\nEND:VEVENT\r\n' for event in events) + 'END:VCALENDAR\r\n').encode()


def dt(value): return datetime.fromisoformat(value).replace(tzinfo=timezone.utc)


class CalendarParser(unittest.TestCase):
    def read(self, raw, start='2026-10-01', end='2026-11-01'):
        return ical.expand(raw, dt(start), dt(end), timezone.utc)

    def test_folded_escaped_text_and_description_quotes(self):
        raw = feed('UID:one\nDTSTART:20261012T140000Z\nDTEND:20261012T150000Z\nSUMMARY:Work\\, personal\\;\n  and more\nDESCRIPTION:Bring "one item\\nSecond line\nLOCATION:Desk')
        row = self.read(raw)[0]
        self.assertEqual(row['title'], 'Work, personal; and more')
        self.assertEqual(row['description'], 'Bring "one item\nSecond line')
        self.assertEqual(row['location'], 'Desk')

    def test_all_day_exclusive_end_and_multiday_overlap(self):
        raw = feed('UID:trip\nDTSTART;VALUE=DATE:20260930\nDTEND;VALUE=DATE:20261003\nSUMMARY:Trip')
        row = self.read(raw)[0]
        self.assertTrue(row['allDay'])
        self.assertEqual((row['startDate'], row['endDate']), ('2026-09-30', '2026-10-03'))
        self.assertEqual(self.read(raw, '2026-10-03', '2026-10-04'), [])

    def test_dst_recurrence_keeps_local_wall_time(self):
        raw = feed('UID:weekly\nDTSTART;TZID=America/New_York:20261025T090000\nDURATION:PT1H\nRRULE:FREQ=WEEKLY;COUNT=3\nSUMMARY:Weekly')
        rows = self.read(raw, '2026-10-01', '2026-11-10')
        self.assertEqual(len(rows), 3)
        self.assertTrue(rows[0]['start'].endswith('09:00:00-04:00'))
        self.assertTrue(rows[1]['start'].endswith('09:00:00-05:00'))

    def test_exdates_rdates_moved_cancelled_occurrences_and_sequence(self):
        raw = feed('UID:series\nDTSTART:20261001T120000Z\nDURATION:PT1H\nRRULE:FREQ=DAILY;COUNT=5\nEXDATE:20261002T120000Z\nRDATE:20261009T120000Z\nSUMMARY:Base',
                   'UID:series\nRECURRENCE-ID:20261003T120000Z\nDTSTART:20261003T150000Z\nSEQUENCE:2\nSUMMARY:Moved',
                   'UID:series\nRECURRENCE-ID:20261003T120000Z\nDTSTART:20261003T140000Z\nSEQUENCE:1\nSUMMARY:Older revision',
                   'UID:series\nRECURRENCE-ID:20261004T120000Z\nSTATUS:CANCELLED')
        rows = self.read(raw)
        self.assertEqual([r['start'][8:10] for r in rows], ['01', '03', '05', '09'])
        self.assertEqual(rows[1]['title'], 'Moved')
        self.assertIn('T15:00', rows[1]['start'])

    def test_monthly_last_weekday_and_ordinal_weekday(self):
        raw = feed('UID:last\nDTSTART:20260930T120000Z\nRRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1\nSUMMARY:Last weekday',
                   'UID:second\nDTSTART:20260908T120000Z\nRRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3\nSUMMARY:Second Tuesday')
        rows = self.read(raw)
        self.assertEqual([(r['start'][8:10], r['title']) for r in rows], [('13', 'Second Tuesday'), ('30', 'Last weekday')])
        # A query ending mid-month must not invent a last-weekday occurrence.
        self.assertEqual(len(self.read(raw, '2026-10-01', '2026-10-20')), 1)

    def test_yearly_leap_day_and_monthly_negative_monthday(self):
        raw = feed('UID:leap\nDTSTART;VALUE=DATE:20240229\nRRULE:FREQ=YEARLY\nSUMMARY:Leap',
                   'UID:last\nDTSTART;VALUE=DATE:20260131\nRRULE:FREQ=MONTHLY;BYMONTHDAY=-1\nSUMMARY:Last')
        rows = self.read(raw, '2028-02-01', '2028-03-01')
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(r['startDate'] == '2028-02-29' for r in rows))

    def test_until_count_and_week_start(self):
        raw = feed('UID:weekly\nDTSTART:20260928T090000Z\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR;UNTIL=20261016T090000Z;WKST=MO')
        self.assertEqual([r['start'][8:10] for r in self.read(raw)], ['02', '12', '16'])
        raw = feed('UID:daily\nDTSTART:20260929T090000Z\nRRULE:FREQ=DAILY;COUNT=3')
        self.assertEqual([r['start'][8:10] for r in self.read(raw)], ['01'])

    def test_floating_time_uses_calendar_timezone(self):
        raw = feed('UID:floating\nDTSTART:20261012T090000\nSUMMARY:Floating', zone='Europe/Paris')
        self.assertTrue(self.read(raw)[0]['start'].endswith('09:00:00+02:00'))

    def test_unsupported_recurrence_and_timezone_are_explicit(self):
        for extra in ['RRULE:FREQ=HOURLY', 'RRULE:FREQ=DAILY;BYSECOND=3', 'EXRULE:FREQ=DAILY']:
            with self.assertRaises(ical.CalendarError): self.read(feed('UID:unsupported\nDTSTART:20261001T090000Z\n' + extra))
        with self.assertRaisesRegex(ical.CalendarError, 'time zone'):
            self.read(feed('UID:unknown\nDTSTART;TZID=Not/AZone:20261001T090000'))
        with self.assertRaisesRegex(ical.CalendarError, 'THISANDFUTURE'):
            self.read(feed('UID:range\nRECURRENCE-ID;RANGE=THISANDFUTURE:20261001T090000Z\nDTSTART:20261001T120000Z'))

    def test_cancelled_series_and_busy_calendar(self):
        raw = feed('UID:cancelled\nDTSTART:20261001T090000Z\nSTATUS:CANCELLED', 'UID:busy\nDTSTART:20261002T090000Z')
        rows = self.read(raw)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['title'], 'Busy')

    def test_invalid_documents_and_bounds(self):
        for raw in [b'<html>Sign in</html>', b'BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR', b'x' * (ical.MAX_BYTES + 1)]:
            with self.assertRaises(ical.CalendarError): self.read(raw)
        with self.assertRaises(ical.CalendarError): self.read(feed('UID:backwards\nDTSTART:20261002T090000Z\nDTEND:20261001T090000Z'))


class CalendarConnections(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.base / 'config'), 'XDG_CACHE_HOME': str(self.base / 'cache'), 'CEDAR_LOCAL_ONLY': ''})
        self.env.start(); self.addCleanup(self.env.stop)
        self.private, self.cache = service.locations()
        self.private.parent.mkdir(parents=True)
        (self.private.parent / 'settings.json').write_text('{"localOnly":false}')
        self.raw = feed('UID:test\nDTSTART:20261012T090000Z\nDURATION:PT1H\nSUMMARY:Private event')
        self.request = {'provider': 'google', 'name': 'Work', 'url': 'https://calendar.google.com/calendar/ical/test/private-fixture/basic.ics', 'begin': '2026-10-01', 'end': '2026-11-01'}

    def call(self, action, **extra): return service.handle(dict(self.request, action=action, **extra))

    def test_connect_refresh_disable_disconnect_and_secret_redaction(self):
        with patch.object(service, 'fetch', return_value=self.raw) as fetch:
            result = self.call('connect')
            self.assertEqual(len(result['events']), 1)
            self.assertNotIn('private-fixture', json.dumps(result))
            source_id = result['sources'][0]['id']
            self.assertEqual(result['sources'][0]['status'], 'ready')
            self.call('refresh'); self.assertEqual(fetch.call_count, 1, 'automatic refresh is throttled')
            self.call('refresh', force=True); self.assertEqual(fetch.call_count, 2)
            disabled = self.call('toggle', id=source_id, enabled=False)
            self.assertEqual(disabled['events'], [])
            self.call('refresh', force=True); self.assertEqual(fetch.call_count, 2)
            enabled = self.call('toggle', id=source_id, enabled=True)
            self.assertEqual(len(enabled['events']), 1)
            result = self.call('disconnect', id=source_id)
            self.assertEqual(result['sources'], [])
            self.assertFalse((self.cache / (source_id + '.json')).exists())

    def test_failed_refresh_preserves_cache_and_reports_error(self):
        with patch.object(service, 'fetch', return_value=self.raw): self.call('connect')
        with patch.object(service, 'fetch', side_effect=ical.CalendarError('Provider unavailable')):
            result = self.call('refresh', force=True)
        self.assertEqual(result['events'][0]['title'], 'Private event')
        self.assertTrue(result['events'][0]['stale'])
        self.assertEqual(result['sources'][0]['status'], 'error')

    def test_offline_never_connects_and_empty_snapshot_is_supported(self):
        (self.private.parent / 'settings.json').write_text('{"localOnly":true}')
        with patch.object(service, 'fetch') as fetch:
            result = self.call('connect')
            self.assertEqual(result['sources'][0]['status'], 'offline')
            self.assertEqual(result['events'], [])
            self.call('refresh', offline=False, force=True)
            fetch.assert_not_called()

    def test_private_permissions_even_with_permissive_umask(self):
        old = os.umask(0)
        try:
            with patch.object(service, 'fetch', return_value=self.raw): self.call('connect')
        finally: os.umask(old)
        self.assertEqual(stat.S_IMODE(self.private.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.private / 'connections.json').stat().st_mode), 0o600)
        for file in self.cache.glob('*.json'): self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)

    def test_import_snapshot_works_without_network_and_excludes_file_path(self):
        file = self.base / 'personal.ics'; file.write_bytes(self.raw)
        with patch.object(service, 'fetch') as fetch:
            result = self.call('import', path=str(file), offline=True, provider='proton')
            self.assertEqual(result['sources'][0]['kind'], 'import')
            self.assertEqual(len(result['events']), 1)
            self.call('refresh', force=True)
            fetch.assert_not_called()
        self.assertNotIn(str(file), json.dumps(result))

    def test_duplicate_connection_rejected_and_replace_drops_old_cache(self):
        with patch.object(service, 'fetch', return_value=self.raw): result = self.call('connect')
        with self.assertRaisesRegex(ical.CalendarError, 'already connected'): self.call('connect')
        with patch.object(service, 'fetch', side_effect=ical.CalendarError('New feed unavailable')):
            result = self.call('replace', id=result['sources'][0]['id'], url='https://calendar.google.com/calendar/ical/new/private-fixture/basic.ics')
        self.assertEqual(result['events'], [])
        self.assertEqual(result['sources'][0]['status'], 'error')

    def test_provider_allowlist_rejects_local_hosts_and_redirects(self):
        for url in ['http://calendar.google.com/calendar/ical/test', 'https://calendar.google.com.evil.test/calendar/ical/test',
                    'https://127.0.0.1/calendar/ical/test', 'file:///tmp/calendar.ics', 'https://user:pass@calendar.google.com/calendar/ical/test',
                    'https://calendar.google.com/calendar/ical/test#secret', 'https://calendar.google.com/']:
            with self.assertRaises(ical.CalendarError): service.validate_url('google', url)
        value = service.validate_url('proton', 'webcal://calendar.proton.me/api/calendar/v1/url/fixture/key')
        self.assertTrue(value.startswith('https://'))
        with self.assertRaises(ical.CalendarError):
            service.CalendarRedirect('google').redirect_request(None, None, 302, '', {}, 'https://evil.test/steal')

    def test_http_errors_do_not_echo_bearer_url(self):
        error = service.urllib.error.HTTPError(self.request['url'], 403, 'private-fixture', {}, None)
        with patch.object(service.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = error
            with self.assertRaises(ical.CalendarError) as raised: service.fetch(self.request)
        self.assertNotIn('private-fixture', str(raised.exception))

    def test_actual_stdin_protocol_and_no_secrets_in_failure(self):
        request = dict(self.request, action='connect', url='https://evil.test/private-fixture')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/calendar_service.py')], input=json.dumps(request)+'\n', text=True, capture_output=True)
        value = json.loads(result.stdout)
        self.assertFalse(value['ok'])
        self.assertNotIn('private-fixture', result.stdout + result.stderr)

    def test_query_range_and_source_id_bounds(self):
        with self.assertRaises(ical.CalendarError): self.call('snapshot', end='2028-01-01')
        service.private_dir(self.private)
        (self.private / 'connections.json').write_text('[{"id":"../../outside","provider":"google"}]')
        with self.assertRaises(ical.CalendarError): self.call('snapshot')


if __name__ == '__main__': unittest.main()
