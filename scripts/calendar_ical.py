"""Bounded iCalendar reader for Google/Proton subscription feeds.

No scripts, attachments or alarm actions are executed. Unsupported recurrence
rules/time zones fail explicitly instead of silently omitting appointments.
"""
from __future__ import annotations
import calendar
from datetime import date, datetime, time, timedelta, timezone
import re
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_BYTES = 2 * 1024 * 1024
MAX_EVENTS = 5000
MAX_DAYS = 366 * 150
WEEKDAYS = {'MO': 0, 'TU': 1, 'WE': 2, 'TH': 3, 'FR': 4, 'SA': 5, 'SU': 6}


class CalendarError(ValueError):
    pass


def local_zone():
    try:
        with open('/etc/localtime', 'rb') as stream:
            return ZoneInfo.from_file(stream)
    except OSError:
        return timezone.utc


def text(value):
    return re.sub(r'\\([nN,;\\])', lambda m: '\n' if m[1] in 'nN' else m[1], str(value))


def parse(raw):
    if len(raw) > MAX_BYTES:
        raise CalendarError('Calendar is larger than 2 MiB.')
    try:
        lines = re.sub(rb'\r?\n[ \t]', b'', raw).decode('utf-8-sig').strip().splitlines()
    except UnicodeError:
        raise CalendarError('Calendar must be UTF-8 iCalendar data.') from None
    if not lines or lines[0].strip().upper() != 'BEGIN:VCALENDAR' or lines[-1].strip().upper() != 'END:VCALENDAR':
        raise CalendarError('This link did not return an iCalendar (.ics) feed.')
    events, current, stack, zone = [], None, [], None
    for line in lines:
        if ':' not in line:
            continue
        # Colons can occur in quoted property parameters.
        quoted = False
        separator = -1
        for index, char in enumerate(line):
            if char == '"': quoted = not quoted
            elif char == ':' and not quoted: separator = index; break
        if separator < 0: raise CalendarError('Malformed calendar property.')
        head, value = line[:separator], line[separator + 1:]
        bits = re.split(r';(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)', head)
        name = bits[0].upper()
        params = {}
        for bit in bits[1:]:
            if '=' in bit:
                key, val = bit.split('=', 1); params[key.upper()] = val.strip('"')
        if name == 'BEGIN':
            stack.append(value.upper())
            if value.upper() == 'VEVENT': current = {}
        elif name == 'END':
            if not stack or stack.pop() != value.upper():
                raise CalendarError('Calendar components are incomplete.')
            if value.upper() == 'VEVENT' and current is not None:
                events.append(current); current = None
                if len(events) > MAX_EVENTS: raise CalendarError('Calendar has too many events.')
        elif current is not None and stack and stack[-1] == 'VEVENT':
            current.setdefault(name, []).append((params, value))
        elif stack == ['VCALENDAR'] and name == 'X-WR-TIMEZONE':
            zone = value
    if stack: raise CalendarError('Calendar components are incomplete.')
    return events, zone


def first(event, key, default=''):
    return event.get(key, [({}, default)])[0][1]


