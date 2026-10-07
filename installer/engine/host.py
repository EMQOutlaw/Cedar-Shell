"""Everything the installer asks the machine, behind one object.

The engine never calls subprocess, os or pathlib directly for facts about the
host; it asks a Host. Tests hand it a FakeHost with scripted files, commands
and processes, so detection, planning, backup and resume are exercised
against fixtures instead of the developer's real home directory.
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

PROC = Path('/proc')
MAX_READ = 2 * 1024 * 1024


class Host:
    def __init__(self, home=None, environ=None):
        self.environ = dict(os.environ if environ is None else environ)
        self.home = Path(home or self.environ.get('HOME') or Path.home())

    # -- paths ---------------------------------------------------------
    def xdg(self, kind, default):
        value = self.environ.get('XDG_' + kind + '_HOME')
        path = Path(value) if value else self.home / default
        return path if path.is_absolute() else self.home / default

    def config_home(self): return self.xdg('CONFIG', '.config')
    def data_home(self): return self.xdg('DATA', '.local/share')
    def state_home(self): return self.xdg('STATE', '.local/state')
    def cache_home(self): return self.xdg('CACHE', '.cache')

    # -- files ---------------------------------------------------------
    def exists(self, path): return Path(path).exists()
    def is_file(self, path): return Path(path).is_file()
    def is_dir(self, path): return Path(path).is_dir()
    def is_symlink(self, path): return Path(path).is_symlink()

    def read(self, path, limit=MAX_READ):
        try:
            with Path(path).open('rb') as stream:
                raw = stream.read(limit + 1)
        except OSError:
            return None
        if len(raw) > limit:
            return None
        return raw.decode('utf-8', 'replace')

    def read_bytes(self, path, limit=4096):
        try:
            with Path(path).open('rb') as stream:
                return stream.read(limit)
        except OSError:
            return None

    def listdir(self, path):
        try:
            return sorted(p.name for p in Path(path).iterdir())
        except OSError:
            return []

    def glob(self, path, pattern):
        try:
            return sorted(str(p) for p in Path(path).glob(pattern))
        except OSError:
            return []

    def disk_free(self, path):
        probe = Path(path)
        while not probe.exists() and probe != probe.parent:
            probe = probe.parent
        try:
            usage = shutil.disk_usage(probe)
        except OSError:
            return None
        return {'free': usage.free, 'total': usage.total, 'path': str(probe)}

    def writable(self, path):
        probe = Path(path)
        while not probe.exists() and probe != probe.parent:
            probe = probe.parent
        return os.access(probe, os.W_OK)

    # -- commands ------------------------------------------------------
    def which(self, name): return shutil.which(name)

    def run(self, argv, timeout=20, env=None):
        """(returncode, stdout, stderr); a missing command is (127, '', message)."""
        try:
            result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                    env={**self.environ, 'LC_ALL': 'C', **(env or {})})
        except FileNotFoundError:
            return 127, '', argv[0] + ' is not installed'
        except subprocess.TimeoutExpired:
            return 124, '', argv[0] + ' timed out'
        except OSError as error:
            return 126, '', str(error)
        return result.returncode, result.stdout, result.stderr

    def stream(self, argv, on_line, timeout=None, env=None, stdin=None):
        """Run a long command, handing each output line to on_line; returns the exit code."""
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   stdin=stdin, env={**self.environ, **(env or {})})
        try:
            for line in process.stdout:
                on_line(line.rstrip('\n'))
            return process.wait(timeout=timeout)
        finally:
            if process.poll() is None:
                process.kill()

    # -- system facts --------------------------------------------------
    def os_release(self):
        try:
            return dict(platform.freedesktop_os_release())
        except OSError:
            return {}

    def machine(self): return platform.machine()

    def kernel(self): return platform.release()

    def python_version(self): return sys.version_info[:3]

    def uid(self): return os.getuid()

    def has_tty(self):
        try:
            with open('/dev/tty', 'rb'):
                return True
        except OSError:
            return False

    def processes(self):
        """[{pid, exe, argv}] for this user's processes; unreadable entries are skipped."""
        rows = []
        try:
            entries = [p for p in PROC.iterdir() if p.name.isdigit()]
        except OSError:
            return rows
        uid = os.getuid()
        for entry in entries:
            try:
                if entry.stat().st_uid != uid:
                    continue
                argv = (entry / 'cmdline').read_bytes().split(b'\0')
                argv = [a.decode('utf-8', 'replace') for a in argv if a]
                try:
                    exe = os.readlink(entry / 'exe')
                except OSError:
                    exe = argv[0] if argv else ''
                if not argv:
                    continue
                rows.append({'pid': int(entry.name), 'exe': exe.replace(' (deleted)', ''), 'argv': argv})
            except OSError:
                continue
        return rows

    def user_units(self):
        """Enabled or running systemd user units by name; empty without systemd."""
        code, out, _ = self.run(['systemctl', '--user', 'list-units', '--type=service', '--all', '--no-legend', '--plain'], timeout=10)
        units = {}
        if code == 0:
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 4 and parts[0].endswith('.service'):
                    units[parts[0]] = {'load': parts[1], 'active': parts[2], 'sub': parts[3]}
        code, out, _ = self.run(['systemctl', '--user', 'list-unit-files', '--no-legend', '--plain'], timeout=10)
        if code == 0:
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 2:
                    units.setdefault(parts[0], {})['state'] = parts[1]
        return units

    def packages(self):
        """Installed package name → version for the detected package manager."""
        if self.which('pacman'):
            code, out, _ = self.run(['pacman', '-Q'], timeout=20)
            if code == 0:
                return dict(line.split(' ', 1) for line in out.splitlines() if ' ' in line)
        elif self.which('dpkg-query'):
            code, out, _ = self.run(['dpkg-query', '-W', '-f=${Package} ${Version}\n'], timeout=20)
            if code == 0:
                return dict(line.split(' ', 1) for line in out.splitlines() if ' ' in line)
        elif self.which('rpm'):
            code, out, _ = self.run(['rpm', '-qa', '--qf', '%{NAME} %{VERSION}\n'], timeout=30)
            if code == 0:
                return dict(line.split(' ', 1) for line in out.splitlines() if ' ' in line)
        return {}


