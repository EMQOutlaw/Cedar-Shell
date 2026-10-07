"""The operations of an installation, bound to CEDAR's existing engine.

Each step is a small function over a Context. The versioned copy, the cedar
command, offline recovery, the offscreen shell check and the session
handoff all come from scripts/distribution.py and the session adapters that
already exist; this module sequences them, reports their real results and
records what changed in the backup manifest.
"""
import contextlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time

from . import operations as ops
from .backup import Backup
from . import facts as facts_module
from ..migration import providers as migration_providers
from ..providers import packages as package_providers
from ..providers import privilege

SHELL_CHECKS = ('check_navigation.py', 'check_identity.py', 'check_trailwatch.py', 'check_portable_ui.py', 'check_controls.py')


class Context:
    def __init__(self, host, source, facts, plan, options, log, emit, runner=None):
        self.host, self.source, self.facts, self.plan, self.options = host, Path(source), facts, plan, options
        self.log, self.emit, self.runner = log, emit, runner
        self.backup = None
        self.installed = None
        self._modules = {}

    # The existing engine lives in scripts/; import it from the source being installed.
    def module(self, name):
        if name not in self._modules:
            scripts = str(self.source / 'scripts')
            if scripts not in sys.path:
                sys.path.insert(0, scripts)
            self._modules[name] = __import__(name)
        return self._modules[name]

    @contextlib.contextmanager
    def capture(self, op):
        """Route the existing engine's print() output into the structured log."""
        class Stream(io.TextIOBase):
            def __init__(stream, ctx): stream.ctx = ctx; stream.buffer_ = ''; stream.inside = False
            def write(stream, text):
                # A listener that prints while handling a line must not come back here.
                if stream.inside:
                    return len(text)
                stream.buffer_ += text
                stream.inside = True
                try:
                    while '\n' in stream.buffer_:
                        line, stream.buffer_ = stream.buffer_.split('\n', 1)
                        if line.strip():
                            stream.ctx.output(op, line)
                finally:
                    stream.inside = False
                return len(text)
            def flush(stream): pass
        stream = Stream(self)
        with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
            yield
        if stream.buffer_.strip():
            self.output(op, stream.buffer_)

    def output(self, op, line):
        record = self.log.output(line, op.id) if self.log else {'message': line}
        self.emit('log', {'operation': op.id, 'line': record['message']})

    def progress(self, op, fraction, detail=None):
        if self.runner:
            self.runner.update(op, progress=fraction, detail=detail)

    def provider(self):
        return migration_providers.by_id(self.facts['environment']['chosen'])

    def backup_dir(self):
        return self.host.state_home() / 'cedar/installations'

    def config_dir(self):
        return self.host.config_home() / 'cedar'


def write_private_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def read_json(path, default):
    try:
        value = json.loads(Path(path).read_text())
        return value if isinstance(value, dict) else default
    except (OSError, ValueError):
        return default


# ---------------------------------------------------------------- backup
def backup_run(ctx, op):
    facts, host = ctx.facts, ctx.host
    targets = set(ctx.provider().backup_targets(facts, host))
    targets.update(facts['hyprland'].get('files', []))
    config = ctx.config_dir()
    for name in ('settings.json', 'desktop.json', 'theme.json', 'installation.json', 'hypr/settings.json'):
        targets.add(str(config / name))
    targets.add(str(host.home / '.local/bin/cedar'))
    environment = {'id': facts['environment']['id'], 'name': facts['environment']['name'], 'evidence': facts['environment'].get('evidence', []),
                   'distro': facts['distro']['name'], 'hyprland': facts['hyprlandVersion'], 'quickshell': facts['quickshellVersion']}
    backup = Backup(ctx.backup_dir(), host.home, facts['installerVersion'], facts['cedarVersion'])
    backup.create(environment, ctx.options, services=facts['userUnits'], packages=facts['packages'])
    existing = [t for t in sorted(targets) if Path(t).exists()]
    for index, target in enumerate(existing):
        backup.add(target, 'may be changed or paused by this installation')
        ctx.progress(op, (index + 1) / max(1, len(existing)), 'Copied ' + Path(target).name)
    ctx.backup = backup
    if ctx.runner:
        ctx.runner.backup = str(backup.root)
        ctx.runner.save()
    op.detail = str(len(existing)) + ' file' + ('s' if len(existing) != 1 else '') + ' copied to ' + str(backup.root)
    ctx.emit('backup', {'path': str(backup.root), 'files': len(existing)})


