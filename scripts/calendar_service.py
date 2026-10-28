#!/usr/bin/env python3
"""Opt-in, read-only Google/Proton/Nextcloud calendar subscriptions; JSON over stdin.

Secret feed URLs and app passwords never enter argv, responses, logs or the
shared settings file.
"""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import base64
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from calendar_ical import CalendarError, MAX_BYTES, expand, local_zone, parse

PROVIDERS = {
    'google': {'name': 'Google Calendar', 'hosts': {'calendar.google.com', 'www.google.com'},
               'prefix': '/calendar/ical/', 'web': 'https://calendar.google.com/'},
    'proton': {'name': 'Proton Calendar', 'hosts': {'calendar.proton.me', 'calendar.protonmail.com'},
               'prefix': '/api/calendar/', 'web': 'https://calendar.proton.me/'},
    # Self-hosted: any HTTPS server the user names, but redirects must stay on it.
    'nextcloud': {'name': 'Nextcloud', 'hosts': None, 'prefix': None, 'web': None},
}
# Nextcloud may live under a subpath (https://example.org/cloud/...). Segments are
# kept to URL-safe characters so the stored path cannot climb with '..'.
NEXTCLOUD_PATH = re.compile(r'(?P<base>(?:/[A-Za-z0-9._~%+-]+)*?)(?:/index\.php)?'
                            r'(?:/apps/calendar/p/(?P<share>[A-Za-z0-9]+)(?:/.*)?'
                            r'|/remote\.php/dav/public-calendars/(?P<public>[A-Za-z0-9]+)/?'
                            r'|/remote\.php/dav/calendars/(?P<user>[A-Za-z0-9._~%@+-]+)/(?P<calendar>[A-Za-z0-9._~%+-]+)/?)')
MAX_SOURCES = 8
REFRESH_SECONDS = 900


def locations():
    home = Path.home()
    return (Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')) / 'cedar/calendar',
            Path(os.environ.get('XDG_CACHE_HOME', home / '.cache')) / 'cedar/calendar')


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path, 0o700)


def atomic(path, payload):
    private_dir(path.parent)
    fd, name = tempfile.mkstemp(prefix='.calendar-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(payload); stream.flush(); os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def read_json(path, default):
    try:
        if path.stat().st_size > MAX_BYTES * 3: raise CalendarError('Calendar settings are too large.')
        return json.loads(path.read_text())
    except FileNotFoundError: return default
    except (ValueError, OSError): raise CalendarError('Calendar settings could not be read.') from None


def nextcloud_url(value, origin=None):
    """Return the ICS export URL for a Nextcloud share link or calendar address."""
    try:
        url = urllib.parse.urlsplit(value)
        match = NEXTCLOUD_PATH.fullmatch(url.path)
        valid = (len(value) <= 4096 and not any(ord(c) < 33 for c in value) and url.scheme == 'https'
                 and bool(url.hostname) and not url.username and not url.password and not url.fragment
                 and match is not None and url.query in ('', 'export')
                 and not any(part in ('.', '..') for part in url.path.split('/')))
        if valid and origin is not None:
            first = urllib.parse.urlsplit(origin)
            valid = (url.hostname, url.port) == (first.hostname, first.port)
    except ValueError: valid = False
    if not valid: raise CalendarError('Paste the Nextcloud calendar share link or calendar address that starts with https://.')
    base = match['base']
    if match['user']: path = f"{base}/remote.php/dav/calendars/{match['user']}/{match['calendar']}"
    else: path = f"{base}/remote.php/dav/public-calendars/{match['share'] or match['public']}"
    return urllib.parse.urlunsplit(('https', url.netloc, path, 'export', ''))


def nextcloud_private(url): return '/remote.php/dav/calendars/' in urllib.parse.urlsplit(url).path


def credentials(request):
    username, password = str(request.get('username', '')).strip(), str(request.get('password', '')).strip()
    if not username or not password: raise CalendarError('A private Nextcloud calendar needs your username and an app password.')
    if len(username) > 256 or len(password) > 256 or any(ord(c) < 32 for c in username + password):
        raise CalendarError('Check the Nextcloud username and app password.')
    return username, password


def web_url(source):
    if source['provider'] != 'nextcloud': return PROVIDERS[source['provider']]['web']
    if source.get('kind') == 'import' or not source.get('url'): return ''
    url = urllib.parse.urlsplit(source['url'])
    base = url.path.split('/remote.php/', 1)[0]
    return urllib.parse.urlunsplit(('https', url.netloc, base + '/index.php/apps/calendar/', '', ''))


def validate_url(provider, value, origin=None):
    if provider not in PROVIDERS: raise CalendarError('Choose Google Calendar, Proton Calendar or Nextcloud.')
    value = str(value).strip()
    if value.startswith('webcal://'): value = 'https://' + value[9:]
    elif value.startswith('webcals://'): value = 'https://' + value[10:]
    if provider == 'nextcloud': return nextcloud_url(value, origin)
    try:
        url = urllib.parse.urlsplit(value)
        valid = (len(value) <= 4096 and not any(ord(c) < 33 for c in value)
                 and url.scheme == 'https' and url.hostname in PROVIDERS[provider]['hosts']
                 and url.port in (None, 443) and not url.username and not url.password and not url.fragment
                 and url.path.startswith(PROVIDERS[provider]['prefix']))
    except ValueError: valid = False
    if not valid: raise CalendarError('Paste the provider’s HTTPS calendar subscription link, not its website address.')
    return value


def network_allowed(request):
    config, _ = locations()
    settings = read_json(config.parent / 'settings.json', {})
    # Matches Config.qml's default and environment-level privacy override.
    return not (os.environ.get('CEDAR_LOCAL_ONLY') == '1' or request.get('offline')
                or settings.get('localOnly', True))


class CalendarRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, provider, origin=None): self.provider, self.origin = provider, origin
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Validate before following a redirect, so a feed cannot redirect secrets
        # to arbitrary sites or local network services. A Nextcloud redirect must
        # stay on the server the user chose, since its credentials travel with it.
        validate_url(self.provider, newurl, self.origin)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(source):
    url = validate_url(source['provider'], source['url'])
    headers = {'Accept': 'text/calendar', 'User-Agent': 'CEDAR-Calendar/1'}
    if source.get('username'):
        token = base64.b64encode(f"{source['username']}:{source.get('password', '')}".encode()).decode()
        headers['Authorization'] = 'Basic ' + token
    request = urllib.request.Request(url, headers=headers)
    try:
        opener = urllib.request.build_opener(CalendarRedirect(source['provider'], url if source['provider'] == 'nextcloud' else None))
        with opener.open(request, timeout=8) as response:
            data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES: raise CalendarError('Calendar is larger than 2 MiB.')
        parse(data)
        return data
    except urllib.error.HTTPError as error:
        error.close()
        if error.code in (401, 403) and source.get('username'):
            raise CalendarError('Nextcloud did not accept the username and app password. Create a new app password and replace the connection.') from None
        if error.code in (401, 403, 404, 410):
            raise CalendarError('Calendar link is unavailable or revoked. Replace it with a new sharing link.') from None
        raise CalendarError('Calendar provider is unavailable. Try refreshing later.') from None
    except (urllib.error.URLError, OSError, TimeoutError):
        raise CalendarError('Could not reach the calendar provider. Cached events are still available.') from None


