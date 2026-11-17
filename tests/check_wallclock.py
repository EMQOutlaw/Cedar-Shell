#!/usr/bin/env python3
"""WallClock keeps the bar clock's timer out of the past.

Quickshell's SystemClock truncated the local time and armed a QTimer for the
distance to the next tick; in a DST fall-back that distance is negative, Qt
clamps it to 1 ms and the clock storms (quickshell #329/#1383). CEDAR now
derives the delay from epoch milliseconds. This check feeds the component the
instants a wall clock repeats or skips and demands a delay in (0, step], and
proves those instants really are traps by emulating Qt's truncation on the
same instants and demanding a negative result there.
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ZONE = ZoneInfo('America/New_York')
LORD_HOWE = ZoneInfo('Australia/Lord_Howe')


def transitions(zone, year):
    """UTC instants where `zone`'s offset changes in `year`, found by scanning.

    Sampling the real transitions keeps both legs of the control honest: a case
    set built from US dates proves nothing about Lord Howe, whose folds fall in
    April and October.
    """
    found, step = [], timedelta(hours=1)
    moment = datetime(year, 1, 1, tzinfo=timezone.utc)
    end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    previous = moment.astimezone(zone).utcoffset()
    while moment < end:
        moment += step
        offset = moment.astimezone(zone).utcoffset()
        if offset != previous:
            found.append(moment - step / 2)
            previous = offset
    return found


def instants():
    """Epoch ms around every 2026/2027 offset change in both zones, plus edges."""
    out = []
    for zone in (ZONE, LORD_HOWE):
        for transition in transitions(zone, 2026) + transitions(zone, 2027):
            # ±3 h around the change, so the repeated hour itself is sampled.
            for minutes in range(-180, 181, 7):
                moment = transition + timedelta(minutes=minutes)
                out.append(int(moment.timestamp() * 1000))
                out.append(int((moment + timedelta(milliseconds=617)).timestamp() * 1000))
    out += [
        0,                                          # epoch
        int(datetime(2026, 1, 1, 4, 59, 59, 999000, tzinfo=timezone.utc).timestamp() * 1000),
        int(datetime(2026, 12, 31, 23, 59, 0, 1, tzinfo=timezone.utc).timestamp() * 1000),
        int(datetime(2028, 2, 29, 12, 0, 30, 500000, tzinfo=timezone.utc).timestamp() * 1000),
    ]
    return sorted(set(out))


def legacy_delay_ms(ms, zone, step_ms=60000):
    """Qt 6.6 SystemClock::schedule's arithmetic, replayed faithfully.

    Truncate the local wall clock to the minute, resolve that naive local time
    the way QDateTime::setTime() does — to the FIRST occurrence of an ambiguous
    time — then ADD ONE STEP, because the clock arms at the next tick rather
    than at the truncated instant, and measure from `ms` to that target. A fold
    yields a negative delay; an ordinary instant yields the rest of its minute.
    """
    local = datetime.fromtimestamp(ms / 1000, tz=zone)
    naive = local.replace(second=0, microsecond=0)
    candidates = [naive.replace(tzinfo=zone, fold=0), naive.replace(tzinfo=zone, fold=1)]
    first = min(candidates, key=lambda dt: dt.timestamp())
    return int((first.timestamp() * 1000) + step_ms - ms)


def main():
    cases = instants()
    traps = [ms for ms in cases if legacy_delay_ms(ms, ZONE) < 0]
    howe_traps = [ms for ms in cases if legacy_delay_ms(ms, LORD_HOWE) < 0]
    if not traps or not howe_traps:
        raise SystemExit(f'negative control failed: {len(traps)} US/Eastern and '
                         f'{len(howe_traps)} Lord Howe fold instants produced a negative legacy delay')

    with tempfile.TemporaryDirectory(prefix='cedar-wallclock-') as tmp:
        p = Path(tmp)
        source = p / 'shell'
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
        runtime = p / 'runtime'
        runtime.mkdir(mode=0o700)
        harness = (ROOT / 'tests/core/WallClockHarness.qml').read_text()
        # The harness imports the tree it will be copied into: rewrite those
        # import lines (and only those) from "../.." to the copy's root.
        harness = re.sub(r'(?m)^import\s+"\.\./\.\."$', 'import "."', harness)
        harness = re.sub(r'(?m)^import\s+"\.\./\.\./([^"]+)"$', r'import "\1"', harness)
        (source / 'preview.qml').write_text(harness)
        env = {
            **os.environ,
            'CEDAR_TEST': '1',
            'QT_QPA_PLATFORM': 'offscreen',
            'QT_QPA_PLATFORMTHEME': 'basic',
            'QT_QUICK_CONTROLS_STYLE': 'Basic',
            'QSG_RHI_BACKEND': 'software',
            'XDG_RUNTIME_DIR': str(runtime),
            'XDG_CONFIG_HOME': str(p / 'config'),
            'XDG_STATE_HOME': str(p / 'state'),
            'XDG_CACHE_HOME': str(p / 'cache'),
            'TZ': 'America/New_York',
            'CEDAR_WALLCLOCK_CASES': json.dumps(cases),
        }
        try:
            result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired as expired:
            # A wedged harness is exactly when its output matters most.
            for stream in (expired.stdout, expired.stderr):
                if stream:
                    print(stream.decode(errors='replace') if isinstance(stream, bytes) else stream)
            raise SystemExit('the wallclock harness did not finish within 60 s')
    output = result.stdout + result.stderr
    broken = re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output)
    if result.returncode or 'PASS: wallclock' not in output or broken:
        print(output)
        raise SystemExit(1)

    match = re.search(r'WALLCLOCK_JSON (.*)', output)
    if not match:
        print(output)
        raise SystemExit('the harness printed no delay table')
    rows = json.loads(match.group(1))
    if len(rows) != len(cases):
        raise SystemExit(f'the harness answered {len(rows)} of {len(cases)} instants')

    steps = {'seconds': 1000, 'minutes': 60000, 'hours': 3600000}
    # A local-hour truncation is genuinely ambiguous inside a fold, so Hours is
    # held to the bound (and to the documented fallback) while the precisions
    # CEDAR uses — Minutes and Seconds, whose truncation is unambiguous because
    # every timezone offset is a whole number of minutes — are pinned exactly.
    for row in rows:
        for precision, step in steps.items():
            delay = row[precision]
            if not isinstance(delay, (int, float)) or delay <= 0 or delay > step:
                raise SystemExit(f'{precision} precision armed {delay} ms at {row["ms"]} (must be in (0, {step}])')
            raw = step - (row['ms'] % step) if row['ms'] % step else step
            expected = max(16, raw)   # one frame is the documented floor
            if precision == 'hours':
                if delay not in (expected, step):
                    raise SystemExit(f'hours precision armed {delay} ms at {row["ms"]}, expected {expected} or {step}')
            elif delay != expected:
                raise SystemExit(f'{precision} precision armed {delay} ms at {row["ms"]}, expected {expected}')

    floors = re.search(r'WALLCLOCK_FLOORS (.*)', output)
    if not floors:
        print(output)
        raise SystemExit('the harness printed no truncation table')
    for row in json.loads(floors.group(1)):
        ms = row['ms']
        for precision, step in steps.items():
            want = ms - (ms % step)
            if precision == 'hours':
                # The window assumes whole-hour UTC offsets, which holds for the
                # TZ this run pins (America/New_York); a half-hour zone would sit
                # outside it. CEDAR itself only asks for Minutes or Seconds.
                if not want - 3600000 <= row[precision] <= want:
                    raise SystemExit(f'hours precision truncated {ms} to {row[precision]}, far from {want}')
            elif row[precision] != want:
                raise SystemExit(f'{precision} precision truncated {ms} to {row[precision]}, expected {want}')

    dates = re.search(r'WALLCLOCK_DATE (\d+) (\d+)', output)
    if not dates or dates.group(1) != '0' or dates.group(2) != '0':
        print(output)
        raise SystemExit('a Minutes clock must publish a date truncated to the minute')

    # The live reading must be the current minute, not a coarser truncation.
    live = re.search(r'WALLCLOCK_LIVE (\d+) (\d+) (\d+) (\S+)', output)
    if not live:
        print(output)
        raise SystemExit('the harness printed no live reading')
    minute, now_minute, hour, shown = int(live.group(1)), int(live.group(2)), int(live.group(3)), live.group(4)
    if abs(minute - now_minute) > 1:
        print(output)
        raise SystemExit(f'the live Minutes clock reads minute {minute} while the wall clock says {now_minute} (shows {shown})')

    step_line = re.search(r'WALLCLOCK_STEPS (\d+) (\d+) (\d+)', output)
    if not step_line:
        print(output)
        raise SystemExit('the live clocks printed no armed delay')
    for value, limit in zip((int(g) for g in step_line.groups()), (60000, 1000, 3600000)):
        if not 0 < value <= limit:
            print(output)
            raise SystemExit(f'the live clocks armed {value} ms, outside its step')

    ticks_line = re.search(r'WALLCLOCK_TICKS (\d+)', output)
    if not ticks_line or int(ticks_line.group(1)) < 1:
        print(output)
        raise SystemExit('the clock did not tick within 1.3 s of starting')

    fallback = re.search(r'WALLCLOCK_FALLBACK (-?\d+) (-?\d+) (-?\d+) (-?\d+)', output)
    if not fallback:
        print(output)
        raise SystemExit('the harness printed no fallback probes')
    negative, nan, infinite, odd_precision = (int(g) for g in fallback.groups())
    if (negative, nan, infinite) != (60000, 1000, 60000):
        print(output)
        raise SystemExit(f'a nonsensical instant must arm one whole step, not 1 ms: {negative} {nan} {infinite}')
    if not 0 < odd_precision <= 3600000:
        print(output)
        raise SystemExit(f'an unknown precision armed {odd_precision} ms outside one hour')

    print(f'PASS: wallclock delay bounded and exact at {len(cases)} instants, '
          f'{len(traps)} US/Eastern and {len(howe_traps)} Lord Howe fold instants '
          f'where the SystemClock arithmetic (truncate, add a step, measure) goes negative')


if __name__ == '__main__':
    sys.exit(main())
