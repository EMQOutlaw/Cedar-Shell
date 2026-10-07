"""The versioned backup CEDAR takes before it changes anything of yours.

~/.local/state/cedar/installations/<timestamp>/
    manifest.json      what was found, what will change, what did change
    restore.sh         a plain shell script that puts the copied files back
    config/            copies of the files the plan may touch, by home-relative path
    services.json      user services and their state before installation
    packages.json      installed packages before installation (name → version)

It copies the configuration the plan intends to touch, never ~/.config
wholesale. Restoration compares each current file with what the installer
wrote; a file you edited afterwards is left alone and reported.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import time

FORMAT = 1


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def snapshot(path):
    path = Path(path)
    if path.is_symlink():
        return {'type': 'link', 'target': os.readlink(path)}
    if path.is_file():
        info = path.stat()
        return {'type': 'file', 'sha256': digest(path), 'mode': stat.S_IMODE(info.st_mode), 'bytes': info.st_size}
    if path.is_dir():
        return {'type': 'directory'}
    return {'type': 'absent'}


class Backup:
    def __init__(self, base, home, installer_version, cedar_version, stamp=None):
        self.home = Path(home)
        self.stamp = stamp or time.strftime('%Y-%m-%dT%H%M%S')
        self.root = Path(base) / self.stamp
        self.manifest = {
            'format': FORMAT, 'installerVersion': installer_version, 'cedarVersion': cedar_version,
            'timestamp': self.stamp, 'createdAt': time.time(), 'environment': {}, 'options': {},
            'files': [], 'filesChanged': [], 'filesCreated': [], 'servicesDisabled': [], 'servicesEnabled': [],
            'packagesInstalled': [], 'packagesRemoved': [], 'stagesCompleted': [], 'notes': [],
        }

    # -- creation ------------------------------------------------------
    def create(self, environment, options, services=None, packages=None):
        self.root.mkdir(parents=True, exist_ok=False, mode=0o700)
        (self.root / 'config').mkdir(mode=0o700)
        self.manifest['environment'] = environment
        self.manifest['options'] = options
        self.write_json('services.json', services or {})
        self.write_json('packages.json', packages or {})
        self.save()
        return self

    def relative(self, path):
        path = Path(path)
        try:
            return str(path.relative_to(self.home))
        except ValueError:
            return 'outside' + str(path)

    def add(self, path, reason=''):
        """Copy one file (or record its absence) so it can be restored later."""
        path = Path(path)
        entry = {'path': str(path), 'home': self.relative(path), 'reason': reason, 'before': snapshot(path), 'copy': None}
        if entry['before']['type'] == 'file':
            copy = self.root / 'config' / entry['home']
            copy.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copy2(path, copy)
            os.chmod(copy, 0o600)
            entry['copy'] = str(copy.relative_to(self.root))
        elif entry['before']['type'] == 'directory':
            copy = self.root / 'config' / entry['home']
            shutil.copytree(path, copy, symlinks=True, dirs_exist_ok=True)
            entry['copy'] = str(copy.relative_to(self.root))
        self.manifest['files'].append(entry)
        self.save()
        return entry

    def changed(self, path):
        path = str(path)
        entry = next((e for e in self.manifest['files'] if e['path'] == path), None)
        after = snapshot(path)
        if entry is None:
            entry = {'path': path, 'home': self.relative(path), 'reason': 'created', 'before': {'type': 'absent'}, 'copy': None}
            self.manifest['files'].append(entry)
        entry['after'] = after
        target = self.manifest['filesCreated'] if entry['before']['type'] == 'absent' else self.manifest['filesChanged']
        if path not in target:
            target.append(path)
        self.save()

    def stage(self, name):
        if name not in self.manifest['stagesCompleted']:
            self.manifest['stagesCompleted'].append(name)
        self.save()

    def note(self, text):
        self.manifest['notes'].append(text); self.save()

    def record(self, key, value):
        if value not in self.manifest[key]:
            self.manifest[key].append(value)
        self.save()

    def write_json(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
        os.chmod(path, 0o600)

    def save(self):
        self.write_json('manifest.json', self.manifest)
        self.write_restore_script()

    def write_restore_script(self):
        lines = ['#!/bin/sh', '# CEDAR installer backup ' + self.stamp + ' — puts the copied files back.',
                 '# Prefer: cedar-install --restore  (verifies each file first). This script is the plain fallback.',
                 'set -eu', 'here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"']
        for entry in self.manifest['files']:
            target = entry['path']
            if entry['before']['type'] == 'file' and entry['copy']:
                lines.append('mkdir -p "$(dirname -- ' + _sh(target) + ')" && cp -p "$here/' + entry['copy'] + '" ' + _sh(target))
            elif entry['before']['type'] == 'absent':
                lines.append('rm -f ' + _sh(target) + '  # did not exist before CEDAR')
        for unit in self.manifest['servicesDisabled']:
            lines.append('systemctl --user enable --now ' + _sh(unit) + ' || true')
        for unit in self.manifest['servicesEnabled']:
            lines.append('systemctl --user disable --now ' + _sh(unit) + ' || true')
        lines.append('echo "Restored the files CEDAR copied on ' + self.stamp + '. Packages were left installed."')
        path = self.root / 'restore.sh'
        path.write_text('\n'.join(lines) + '\n')
        os.chmod(path, 0o700)

    # -- restoration ---------------------------------------------------
    @classmethod
    def load(cls, root):
        root = Path(root)
        manifest = json.loads((root / 'manifest.json').read_text())
        if manifest.get('format') != FORMAT:
            raise ValueError('Unsupported backup manifest format')
        backup = cls(root.parent, Path.home(), manifest['installerVersion'], manifest['cedarVersion'], stamp=root.name)
        backup.manifest = manifest
        return backup

    @staticmethod
    def latest(base):
        base = Path(base)
        if not base.is_dir():
            return None
        candidates = sorted(p for p in base.iterdir() if (p / 'manifest.json').is_file())
        return candidates[-1] if candidates else None

    def check_restore(self):
        """Which recorded files can be put back safely, and which you edited since."""
        safe, conflicts = [], []
        for entry in self.manifest['files']:
            now = snapshot(entry['path'])
            after = entry.get('after')
            if after is None:
                # Never changed by the installer: nothing to restore.
                continue
            if now == entry['before']:
                continue
            if now != after:
                conflicts.append(entry['path'])
            else:
                safe.append(entry)
        return safe, conflicts

    def restore(self, dry_run=False):
        safe, conflicts = self.check_restore()
        restored = []
        for entry in safe:
            target = Path(entry['path'])
            if dry_run:
                restored.append(str(target)); continue
            if entry['before']['type'] == 'file':
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(self.root / entry['copy'], target)
                os.chmod(target, entry['before']['mode'])
            elif entry['before']['type'] == 'absent':
                if target.is_file() or target.is_symlink():
                    target.unlink()
            elif entry['before']['type'] == 'link':
                if target.exists() or target.is_symlink():
                    target.unlink()
                target.symlink_to(entry['before']['target'])
            restored.append(str(target))
        if not dry_run:
            self.manifest['restoredAt'] = time.time(); self.save()
        return {'restored': restored, 'conflicts': conflicts}


def _sh(value):
    return "'" + str(value).replace("'", "'\\''") + "'"