def backup_verify(ctx, op):
    return ctx.backup is not None and (ctx.backup.root / 'manifest.json').is_file() and (ctx.backup.root / 'restore.sh').is_file()


def reopen_backup(ctx):
    """On resume the backup from the interrupted run is reused, never duplicated."""
    if ctx.backup is None and ctx.runner and ctx.runner.backup and Path(ctx.runner.backup, 'manifest.json').is_file():
        ctx.backup = Backup.load(ctx.runner.backup)
        ctx.backup.home = ctx.host.home
    return ctx.backup


# ---------------------------------------------------------- dependencies
def dependencies_run(ctx, op):
    missing = list(ctx.plan['packages'])
    if not missing:
        raise ops.Skip('All required software is already present')
    provider = package_providers.select(ctx.facts)
    provider.check(ctx.host, missing)
    method = privilege.method(ctx.host, ctx.facts)
    if not method:
        raise RuntimeError(privilege.describe(''))
    ctx.emit('password', {'method': method, 'text': privilege.describe(method)})
    argv = privilege.wrap(method, provider.argv(missing))
    if ctx.log: ctx.log.info('run ' + ' '.join(argv[1:] if method == 'pkexec' else argv[3:]), op.id)
    ctx.progress(op, 0.02, privilege.describe(method))
    seen = 0
    def on_line(line):
        nonlocal seen
        ctx.output(op, line)
        if re.match(r'(?i)^\s*(installing|upgrading|reinstalling|downloading)\b', line):
            seen += 1
            ctx.progress(op, min(0.95, 0.05 + seen / (len(missing) + 4)), line.strip()[:120])
        elif re.match(r'(?i)^(resolving|looking|checking|synchroni|retrieving)', line):
            ctx.progress(op, None, line.strip()[:120])
    code = ctx.host.stream(argv, on_line, timeout=3600)
    if code != 0:
        raise RuntimeError('Package installation did not complete (exit ' + str(code) + '). Nothing on your desktop was changed; your configuration backup is kept.')
    backup = reopen_backup(ctx)
    if backup:
        for package in missing:
            backup.record('packagesInstalled', package)
    op.detail = 'Installed ' + ', '.join(missing)


def dependencies_verify(ctx, op):
    if not ctx.plan['packages']:
        return True
    report = facts_module.dependency_report(ctx.host, ctx.source)
    ctx.facts['dependencies'] = report
    ctx.facts['quickshellInstalled'] = bool(ctx.host.which('qs'))
    still = [p for p in report['missing'] if p in ctx.plan['packages']]
    if still:
        op.error = 'Still missing after installation: ' + ', '.join(still)
        return False
    return True


# --------------------------------------------------------------- runtime
def runtime_run(ctx, op):
    d = ctx.module('distribution')
    ctx.progress(op, 0.1, 'Checking the release, free space and the shell (about half a minute)')
    before = {name: Path(name).exists() for name in (str(ctx.host.home / '.local/bin/cedar'), str(ctx.host.data_home() / 'cedar/current'))}
    # distribution.install validates the shell offscreen (imports plus five
    # rendering checks) before it copies anything, then journals every file.
    with ctx.capture(op):
        d.install(ctx.source, approved=True)
    ctx.installed = d.installed()
    backup = reopen_backup(ctx)
    if backup:
        for name in before:
            backup.changed(name)
        backup.stage('runtime')
    op.detail = 'CEDAR ' + ctx.facts['cedarVersion'] + ' installed to ' + str(ctx.installed)


