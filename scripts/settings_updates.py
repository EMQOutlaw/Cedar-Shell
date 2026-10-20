"""On-demand Settings view of the existing managed updater; never installs."""
import json
import os
import sys
import time
from pathlib import Path
import desktop_runtime as runtime
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from installer.engine.update import Updater, installed_channel, content_digest


def state_path():
    return runtime.xdg('STATE','.local/state')/'cedar/settings-update-status.json'


def status():
    try:
        record=runtime.read_json(state_path())
        if not isinstance(record,dict) or record.get('state') not in ('current','available','error'):
            raise ValueError('Invalid update status')
        if record.get('sourceDigest')!=content_digest(ROOT):
            return {'state':'unknown','detail':'CEDAR changed since the last check.'}
        return record
    except (OSError,ValueError,TypeError):
        return {'state':'unknown','detail':'No verified update check is recorded.'}


def check():
    channel=os.environ.get('CEDAR_INSTALLER_CHANNEL') or installed_channel() or 'stable'
    record={'sourceDigest':content_digest(ROOT),'channel':channel,'state':'error'}
    try:
        result=Updater(ROOT,channel=channel).run()
        record.update(state='current' if result.get('current') is True else 'available',
                      checkedAt=time.time(),version=result.get('version',''),
                      detail='Verified against '+channel+' channel.')
    except Exception as error:
        record['detail']=str(error)
    runtime.atomic(state_path(),(json.dumps(record)+'\n').encode())
    return record