def request_range(request):
    zone = local_zone()
    try:
        begin = datetime.strptime(request.get('begin', datetime.now().strftime('%Y-%m-01')), '%Y-%m-%d').replace(tzinfo=zone)
        end = datetime.strptime(request['end'], '%Y-%m-%d').replace(tzinfo=zone) if request.get('end') else begin + timedelta(days=42)
    except (ValueError, TypeError): raise CalendarError('Choose a valid calendar date range.') from None
    if not timedelta(0) < end - begin <= timedelta(days=93): raise CalendarError('Calendar range must be between 1 and 93 days.')
    return begin, end


def public_source(source, cached, error, allowed):
    updated = cached.get('updatedAt', 0)
    imported = source.get('kind') == 'import'
    status = 'error' if error else 'imported' if imported else 'offline' if not allowed else 'stale' if not updated or time.time() - updated >= REFRESH_SECONDS else 'ready'
    return {'id': source['id'], 'provider': source['provider'], 'name': source['name'], 'enabled': source.get('enabled', True),
            'color': source.get('color', '#62b89a'), 'updatedAt': updated * 1000, 'status': status, 'error': error,
            'readOnly': True, 'kind': 'import' if imported else 'subscription', 'webUrl': web_url(source)}


def snapshot(sources, request, refresh=False, force_id=None):
    _, cache = locations()
    begin, end = request_range(request)
    allowed = network_allowed(request)

    def one(source):
        path = cache / (source['id'] + '.json')
        cached = read_json(path, {})
        error = cached.get('error', '')
        imported = source.get('kind') == 'import'
        due = time.time() - cached.get('attemptedAt', 0) >= REFRESH_SECONDS
        if allowed and source.get('enabled', True) and not imported and (force_id == source['id'] or refresh and (request.get('force') or due)):
            cached['attemptedAt'] = time.time()
            # Persist the attempt first so a feed that hangs or kills the helper is throttled.
            atomic(path, json.dumps(cached).encode())
            try:
                raw = fetch(source)
                rows = expand(raw, begin, end)
                cached.update({'ics': raw.decode('utf-8-sig'), 'updatedAt': time.time(), 'error': ''})
                error = ''
            except CalendarError as failure:
                error = str(failure); cached['error'] = error
            atomic(path, json.dumps(cached).encode())
        rows = []
        if source.get('enabled', True) and cached.get('ics'):
            try: rows = expand(cached['ics'].encode(), begin, end)
            except CalendarError as failure: error = str(failure)
        public = public_source(source, cached, error, allowed)
        for row in rows:
            row.update({'sourceId': source['id'], 'calendar': source['name'], 'color': public['color'],
                        'stale': public['status'] in ('offline', 'stale', 'error'), 'provider': source['provider']})
        return public, rows

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(one, sources))
    calendars = [result[0] for result in results]
    rows = [row for _, events in results for row in events]
    rows.sort(key=lambda row: (datetime.fromisoformat(row['start']).timestamp(), row['title']))
    return {'sources': calendars, 'events': rows[:5000], 'truncated': len(rows) > 5000, 'offline': not allowed,
            'begin': begin.date().isoformat(), 'end': end.date().isoformat()}