def runtime_verify(ctx, op):
    d = ctx.module('distribution')
    try:
        ctx.installed = d.installed()
    except Exception as error:  # noqa: BLE001 - reported as a verification failure
        op.error = str(error); return False
    return (ctx.host.home / '.local/bin/cedar').is_file()


# ----------------------------------------------------------------- shell
def shell_run(ctx, op):
    """The installed copy, not the source, loads with this Quickshell and Qt.

    The runtime step already rendered the five offscreen checks on the
    source before copying; here the installed tree proves its imports and
    one rendering check, so a copy that lost a file is caught without
    repeating the whole minute of checks."""
    if not ctx.host.which('qs'):
        raise ops.Skip('Quickshell is not installed, so the shell cannot be loaded here')
    d = ctx.module('distribution')
    root = ctx.installed or d.installed()
    ctx.progress(op, 0.2, 'Loading the required QML imports from the installed copy')
    d.validate_imports(root)
    ctx.progress(op, 0.6, 'Rendering the navigation check from the installed copy')
    with ctx.capture(op):
        d.command([sys.executable, str(root / 'tests' / SHELL_CHECKS[0])], timeout=120)
    op.detail = 'The installed shell loads with Quickshell ' + (ctx.facts['quickshellVersion'] or facts_module.version_of(ctx.host, ['qs', '--version']))


# --------------------------------------------------------------- migrate
def migrate_run(ctx, op):
    if not ctx.options.get('migrate'):
        raise ops.Skip('Migration turned off; existing configuration untouched')
    facts = ctx.facts
    # desktop.py resolves the main Hyprland config when it is imported.
    if facts['hyprland'].get('config'):
        os.environ['CEDAR_HYPR_CONFIG'] = facts['hyprland']['config']
    desktop = ctx.module('desktop')
    config = ctx.config_dir()
    config.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = reopen_backup(ctx)
    imported, notes = [], []
    # CEDAR's own display/input state (scripts/desktop.py OWN): Settings › Displays reads and applies it.
    desktop_path = config / 'hypr/settings.json'
    state = read_json(desktop_path, {'input': {}, 'monitors': [], 'bindings': []})
    if backup: backup.add(desktop_path, 'CEDAR display and input settings')
    ctx.progress(op, 0.2, 'Translating monitor rules')
    monitors = facts['hyprland'].get('monitors', [])
    if monitors and not state.get('monitors'):
        try:
            state['monitors'] = desktop.validate_monitors(monitors, facts['hyprland'].get('liveFull', []))
            imported.append(str(len(monitors)) + ' monitor' + ('s' if len(monitors) != 1 else ''))
        except (ValueError, KeyError) as error:
            notes.append('Monitors were not imported: ' + str(error) + ' Set them in Settings › Displays.')
    elif state.get('monitors'):
        notes.append('Existing CEDAR display settings kept.')
    ctx.progress(op, 0.5, 'Translating keyboard settings')
    keyboard = {k: v for k, v in facts['hyprland'].get('keyboard', {}).items() if k in desktop.INPUTS}
    if keyboard and not state.get('input'):
        try:
            state['input'] = desktop.validate_inputs(keyboard)
            imported.append('keyboard layout')
        except ValueError as error:
            notes.append('Keyboard settings were not imported: ' + str(error))
    if ctx.options.get('keybinds'):
        ctx.progress(op, 0.6, 'Installing CEDAR’s keybinds')
        syntax = facts['hyprland'].get('syntax') or 'lua'
        target = config / 'hypr' / ('keybinds.' + syntax)
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if backup: backup.add(target, 'CEDAR keybinds copy')
        if not target.is_file():
            shutil.copy2(ctx.source / 'themes' / ('keybinds.' + syntax), target); os.chmod(target, 0o600)
            if backup: backup.changed(target)
            imported.append('keybinds')
        else:
            notes.append('Your existing keybinds copy was kept.')
        state['keybinds'] = True
    write_private_json(desktop_path, state)
    if backup: backup.changed(desktop_path)
    if ctx.options.get('keybinds') and facts['compositor']['running'] and facts['hyprland'].get('config') and not facts['hyprland'].get('ambiguous'):
        # Apply now through CEDAR's loader (journaled marker block in the main
        # config, generated.* beside the copy, hyprctl reload + configerrors;
        # desktop.install restores every file it touched if Hyprland refuses).
        ctx.progress(op, 0.7, 'Loading the keybinds into Hyprland')
        main = Path(facts['hyprland']['config'])
        if backup: backup.add(main, 'Hyprland main configuration (CEDAR loader block)')
        try:
            desktop.install(state)
            if backup: backup.changed(main); backup.changed(config / 'hypr' / ('generated.' + syntax))
            imported.append('keybinds loaded')
        except (RuntimeError, OSError, ValueError) as error:
            notes.append('Keybinds were recorded but not loaded into Hyprland: ' + str(error) + ' Apply them from Settings › Displays, or run "cedar ipc settings show keybinds".')
    elif ctx.options.get('keybinds'):
        notes.append('Keybinds are recorded; they load the next time CEDAR applies its Hyprland settings (Settings › Displays › Apply) because the compositor was not running or its main configuration was ambiguous.')
    ctx.progress(op, 0.75, 'Seeding preferred applications')
    settings_path = config / 'settings.json'
    settings = read_json(settings_path, {})
    if backup: backup.add(settings_path, 'CEDAR preferences')
    for key in ('terminal', 'browser', 'editor', 'files'):
        value = facts['apps'].get(key)
        if value and key not in settings:
            # Desktop associations name a .desktop id; CEDAR stores a command.
            if value.endswith('.desktop'):
                if not ctx.host.which('gtk-launch'):
                    continue
                value = 'gtk-launch ' + value
            settings[key] = value; imported.append(key)
    if ctx.options.get('wallpapers') and facts['wallpapers'] and 'wallpaperFolder' not in settings:
        settings['wallpaperFolder'] = facts['wallpapers'][0]['path']; imported.append('wallpaper library')
    write_private_json(settings_path, settings)
    if backup:
        backup.changed(settings_path); backup.stage('migrate')
    op.detail = ('Imported ' + ', '.join(imported)) if imported else 'Nothing new to import; existing CEDAR settings kept'
    if notes:
        raise ops.Warn(op.detail + '. ' + ' '.join(notes))


