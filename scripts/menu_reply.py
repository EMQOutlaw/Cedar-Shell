#!/usr/bin/env python3
"""Answer a Go select/input prompt for a waiting script.

Omarchy's prompt helpers create a selection file with mktemp, remove a second
mktemp name to use as the done marker, hand both paths to the shell over IPC,
and poll for the marker. The paths therefore arrive from any local IPC caller.
This helper only ever writes where that protocol can legitimately point:

- both paths are absolute and inside a temporary directory;
- the selection file must already exist, be a regular file owned by this user,
  and is opened without following symlinks;
- the done marker must not exist yet and is created exclusively.

No shell is involved; the request is JSON on stdin."""
import json
import os
import stat
import sys
import tempfile
from pathlib import Path


def temp_roots():
    roots = [Path(tempfile.gettempdir()), Path('/tmp'), Path('/var/tmp')]
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if runtime:
        roots.append(Path(runtime))
    return [r.resolve() for r in roots if r.is_absolute()]


def inside_temp(path):
    parent = path.parent.resolve()
    return any(parent == root or root in parent.parents for root in temp_roots())


def check_path(value):
    if not isinstance(value, str) or not value or '\0' in value or '\n' in value:
        raise ValueError('Reply paths must be plain absolute paths.')
    path = Path(value)
    if not path.is_absolute() or not inside_temp(path):
        raise ValueError('Reply files must live in a temporary directory.')
    return path


def write_selection(path, selection):
    fd = os.open(path, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError('Selection file is not a regular file owned by you.')
        os.write(fd, (selection + '\n').encode())
    finally:
        os.close(fd)


def mark_done(path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    os.close(fd)


def reply(request):
    done = check_path(request.get('doneFile'))
    selection = request.get('selection')
    if selection is not None:
        if not isinstance(selection, str) or len(selection) > 65536:
            raise ValueError('Selection must be a short string.')
        write_selection(check_path(request.get('selectionFile')), selection)
    mark_done(done)
    return {}


if __name__ == '__main__':
    try:
        print(json.dumps({'ok': True, 'data': reply(json.loads(sys.stdin.readline() or '{}'))}))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        sys.exit(1)