def temporal(prop, fallback):
    params, value = prop
    if params.get('VALUE') == 'DATE' or re.fullmatch(r'\d{8}', value):
        try: return datetime.strptime(value, '%Y%m%d').date()
        except ValueError: raise CalendarError('Invalid all-day date.') from None
    zone = fallback
    if params.get('TZID'):
        try: zone = ZoneInfo(params['TZID'])
        except (ZoneInfoNotFoundError, ValueError):
            raise CalendarError('Calendar uses an unsupported time zone.') from None
    try:
        if value.endswith('Z'):
            return datetime.strptime(value, '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)
        return datetime.strptime(value, '%Y%m%dT%H%M%S').replace(tzinfo=zone)
    except ValueError:
        raise CalendarError('Invalid calendar time.') from None


def as_datetime(value, zone):
    return value if isinstance(value, datetime) else datetime.combine(value, time.min, zone)


def identity(value):
    return value.astimezone(timezone.utc).isoformat() if isinstance(value, datetime) else value.isoformat()


def duration(event, start, zone):
    if event.get('DTEND'):
        end = temporal(event['DTEND'][0], zone)
        if isinstance(start, datetime) != isinstance(end, datetime):
            raise CalendarError('Calendar start and end use different date types.')
        delta = end - start
    elif event.get('DURATION'):
        match = re.fullmatch(r'P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?', first(event, 'DURATION'))
        if not match or not any(match.groups()): raise CalendarError('Unsupported event duration.')
        w, d, h, m, s = [int(x or 0) for x in match.groups()]
        delta = timedelta(weeks=w, days=d, hours=h, minutes=m, seconds=s)
    else:
        delta = timedelta(0) if isinstance(start, datetime) else timedelta(days=1)
    if delta < timedelta(0) or delta > timedelta(days=366):
        raise CalendarError('Invalid event duration.')
    return delta


def numbers(rule, key, low, high, no_zero=False):
    if key not in rule: return []
    try: values = [int(x) for x in rule[key].split(',')]
    except ValueError: raise CalendarError('Invalid recurrence number.') from None
    if len(values) > 64 or any(v < low or v > high or (no_zero and v == 0) for v in values):
        raise CalendarError('Recurrence is outside supported limits.')
    return values


def occurrences(event, start, stop, zone):
    """Expand daily/weekly/monthly/yearly RRULEs, including set positions."""
    if len(event.get('RRULE', [])) > 1: raise CalendarError('Multiple recurrence rules are unsupported.')
    if event.get('EXRULE'): raise CalendarError('Legacy EXRULE recurrence is unsupported.')
    if not event.get('RRULE'): return [start]
    try: rule = dict(part.split('=', 1) for part in first(event, 'RRULE').upper().split(';'))
    except ValueError: raise CalendarError('Malformed recurrence rule.') from None
    allowed = {'FREQ', 'INTERVAL', 'COUNT', 'UNTIL', 'BYDAY', 'BYMONTHDAY', 'BYMONTH', 'BYSETPOS', 'WKST'}
    if set(rule) - allowed or rule.get('FREQ') not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'):
        raise CalendarError('This calendar uses an unsupported recurrence rule; hourly/minutely rules are not supported.')
    interval = numbers(rule, 'INTERVAL', 1, 1000) or [1]
    count = numbers(rule, 'COUNT', 1, 1000000) or [1000000]
    if len(interval) != 1 or len(count) != 1: raise CalendarError('Invalid recurrence interval/count.')
    interval, count = interval[0], count[0]
    months = numbers(rule, 'BYMONTH', 1, 12)
    monthdays = numbers(rule, 'BYMONTHDAY', -31, 31, True)
    positions = numbers(rule, 'BYSETPOS', -366, 366, True)
    byday = []
    for item in rule.get('BYDAY', '').split(',') if rule.get('BYDAY') else []:
        match = re.fullmatch(r'([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)', item)
        if not match: raise CalendarError('Invalid recurrence weekday.')
        ordinal = int(match[1]) if match[1] else 0
        if match[1] and (ordinal == 0 or abs(ordinal) > 53): raise CalendarError('Invalid weekday position.')
        if ordinal and rule['FREQ'] not in ('MONTHLY', 'YEARLY'):
            raise CalendarError('Weekday positions require monthly or yearly recurrence.')
        byday.append((ordinal, WEEKDAYS[match[2]]))
    if 'WKST' in rule and rule['WKST'] not in WEEKDAYS: raise CalendarError('Invalid recurrence week start.')
    wkst = WEEKDAYS.get(rule.get('WKST', 'MO'), 0)
    until = temporal(({}, rule['UNTIL']), zone) if 'UNTIL' in rule else None
    first_day = start.date() if isinstance(start, datetime) else start
    last_day = stop.date() if isinstance(stop, datetime) else stop
    if last_day < first_day: return []
    if (last_day - first_day).days > MAX_DAYS: raise CalendarError('Recurring event starts more than 150 years ago.')
    freq = rule['FREQ']
    week_origin = first_day - timedelta(days=(first_day.weekday() - wkst) % 7)
    buckets = {}
    for offset in range((last_day - first_day).days + 1):
        day = first_day + timedelta(days=offset)
        month_index = (day.year - first_day.year) * 12 + day.month - first_day.month
        week_index = (day - week_origin).days // 7
        period = offset if freq == 'DAILY' else week_index if freq == 'WEEKLY' else month_index if freq == 'MONTHLY' else day.year - first_day.year
        if period % interval or (months and day.month not in months): continue
        days_in_month = calendar.monthrange(day.year, day.month)[1]
        if monthdays and day.day not in [n if n > 0 else days_in_month + n + 1 for n in monthdays]: continue
        if byday:
            matched = False
            for ordinal, weekday in byday:
                if day.weekday() != weekday: continue
                if not ordinal: matched = True; break
                if freq == 'YEARLY' and not months:
                    position = (day - date(day.year, 1, 1)).days // 7 + 1
                    reverse = -((date(day.year, 12, 31) - day).days // 7 + 1)
                else:
                    position = (day.day - 1) // 7 + 1
                    reverse = -((days_in_month - day.day) // 7 + 1)
                if ordinal in (position, reverse): matched = True; break
            if not matched: continue
        if freq == 'WEEKLY' and not byday and day.weekday() != first_day.weekday(): continue
        if freq in ('MONTHLY', 'YEARLY') and not monthdays and not byday and day.day != first_day.day: continue
        if freq == 'YEARLY' and not months and not byday and not monthdays and day.month != first_day.month: continue
        value = datetime.combine(day, start.timetz()) if isinstance(start, datetime) else day
        if until is not None and as_datetime(value, zone) > as_datetime(until, zone): continue
        buckets.setdefault(period, []).append(value)
    result = []
    for bucket in buckets.values():
        if positions:
            bucket = sorted(set(bucket[n-1 if n > 0 else n] for n in positions if -len(bucket) <= n <= len(bucket)))
        result.extend(bucket)
        if len(result) >= count: break
    return result[:count]


def expand(raw, begin, end, display_zone=None):
    events, tzname = parse(raw)
    zone = display_zone or local_zone()
    if tzname:
        try: zone = ZoneInfo(tzname)
        except (ZoneInfoNotFoundError, ValueError): raise CalendarError('Calendar uses an unsupported time zone.') from None
    # Select the newest sequence for a UID/recurrence pair (cancelled overrides included).
    unique = {}
    for event in events:
        if not event.get('UID'): raise CalendarError('An event is missing its calendar identifier.')
        recurrence = event.get('RECURRENCE-ID')
        if recurrence and recurrence[0][0].get('RANGE'):
            raise CalendarError('THISANDFUTURE recurrence edits are unsupported.')
        key = (first(event, 'UID'), identity(temporal(recurrence[0], zone)) if recurrence else '')
        try: sequence = int(first(event, 'SEQUENCE', '0'))
        except ValueError: raise CalendarError('Invalid event revision.') from None
        previous = unique.get(key)
        if previous is None or sequence >= previous[0]: unique[key] = (sequence, event)
    overrides = {key: val[1] for key, val in unique.items() if key[1]}
    rows = []

    def append(event, start, delta, uid):
        finish = start + delta
        at, to = as_datetime(start, zone), as_datetime(finish, zone)
        if at >= end or (to <= begin if delta else at < begin): return
        all_day = not isinstance(start, datetime)
        rows.append({'id': uid + ':' + identity(start), 'title': text(first(event, 'SUMMARY', 'Busy'))[:240] or 'Busy',
                     'start': at.isoformat(), 'end': to.isoformat(), 'allDay': all_day,
                     'startDate': start.isoformat() if all_day else '', 'endDate': finish.isoformat() if all_day else '',
                     'location': text(first(event, 'LOCATION'))[:240], 'description': text(first(event, 'DESCRIPTION'))[:1200]})
        if len(rows) > MAX_EVENTS: raise CalendarError('Too many events in the requested range.')

    recurrence_work = 0
    for (uid, recurrence), (_, event) in unique.items():
        if recurrence or first(event, 'STATUS').upper() == 'CANCELLED': continue
        if not event.get('DTSTART'): raise CalendarError('An event is missing its start time.')
        start = temporal(event['DTSTART'][0], zone)
        delta = duration(event, start, zone)
        # Complete the final recurrence period before applying BYSETPOS.
        stop = end.astimezone(start.tzinfo) if isinstance(start, datetime) else end.date()
        if 'BYSETPOS=' in first(event, 'RRULE').upper():
            stop_date = stop.date() if isinstance(stop, datetime) else stop
            stop_date = date(stop_date.year, 12, 31)
            stop = datetime.combine(stop_date, time.max, start.tzinfo) if isinstance(start, datetime) else stop_date
        if event.get('RRULE'):
            recurrence_work += max(0, (as_datetime(stop, zone).date() - as_datetime(start, zone).date()).days)
            if recurrence_work > 1000000: raise CalendarError('Calendar recurrence history is too large to expand safely.')
        starts = {identity(x): x for x in occurrences(event, start, stop, zone)}
        starts.setdefault(identity(start), start)  # DTSTART is always in the recurrence set.
        for params, values in event.get('RDATE', []):
            if params.get('VALUE') == 'PERIOD': raise CalendarError('Period-valued recurrence dates are unsupported.')
            for value in values.split(','):
                item = temporal((params, value), zone); starts[identity(item)] = item
        excluded = {identity(temporal((params, value), zone)) for params, values in event.get('EXDATE', []) for value in values.split(',')}
        for key, value in starts.items():
            if key not in excluded and (uid, key) not in overrides: append(event, value, delta, uid)
    for (uid, _), event in overrides.items():
        if first(event, 'STATUS').upper() == 'CANCELLED': continue
        if not event.get('DTSTART'): raise CalendarError('An edited occurrence has no start time.')
        start = temporal(event['DTSTART'][0], zone)
        append(event, start, duration(event, start, zone), uid)
    return sorted(rows, key=lambda row: (row['start'], row['title']))