class FakeHost(Host):
    """A scripted machine for tests: files, commands, processes and units are dictionaries."""

    def __init__(self, home='/home/station', environ=None, files=None, dirs=None, commands=None,
                 processes=None, units=None, packages=None, which=None, release=None, machine='x86_64',
                 free=200 * 1024 ** 3, tty=True, python=(3, 12, 0)):
        super().__init__(home=home, environ={'HOME': home, **(environ or {})})
        self.files = {str(Path(k)): v for k, v in (files or {}).items()}
        self.dirs = {str(Path(d)) for d in (dirs or [])}
        for path in self.files:
            parent = Path(path).parent
            while str(parent) not in self.dirs and parent != parent.parent:
                self.dirs.add(str(parent)); parent = parent.parent
        self.commands = commands or {}
        self.process_rows = processes or []
        self.units = units or {}
        self.package_rows = packages or {}
        self.available = set(which or [])
        self.release = release if release is not None else {'ID': 'arch', 'NAME': 'Arch Linux', 'PRETTY_NAME': 'Arch Linux'}
        self.machine_name = machine
        self.free = free
        self.tty = tty
        self.python = python
        self.calls = []

    def exists(self, path): return str(Path(path)) in self.files or str(Path(path)) in self.dirs
    def is_file(self, path): return str(Path(path)) in self.files
    def is_dir(self, path): return str(Path(path)) in self.dirs
    def is_symlink(self, path): return False
    def read(self, path, limit=MAX_READ):
        value = self.files.get(str(Path(path)))
        return None if value is None else str(value)
    def read_bytes(self, path, limit=4096):
        value = self.files.get(str(Path(path)))
        return None if value is None else (value if isinstance(value, bytes) else str(value).encode())
    def listdir(self, path):
        base = str(Path(path)).rstrip('/') + '/'
        names = {p[len(base):].split('/', 1)[0] for p in list(self.files) + list(self.dirs) if p.startswith(base)}
        return sorted(n for n in names if n)
    def glob(self, path, pattern):
        import fnmatch
        base = str(Path(path)).rstrip('/') + '/'
        return sorted(p for p in list(self.files) + list(self.dirs) if p.startswith(base) and fnmatch.fnmatch(p[len(base):], pattern))
    def disk_free(self, path): return {'free': self.free, 'total': self.free * 2, 'path': str(path)}
    def writable(self, path): return True
    def which(self, name): return '/usr/bin/' + name if name in self.available else None
    def run(self, argv, timeout=20, env=None):
        self.calls.append(list(argv))
        key = ' '.join(argv)
        for pattern, reply in self.commands.items():
            if key == pattern or key.startswith(pattern + ' ') or pattern == argv[0]:
                if callable(reply):
                    return reply(argv)
                if isinstance(reply, tuple):
                    return reply
                return 0, str(reply), ''
        if argv[0] not in self.available:
            return 127, '', argv[0] + ' is not installed'
        return 0, '', ''
    def stream(self, argv, on_line, timeout=None, env=None, stdin=None):
        code, out, err = self.run(argv, env=env)
        for line in (out + err).splitlines():
            on_line(line)
        return code
    def os_release(self): return dict(self.release)
    def machine(self): return self.machine_name
    def kernel(self): return '6.0.0-fixture'
    def python_version(self): return self.python
    def uid(self): return 1000
    def has_tty(self): return self.tty
    def processes(self): return [dict(p) for p in self.process_rows]
    def user_units(self): return dict(self.units)
    def packages(self): return dict(self.package_rows)