def migrate_verify(ctx, op):
    return (ctx.config_dir() / 'hypr/settings.json').is_file() if ctx.options.get('migrate') else True


# --------------------------------------------------------------- session
def session_run(ctx, op):
    if not ctx.options.get('session'):
        raise ops.Skip('Not selected: start CEDAR later with cedar try, then cedar keep')
    env = ctx.facts['environment']
    if not env.get('adapter'):
        raise ops.Skip('Session handoff for ' + env['name'] + ' is not validated yet; open CEDAR with cedar preview')
    d = ctx.module('distribution')
    backend = d.session_backend('omarchy' if env['adapter'] == 'omarchy' else 'auto')
    installed = ctx.installed or d.installed()
    ctx.progress(op, 0.1, 'Starting CEDAR beside your applications')
    try:
        with ctx.capture(op):
            if backend.__name__ == 'portable_session':
                backend.trial(installed, approved=True, cedar_launcher=bool(ctx.options.get('launcher')), trailwatch=bool(ctx.options.get('trailwatch')))
            else:
                backend.trial(installed, approved=True, trailwatch=bool(ctx.options.get('trailwatch')))
        ctx.progress(op, 0.5, 'CEDAR is on screen; checking its health')
        with ctx.capture(op):
            backend.keep()
        ctx.progress(op, 0.8, 'Enabling CEDAR at login')
        with ctx.capture(op):
            backend.keep(login=True, approved=True)
    except (RuntimeError, OSError, ValueError) as error:
        # The adapters refuse rather than guess (an unidentified shell, a
        # locker, an unknown idle daemon). CEDAR is installed either way;
        # the person starts it when the desktop is ready for it.
        if ctx.log: ctx.log.warn('session handoff refused: ' + str(error), op.id)
        session_rollback(ctx, op)
        raise ops.Warn('CEDAR is installed but was not started in this session: ' + str(error).rstrip('.') + '. Start it when ready with "cedar try", then "cedar keep".') from error
    backup = reopen_backup(ctx)
    record = backend.read_record() or {}
    if backup:
        for process in record.get('paused', []) or []:
            backup.record('servicesDisabled', process.get('unit') or Path(process.get('exe', '')).name)
        backup.note('Session handoff through the ' + env['adapter'] + ' adapter; cedar restore returns the previous desktop.')
        backup.stage('session')
    op.detail = 'CEDAR is running and will start at login'


