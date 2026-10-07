"""The installer engine behind both front ends, and its JSON-lines server.

Engine drives scan → plan → install/resume/restore/uninstall/repair and
emits events; the terminal flow calls it directly and the CEDAR Installer
window talks to it over stdin/stdout, one JSON object per line:

    → {"cmd": "scan"}                          ← {"event": "facts", "data": {...}}
    → {"cmd": "plan", "options": {...}}        ← {"event": "plan", "data": {...}}
    → {"cmd": "install", "options": {...}, "digest": "..."}
                                               ← {"event": "operation", "data": {...}} …
                                               ← {"event": "log", "data": {"operation": "...", "line": "..."}}
                                               ← {"event": "password", "data": {"method": "sudo", "text": "..."}}
                                               ← {"event": "done", "data": {...}} | {"event": "error", "data": {...}}
    → {"cmd": "resume"} | {"cmd": "start-over"} | {"cmd": "restore"} | {"cmd": "session"} | {"cmd": "quit"}

The window never parses terminal output to guess progress; it renders the
operation records the engine sends.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import threading
import time
import traceback

from . import facts as facts_module
from . import log as log_module
from . import operations as ops
from . import plan as plan_module
from . import steps
from .backup import Backup
from .host import Host


def private_tree(root, children=()):
    """~/.local/state/cedar and the installer's folders under it, private to the user.

    The existing engine refuses a recovery directory that is not 0700 and
    user-owned, and Path.mkdir(parents=True) would create the parent with
    the default mode. Existing directories keep their permissions."""
    root = Path(root)
    for path in (root, *[root / child for child in children]):
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.mkdir(mode=0o700)
            os.chmod(path, 0o700)


class Engine:
    def __init__(self, source, host=None, emit=None):
        self.source = Path(source).resolve()
        self.host = host or Host()
        self.emit = emit or (lambda event, data: None)
        self.facts = None
        self.plan = None
        self.state_dir = self.host.state_home() / 'cedar/installer'
        self.state_path = self.state_dir / 'state.json'
        private_tree(self.host.state_home() / 'cedar', ('installer', 'installer/logs', 'installations'))
        self.log = None
        self.runner = None
        self.busy = False

    # -- discovery -------------------------------------------------------
    def scan(self):
        self.facts = facts_module.scan(self.host, self.source, self.state_dir)
        self.emit('facts', self.public_facts())
        return self.facts

    def public_facts(self):
        facts = {k: v for k, v in self.facts.items() if k not in ('processes', 'packages', 'userUnits', 'quickshellInstances')}
        facts['processCount'] = len(self.facts['processes'])
        facts['packageCount'] = len(self.facts['packages'])
        facts['technical'] = facts_module.technical(self.facts)
        return facts

    def build_plan(self, options=None):
        if self.facts is None:
            self.scan()
        plan_module.set_check_host(self.host)
        self.plan = plan_module.build(self.facts, options)
        self.emit('plan', self.plan)
        return self.plan

    # -- logging -----------------------------------------------------------
    def open_log(self, run_id=None):
        if self.log is None:
            self.log = log_module.RunLog(self.state_dir / 'logs', home=self.host.home, run_id=run_id).open()
            self.log.info('CEDAR installer ' + (self.facts or {}).get('installerVersion', '') + ' started')
        return self.log

    # -- installation ----------------------------------------------------
    def install(self, options=None, digest=None, resume=False):
        if self.busy:
            raise RuntimeError('An operation is already running')
        self.busy = True
        try:
            state = ops.load_state(self.state_path) if resume else None
            if resume and not state:
                raise RuntimeError('There is no interrupted installation to resume')
            if resume:
                options = state.get('options') or options
            if self.facts is None:
                self.scan()
            plan = self.build_plan(options)
            if digest is not None and plan['digest'] != digest:
                raise RuntimeError('The reviewed plan no longer matches this machine. Review it again before installing.')
            if plan['blocked']:
                raise RuntimeError('The plan needs attention before installation: ' + '; '.join(a['title'] for a in plan['attention'] if a['severity'] == 'stop'))
            log = self.open_log(state.get('runId') if state else None)
            ctx = steps.Context(self.host, self.source, self.facts, plan, plan['options'], log, self.emit)
            runner = steps.build(ctx, self.state_path, log, self.emit, log.run_id, plan['options'])
            if state:
                runner.restore_from(state)
                steps.reopen_backup(ctx)
            self.runner = runner
            self.emit('operations', [op.to_dict() for op in runner.operations])
            try:
                summary = runner.run(ctx, resume=bool(state))
            except ops.Failed as failure:
                data = self.failure(failure, runner)
                self.emit('error', data)
                return {'ok': False, **data}
            result = {'ok': True, **summary, 'backup': runner.backup, 'log': str(log.path), 'imports': plan['imports'],
                      'session': ctx.facts['environment'].get('adapter', '') if plan['options'].get('session') else '',
                      'sessionState': self.session_state(), 'version': self.facts['cedarVersion']}
            log.info('finished: ' + json.dumps(summary))
            self.emit('done', result)
            return result
        finally:
            self.busy = False

    def failure(self, failure, runner):
        op = failure.operation
        changed = [o.title for o in runner.operations if o.state in ops.FINAL and o.id != 'backup']
        resumable = op.id not in ('backup',)
        return {'operation': op.id, 'title': op.title, 'message': str(failure), 'changedBefore': changed, 'rolledBack': failure.rolled_back,
                'resumable': resumable, 'backup': runner.backup, 'log': str(self.log.path) if self.log else '',
                'preserved': 'Your original configuration is in the backup. No existing desktop files were deleted.'}

    def resume(self):
        return self.install(resume=True)

    def start_over(self):
        if self.state_path.is_file():
            self.state_path.unlink()
        return self.install()

    def retry(self):
        state = ops.load_state(self.state_path)
        if not state:
            raise RuntimeError('Nothing to retry')
        return self.install(resume=True)

    def session_now(self):
        """The finish screen's Start CEDAR: run the session handoff after an install that skipped it."""
        state = ops.load_state(self.state_path)
        options = dict((state or {}).get('options') or (self.plan or {}).get('options') or {})
        options['session'] = True
        if state:
            for row in state.get('operations', []):
                if row.get('id') in ('session', 'verify'):
                    row['state'] = ops.PENDING
            state['options'] = options; state['finished'] = False
            self.state_path.write_text(json.dumps(state, indent=2))
        return self.install(options=options, resume=bool(state))

    def session_state(self):
        try:
            sys.path.insert(0, str(self.source / 'scripts'))
            import distribution as d
            record = d.session_backend().read_record() or {}
            return record.get('stage', 'not active')
        except Exception:  # noqa: BLE001
            return 'unknown'

    # -- recovery --------------------------------------------------------
    def restore(self, dry_run=False):
        """Restore Previous System: leave a CEDAR session, put copied files back, undo the program entry points."""
        report = {'session': 'not active', 'files': [], 'conflicts': [], 'program': 'kept'}
        sys.path.insert(0, str(self.source / 'scripts'))
        import distribution as d
        try:
            if d.session_active() and not dry_run:
                d.session_backend().request_restore(); report['session'] = 'restored'
        except Exception as error:  # noqa: BLE001
            report['session'] = 'not restored: ' + str(error)
        latest = Backup.latest(self.host.state_home() / 'cedar/installations')
        if latest:
            backup = Backup.load(latest)
            backup.home = self.host.home
            outcome = backup.restore(dry_run=dry_run)
            report['files'], report['conflicts'], report['backup'] = outcome['restored'], outcome['conflicts'], str(latest)
            for unit in backup.manifest.get('servicesDisabled', []):
                if unit.endswith('.service') and not dry_run:
                    self.host.run(['systemctl', '--user', 'start', unit], timeout=20)
        state = ops.load_state(self.state_path)
        if state and any(o.get('id') == 'runtime' and o.get('state') == ops.COMPLETE for o in state.get('operations', [])) and not dry_run:
            try:
                d.recover_latest('install'); report['program'] = 'program entry points restored'
            except Exception as error:  # noqa: BLE001
                report['program'] = 'not restored: ' + str(error)
        if self.state_path.is_file() and not dry_run:
            self.state_path.rename(self.state_path.with_name('state-restored-' + time.strftime('%Y%m%dT%H%M%S') + '.json'))
        self.emit('restored', report)
        return report

    def uninstall(self, dry_run=False):
        """Undo CEDAR-owned changes: session, program entry points, copied configuration; keep packages and your data."""
        report = {'session': 'not active', 'program': 'kept', 'files': [], 'conflicts': [], 'kept': ['packages', 'preferences', 'wallpapers', 'backups', 'release files']}
        sys.path.insert(0, str(self.source / 'scripts'))
        import distribution as d
        if d.session_active():
            if dry_run:
                report['session'] = 'would be restored'
            else:
                d.session_backend().request_restore(); report['session'] = 'restored'
        if not dry_run:
            try:
                d.uninstall(approved=True); report['program'] = 'program entry points restored'
            except Exception as error:  # noqa: BLE001
                report['program'] = str(error)
        else:
            report['program'] = 'would restore the cedar command, current-release link and launcher entries from their journals'
        latest = Backup.latest(self.host.state_home() / 'cedar/installations')
        if latest:
            backup = Backup.load(latest); backup.home = self.host.home
            outcome = backup.restore(dry_run=dry_run)
            report['files'], report['conflicts'], report['backup'] = outcome['restored'], outcome['conflicts'], str(latest)
        marker = self.host.config_home() / 'cedar/installation.json'
        if marker.is_file() and not dry_run:
            marker.unlink()
        if self.state_path.is_file() and not dry_run:
            self.state_path.unlink()
        self.emit('uninstalled', report)
        return report

    def repair(self):
        """Verify the installed copy; reinstall the release when its files do not match; re-check the shell."""
        sys.path.insert(0, str(self.source / 'scripts'))
        import distribution as d
        report = {'release': 'ok', 'shell': 'not checked', 'command': 'ok'}
        try:
            root = d.installed()
        except Exception as error:  # noqa: BLE001
            report['release'] = 'reinstalled: ' + str(error)
            d.install(self.source, approved=True); root = d.installed()
        if not (self.host.home / '.local/bin/cedar').is_file():
            d.install(self.source, approved=True); report['command'] = 'reinstalled'
        if self.host.which('qs'):
            try:
                d.validate_imports(root); report['shell'] = 'imports load'
            except Exception as error:  # noqa: BLE001
                report['shell'] = 'failed: ' + str(error)
        self.emit('repaired', report)
        return report

    def last_log(self):
        return log_module.latest(self.state_dir / 'logs')

    def previous(self):
        return ops.describe_state(ops.load_state(self.state_path))


