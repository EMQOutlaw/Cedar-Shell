#!/usr/bin/env python3
"""Bounded read-only lockscreen sources. No package refresh or device wake-up."""
import concurrent.futures
import datetime as dt
import json
import os
from pathlib import Path
import stat
import subprocess
import time
from desktop_runtime import omarchy


def command(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=3)
        return p.stdout if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def agenda(path, now):
    try:
        if path.stat().st_size > 65536:
            raise ValueError('too large')
        data = json.loads(path.read_text())
        # A publisher must refresh daily; a forgotten feed must not masquerade as live.
        stamp = dt.datetime.fromisoformat(data['updatedAt'])
        if stamp.tzinfo is None or not -60 <= now-stamp.timestamp() <= 86400:
            return {'status': 'stale', 'events': []}
        events = []
        for row in data.get('events', [])[:100]:
            at = dt.datetime.fromisoformat(row['start'])
            if at.tzinfo is None:
                continue
            if at.timestamp() >= now:
                events.append({'at': at.timestamp()*1000, 'title': str(row.get('title', 'Calendar event'))[:160]})
        return {'status': 'ready', 'events': sorted(events, key=lambda e:e['at'])}
    except FileNotFoundError:
        return {'status': 'unconfigured', 'events': []}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return {'status': 'unavailable', 'events': []}


def private_dir(path):
    try:info=os.lstat(path)
    except OSError:return False
    return stat.S_ISDIR(info.st_mode) and info.st_uid==os.getuid() and not info.st_mode&0o022


def reminder_title(path):
    """Read a reminder message without following links: a regular file this
    user owns, at most 4 KiB."""
    try:fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    except OSError:return ''
    try:
        info=os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_size>4096:return ''
        return os.read(fd,4096).decode('utf-8','replace').strip()[:160]
    except OSError:return ''
    finally:os.close(fd)


def reminders():
    if not omarchy(): return []
    raw = command(['systemctl', '--user', 'list-timers', '--all', '--output=json', 'omarchy-reminder-*.timer'])
    if raw is None:
        return None
    try:
        rows=[]
        # Titles come only from this user's private runtime directory; shared
        # /tmp could hold another account's symlink to a private file.
        runtime=os.environ.get('XDG_RUNTIME_DIR')
        base=Path(runtime)/'omarchy-reminders' if runtime and private_dir(Path(runtime)/'omarchy-reminders') else None
        for row in json.loads(raw):
            unit=row.get('unit','')
            if not unit.startswith('omarchy-reminder-') or '/' in unit or not unit.endswith('.timer'):
                continue
            at=float(row.get('next') or 0)/1000
            if at<=time.time()*1000:
                continue
            title='Reminder'
            if base is not None:title=reminder_title(base/(unit[:-6]+'.message')) or title
            rows.append({'at':at,'title':title})
        return sorted(rows,key=lambda r:r['at'])
    except (ValueError,TypeError):
        return None


def failed(user):
    raw=command(['systemctl']+(['--user'] if user else [])+['--failed','--no-legend','--no-pager','--plain'])
    return None if raw is None else len([line for line in raw.splitlines() if '.service' in line])


def gpu():
    # Never invoke nvidia-smi: querying it may wake a suspended discrete GPU.
    rows=[]
    for device in Path('/sys/class/drm').glob('card[0-9]*/device'):
        try:
            if (device/'power/runtime_status').read_text().strip()!='active':continue
            load=int((device/'gpu_busy_percent').read_text())
            rows.append({'name':device.parent.name,'load':load})
        except (OSError,ValueError):pass
    return rows


def snapshot():
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        tasks=[pool.submit(reminders),pool.submit(failed,True),pool.submit(failed,False)]
        reminder,user,system=[t.result() for t in tasks]
    config=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))/'cedar'
    return {'at':time.time()*1000,'reminders':reminder,'failed':None if user is None or system is None else user+system,
            'agenda':agenda(config/'trailwatch-agenda.json',time.time()),'gpus':gpu()}

if __name__=='__main__':
    print(json.dumps({'ok':True,'data':snapshot()}))