def session_verify(ctx, op):
    if not ctx.options.get('session') or not ctx.facts['environment'].get('adapter'):
        return True
    d = ctx.module('distribution')
    backend = d.session_backend()
    record = backend.read_record() or {}
    return record.get('stage') == 'kept' and bool(record.get('login'))


def session_rollback(ctx, op):
    d = ctx.module('distribution')
    backend = d.session_backend()
    record = backend.read_record() or {}
    if record.get('stage') not in (None, 'restored'):
        with ctx.capture(op):
            backend.request_restore()


# ---------------------------------------------------------------- verify
def verify_run(ctx, op):
    d = ctx.module('distribution')
    checks = []
    root = d.installed()
    checks.append('release files verified')
    ctx.progress(op, 0.3, 'Release files verified')
    if ctx.host.which('qs'):
        d.validate_imports(root)
        checks.append('shell imports load')
    ctx.progress(op, 0.6, 'Shell imports load')
    if not (ctx.host.home / '.local/bin/cedar').is_file():
        raise RuntimeError('The cedar command is missing after installation')
    checks.append('cedar command present')
    entry = ctx.host.data_home() / 'applications/cedar-shield.desktop'
    checks.append('Shield launcher entry present' if entry.is_file() else 'Shield launcher entry missing (optional)')
    session = 'not started'
    if ctx.options.get('session') and ctx.facts['environment'].get('adapter'):
        record = d.session_backend().read_record() or {}
        session = record.get('stage', 'unknown')
        checks.append('session ' + session)
    record = {'format': 1, 'version': ctx.facts['cedarVersion'], 'installedAt': time.time(), 'runId': ctx.runner.run_id if ctx.runner else '',
              'backup': ctx.runner.backup if ctx.runner else '', 'installer': 'cedar-install ' + ctx.facts['installerVersion'],
              'environment': ctx.facts['environment']['id'], 'session': session, 'log': str(ctx.log.path) if ctx.log else ''}
    write_private_json(ctx.config_dir() / 'installation.json', record)
    backup = reopen_backup(ctx)
    if backup:
        backup.changed(ctx.config_dir() / 'installation.json'); backup.stage('verify')
    op.detail = '; '.join(checks)
    ctx.progress(op, 1.0, op.detail)


def build(ctx, state_path, log, emit, run_id, options):
    plan_ops = {row['id']: row for row in ctx.plan['operations']}
    def disabled(reason):
        def run(ctx_, op): raise ops.Skip(reason)
        return run
    table = {
        'backup': (backup_run, backup_verify, None),
        'dependencies': (dependencies_run, dependencies_verify, None),
        'runtime': (runtime_run, runtime_verify, None),
        'shell': (shell_run, None, None),
        'migrate': (migrate_run, migrate_verify, None),
        'session': (session_run, session_verify, session_rollback),
        'verify': (verify_run, None, None),
    }
    operations = []
    for op_id, (run, verify, rollback) in table.items():
        row = plan_ops[op_id]
        if not row.get('enabled', True):
            run, verify, rollback = disabled('Not part of this run'), None, None
        operations.append(ops.Operation(op_id, row['title'], row['description'], run, verify, rollback, optional=row.get('optional', False), group=row.get('group', '')))
    runner = ops.Runner(operations, state_path, log, emit, version=ctx.facts['cedarVersion'], options=options, run_id=run_id)
    ctx.runner = runner
    return runner