def handle(request):
    if not isinstance(request, dict): raise CalendarError('Invalid calendar request.')
    config, cache = locations()
    private_dir(config); private_dir(cache)
    action = request.get('action', 'snapshot')
    with (config / '.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = config / 'connections.json'
        sources = read_json(path, [])
        if not isinstance(sources, list) or len(sources) > MAX_SOURCES: raise CalendarError('Calendar connection settings are invalid.')
        for source in sources:
            if not re.fullmatch(r'[a-f0-9]{32}', str(source.get('id', ''))) or source.get('provider') not in PROVIDERS:
                raise CalendarError('Calendar connection settings are invalid.')
        force_id = None
        if action in ('connect', 'import'):
            if len(sources) >= MAX_SOURCES: raise CalendarError('You can connect up to eight calendars.')
            provider = request.get('provider')
            if provider not in PROVIDERS: raise CalendarError('Choose a calendar provider.')
            name = str(request.get('name', '')).strip()[:80] or PROVIDERS[provider]['name']
            color = str(request.get('color', '#62b89a'))
            if not re.fullmatch(r'#[0-9a-fA-F]{6}', color): raise CalendarError('Choose a valid calendar color.')
            source = {'id': uuid.uuid4().hex, 'provider': provider, 'name': name, 'enabled': True, 'color': color,
                      'kind': 'import' if action == 'import' else 'subscription'}
            if action == 'connect':
                source['url'] = validate_url(provider, request.get('url', ''))
                if provider == 'nextcloud' and nextcloud_private(source['url']):
                    source['username'], source['password'] = credentials(request)
                if any(s.get('url') == source['url'] for s in sources): raise CalendarError('This calendar is already connected.')
                force_id = source['id']
            else:
                file = Path(str(request.get('path', ''))).expanduser()
                if not file.is_absolute() or file.suffix.lower() != '.ics': raise CalendarError('Choose an absolute path to an exported .ics file.')
                try:
                    with file.open('rb') as stream: raw = stream.read(MAX_BYTES + 1)
                except OSError: raise CalendarError('Could not read the selected calendar file.') from None
                begin, end = request_range(request)
                expand(raw, begin, end)
                atomic(cache / (source['id'] + '.json'), json.dumps({'ics': raw.decode('utf-8-sig'), 'updatedAt': time.time()}).encode())
            sources.append(source)
            atomic(path, json.dumps(sources).encode())
        elif action in ('disconnect', 'toggle', 'replace'):
            source = next((s for s in sources if s['id'] == request.get('id')), None)
            if source is None: raise CalendarError('Calendar connection no longer exists.')
            if action == 'disconnect':
                sources.remove(source)
            elif action == 'toggle':
                source['enabled'] = bool(request.get('enabled'))
                if source['enabled']: force_id = source['id']
            else:
                source['url'] = validate_url(source['provider'], request.get('url', ''))
                source.pop('username', None); source.pop('password', None)
                if source['provider'] == 'nextcloud' and nextcloud_private(source['url']):
                    source['username'], source['password'] = credentials(request)
                source['kind'] = 'subscription'; force_id = source['id']
            atomic(path, json.dumps(sources).encode())
            if action in ('disconnect', 'replace'): (cache / (source['id'] + '.json')).unlink(missing_ok=True)
        elif action not in ('snapshot', 'refresh'):
            raise CalendarError('Unknown calendar action.')
        return snapshot(sources, request, refresh=action == 'refresh', force_id=force_id)


def main():
    try:
        line = sys.stdin.buffer.readline(16385)
        if len(line) > 16384: raise CalendarError('Calendar request is too large.')
        value = handle(json.loads(line))
        print(json.dumps({'ok': True, 'data': value}))
    except CalendarError as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
    except Exception:
        # Exception strings can contain the bearer URL or event text.
        print(json.dumps({'ok': False, 'error': 'Calendar service could not complete the request. Check the calendar settings and try again.'}))


if __name__ == '__main__': main()
