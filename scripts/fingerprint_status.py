#!/usr/bin/env python3
"""Detect enrollment only; authentication always goes through PAM."""
import json
import os
from pathlib import Path
import pwd
import re
import subprocess


def available():
    if not Path('/etc/pam.d/omarchy-lock-fingerprint').is_file():
        return False
    try:
        result = subprocess.run(
            ['fprintd-list', pwd.getpwuid(os.getuid()).pw_name],
            capture_output=True, text=True, timeout=8,
            env={**os.environ, 'LC_ALL': 'C'})
        return result.returncode == 0 and bool(re.search(r'^\s*-\s*#\d+:\s*\S+', result.stdout, re.M))
    except (OSError, subprocess.TimeoutExpired):
        return False


if __name__ == '__main__':
    print(json.dumps({'ok': True, 'data': {'available': available()}}))
