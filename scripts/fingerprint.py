#!/usr/bin/env python3
"""Is fingerprint unlock usable here? PAM service present and a print enrolled.

Read-only: no enrollment, no verification. Verification itself runs through
PAM inside the shell, with the same service Omarchy's own lock uses."""
import json
import os
import pwd
import shutil
import subprocess
import sys
from pathlib import Path

SERVICE = 'omarchy-lock-fingerprint'


def fingers(output):
    """Count enrolled prints in fprintd-list output ('- #0: right-index-finger')."""
    return sum(1 for line in str(output or '').splitlines() if line.strip().startswith('- #'))


def status(pam_dir='/etc/pam.d', user=None, run=subprocess.run):
    user = user or os.environ.get('USER') or pwd.getpwuid(os.getuid()).pw_name
    if not (Path(pam_dir) / SERVICE).is_file():
        return {'configured': False, 'fingers': 0, 'service': SERVICE, 'reason': 'No ' + SERVICE + ' PAM service.'}
    if not shutil.which('fprintd-list'):
        return {'configured': False, 'fingers': 0, 'service': SERVICE, 'reason': 'fprintd is not installed.'}
    try:
        result = run(['fprintd-list', user], capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return {'configured': False, 'fingers': 0, 'service': SERVICE, 'reason': 'The fingerprint service did not answer.'}
    count = fingers(result.stdout) if result.returncode == 0 else 0
    return {'configured': count > 0, 'fingers': count, 'service': SERVICE,
            'reason': '' if count else 'No fingerprint is enrolled for this user.'}


if __name__ == '__main__':
    try:
        json.loads(sys.stdin.readline() or '{}')
        print(json.dumps({'ok': True, 'data': status()}))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