# ------------------------------------------------------------------ server
def serve(source):
    """stdin → commands, stdout → events; long operations run on a worker thread.

    Events go to the console stream captured here, never to whatever
    sys.stdout is at the moment: a step that redirects stdout into the log
    (the runtime step wraps the existing engine's print output) must not
    swallow the events, or feed them back into the log as output lines.
    """
    lock = threading.Lock()
    console = sys.stdout
    def emit(event, data):
        with lock:
            console.write(json.dumps({'event': event, 'data': data}, ensure_ascii=False) + '\n'); console.flush()
    engine = Engine(source, emit=emit)
    worker = None

    def background(fn, *args, **kwargs):
        nonlocal worker
        def run():
            try:
                fn(*args, **kwargs)
            except Exception as error:  # noqa: BLE001
                emit('error', {'operation': '', 'title': 'Installer', 'message': str(error), 'changedBefore': [], 'rolledBack': False, 'resumable': False,
                               'backup': engine.runner.backup if engine.runner else '', 'log': str(engine.log.path) if engine.log else '', 'trace': traceback.format_exc()[-2000:]})
        if worker and worker.is_alive():
            emit('error', {'operation': '', 'title': 'Installer', 'message': 'Still working on the previous request', 'changedBefore': [], 'rolledBack': False, 'resumable': False, 'backup': '', 'log': ''})
            return
        worker = threading.Thread(target=run, daemon=True); worker.start()

    emit('ready', {'source': str(engine.source), 'version': (engine.source / 'VERSION').read_text().strip() if (engine.source / 'VERSION').is_file() else ''})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            emit('error', {'message': 'Malformed request', 'operation': '', 'title': 'Installer', 'changedBefore': [], 'rolledBack': False, 'resumable': False, 'backup': '', 'log': ''}); continue
        cmd = request.get('cmd')
        try:
            if cmd == 'scan': background(engine.scan)
            elif cmd == 'plan': background(engine.build_plan, request.get('options'))
            elif cmd == 'install': background(engine.install, request.get('options'), request.get('digest'))
            elif cmd == 'resume': background(engine.resume)
            elif cmd == 'start-over': background(engine.start_over)
            elif cmd == 'retry': background(engine.retry)
            elif cmd == 'restore': background(engine.restore)
            elif cmd == 'session': background(engine.session_now)
            elif cmd == 'log': emit('logpath', {'path': str(engine.log.path) if engine.log else str(engine.last_log() or '')})
            elif cmd == 'quit': break
            else: emit('error', {'message': 'Unknown command ' + str(cmd), 'operation': '', 'title': 'Installer', 'changedBefore': [], 'rolledBack': False, 'resumable': False, 'backup': '', 'log': ''})
        except Exception as error:  # noqa: BLE001
            emit('error', {'message': str(error), 'operation': '', 'title': 'Installer', 'changedBefore': [], 'rolledBack': False, 'resumable': False, 'backup': '', 'log': ''})
    if engine.log:
        engine.log.close()
