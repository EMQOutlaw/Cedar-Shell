#!/usr/bin/env python3
"""Opt-in, reversible files for Omarchy's existing sleep-lock monitor.

This prepares a private adapter and one service-specific PATH drop-in. It never
starts/restarts a service, reloads systemd, changes the shell, or edits Hyprland.
Explicit activation belongs to the caller after checking that the session is
unlocked. Restoration uses CEDAR's existing transaction journal and preserves
later edits instead of overwriting them.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

import distribution as d

ACTION = 'lock-bridge'
FORMAT = 1
MAX_FILE = 128 * 1024
BASE_PATH = '/usr/share/omarchy/bin:/usr/local/bin:/usr/bin'


def locations():
    base = d.paths()['data'] / 'lock-bridge'
    return {
        'bridge': base / 'lock_bridge.py',
        'shim': base / 'lock-shim/omarchy-shell',
        'dropin': d.xdg('CONFIG', '.config') / 'systemd/user/omarchy-sleep-lock.service.d/50-cedar-lock-bridge.conf',
        'receipt': d.paths()['state'] / 'lock-bridge-install.json',
    }


def check_parents(path):
    owned_roots = (d.xdg('CONFIG', '.config'), d.xdg('DATA', '.local/share'), d.xdg('STATE', '.local/state'))
    for parent in (path.parent, *path.parent.parents):
        if parent.is_symlink():
            raise d.Refused('Lock bridge paths must not traverse symlinks: ' + str(parent))
        if parent.exists():
            info = parent.stat()
            # System ancestors can be remapped inside a sandbox; every XDG
            # root and descendant belongs to this user, including drop-ins.
            managed = any(parent.is_relative_to(root) for root in owned_roots)
            if (not stat.S_ISDIR(info.st_mode)
                    or (managed and info.st_uid != os.getuid())
                    or (info.st_mode & 0o022 and (managed or not info.st_mode & stat.S_ISVTX))):
                raise d.Refused('Unsafe lock bridge parent: ' + str(parent))


def read_regular(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as exc:
        raise d.Refused('Cannot read a regular lock bridge file: ' + str(path)) from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_FILE:
            raise d.Refused('Lock bridge files must be regular and at most 128 KiB.')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_FILE + 1)
        if len(data) > MAX_FILE:
            raise d.Refused('Lock bridge file exceeded its size limit.')
        return data
    finally:
        os.close(fd)


def systemd_quote(value):
    if any(character in value for character in ('\x00', '\n', '\r')):
        raise d.Refused('A service environment path contains unsupported control characters.')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%') + '"'


def dropin_content(shim):
    if ':' in str(shim.parent):
        raise d.Refused('A lock bridge directory cannot contain a PATH separator.')
    return ('# CEDAR-owned; restore with lock_bridge_install.py --restore.\n'
            '# Only this monitor receives the adapter PATH. No service is activated here.\n'
            '[Service]\nEnvironment=' + systemd_quote('PATH=' + str(shim.parent) + ':' + BASE_PATH) + '\n').encode()


def receipt_journal(paths):
    receipt = paths['receipt']
    if not receipt.exists() and not receipt.is_symlink():
        return None
    try:
        value = json.loads(read_regular(receipt))
    except (ValueError, UnicodeError) as exc:
        raise d.Refused('The lock bridge ownership receipt is unreadable.') from exc
    if not isinstance(value, dict) or value.get('format') != FORMAT or value.get('action') != ACTION:
        raise d.Refused('The lock bridge ownership receipt is invalid.')
    journal_name = value.get('journal')
    if not isinstance(journal_name, str):
        raise d.Refused('The lock bridge recovery journal is invalid.')
    relative = Path(journal_name)
    if (relative.is_absolute() or len(relative.parts) != 3 or relative.parts[0] != 'transactions'
            or relative.parts[2] != 'journal.json' or '..' in relative.parts):
        raise d.Refused('The lock bridge recovery journal leaves its owned location.')
    journal = d.paths()['state'] / relative
    check_parents(journal)
    try:
        record = json.loads(read_regular(journal))
    except (ValueError, UnicodeError) as exc:
        raise d.Refused('The lock bridge recovery journal is unreadable.') from exc
    expected = {str(path) for path in paths.values()}
    entries = record.get('files') if isinstance(record, dict) else None
    if (not isinstance(record, dict) or record.get('action') != ACTION
            or not isinstance(entries, list) or len(entries) != len(expected)
            or any(not isinstance(entry, dict) for entry in entries)
            or {entry.get('path') for entry in entries} != expected):
        raise d.Refused('The lock bridge recovery journal has an unexpected file scope.')
    return journal


def install(source):
    paths = locations()
    for path in paths.values():
        check_parents(path)
        if path.is_symlink():
            raise d.Refused('Refusing to replace a symlink at ' + str(path))
    source = Path(source)
    bridge = read_regular(source / 'scripts/lock_bridge.py')
    shim = read_regular(source / 'scripts/lock-shim/omarchy-shell')
    compile(bridge, 'lock_bridge.py', 'exec')
    contents = {'bridge': (bridge, 0o644), 'shim': (shim, 0o755),
                'dropin': (dropin_content(paths['shim']), 0o644)}
    with d.exclusive():
        previous = receipt_journal(paths)
        expected_before = {str(path): {'type': 'absent'} for path in paths.values()}
        if previous is None:
            if any(path.exists() for path in paths.values()):
                raise d.Refused('An existing lock bridge file has no ownership receipt; it was left unchanged.')
        else:
            record = d.check_restore_journal(previous)
            if record.get('stage') != 'commit' or any(not d.same(d.info(Path(entry['path'])), entry.get('after') or {})
                                                     for entry in record['files']):
                raise d.Refused('The prior lock bridge installation changed; restore or review its journal first.')
            expected_before = {entry['path']: entry['after'] for entry in record['files']}
            if all(d.same(d.info(paths[name]), {'type': 'file', 'mode': mode,
                                               'sha256': hashlib.sha256(data).hexdigest()})
                   for name, (data, mode) in contents.items()):
                d.private_directory(paths['bridge'].parent)
                d.private_directory(paths['shim'].parent)
                return {'action': 'unchanged', 'journal': str(previous),
                        'files': [str(path) for path in paths.values()], 'activated': False}
        # A private copy remains independent of current-release links.
        d.private_directory(paths['bridge'].parent)
        d.private_directory(paths['shim'].parent)
        transaction = d.Transaction(ACTION)
        try:
            transaction.stage('prepare-lock-bridge')
            entries = {name: transaction.backup(path) for name, path in paths.items()}
            if any(not d.same(entry['before'], expected_before[entry['path']]) for entry in entries.values()):
                raise d.Refused('A lock bridge file changed during preparation; the later edit was preserved.')
            for name, (data, mode) in contents.items():
                transaction.apply_file(entries[name], data, mode)
            receipt = {'format': FORMAT, 'action': ACTION,
                       'journal': str(transaction.path.relative_to(d.paths()['state']))}
            transaction.apply_file(entries['receipt'], (json.dumps(receipt, indent=2) + '\n').encode())
            transaction.commit()
        except Exception:
            # Preserve later edits; the existing recovery engine refuses any
            # mismatch rather than turning a failed install into data loss.
            d.restore_journal(transaction.path)
            raise
    return {'action': 'installed', 'journal': str(transaction.path),
            'files': [str(path) for path in paths.values()], 'activated': False}


def restore():
    paths = locations()
    for path in paths.values():
        check_parents(path)
    with d.exclusive():
        journal = receipt_journal(paths)
        if journal is None:
            raise d.Refused('No owned lock bridge installation is recorded.')
        d.restore_journal(journal)
    return {'action': 'restored', 'journal': str(journal), 'activated': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument('--install', action='store_true')
    operation.add_argument('--restore', action='store_true')
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    try:
        if os.getuid() == 0:
            raise d.Refused('Install the user lock bridge as the desktop user, never root.')
        result = install(args.source) if args.install else restore()
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, SyntaxError, d.Refused) as exc:
        print('CEDAR: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
