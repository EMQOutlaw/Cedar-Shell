"""Approved plans and verified recovery over the existing session transactions."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import time
from .support import ROOT, d
from . import detection, keybindings
from .adapters import SessionAdapter, active_adapter
from installer.engine.host import Host

ACTION = 'compatibility-migration'
TERMINAL = ('restored',)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def history():
    base = d.paths()['state'] / 'transactions'
    result = []
    if not base.exists():
        return result
    for path in sorted(base.glob('*/journal.json'), reverse=True):
        if path.is_symlink():
            continue
        try:
            record = d.read_json(path)
            if record.get('action') == ACTION:
                result.append({'id': path.parent.name, 'path': str(path), 'stage': record['stage'],
                               'created': record['created'], 'adapter': record['plan']['adapter'],
                               'error': record.get('error', ''), 'planDigest': record['plan']['digest']})
        except (KeyError, ValueError, OSError):
            continue
    return result


def pending():
    return next((r for r in history() if r['stage'] not in TERMINAL), None)


@contextlib.contextmanager
def operation_lock():
    # Separate coordinator lock: session supervisors continue using distribution.lock.
    base = d.paths()['state']
    d.private_directory(base)
    path = base / 'compatibility.lock'
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise d.Refused('Another compatibility operation is in progress') from None
        yield
    finally:
        os.close(fd)


class Engine:
    def __init__(self, root=ROOT, host=None, adapter_factory=SessionAdapter, scan=None):
        self.root = Path(root).resolve()
        self.host = host or Host()
        self.adapter_factory = adapter_factory
        self.scan = scan or (lambda: detection.scan(self.host))

    def preview(self, options=None):
        options = {'bindings': False, 'login': False, 'trailwatch': False, **(options or {})}
        evidence = self.scan()
        blocked, actions, files = [], [], []
        compositor = evidence['compositor']
        if not compositor['active'] or not compositor['session']:
            blocked.append('A live, identified Hyprland session is required')
        if compositor['locked']:
            blocked.append('Unlock the desktop normally before migration')
        if compositor['ambiguous']:
            blocked.append('Multiple Hyprland main configurations require review')
        if options['login'] and options['trailwatch']:
            blocked.append('Review locker handoff separately from persistent login; startup changes after authentication need a fresh preview')
        blocked.extend(evidence['probeErrors'])
        missing = [r['command'] for r in evidence['dependencies'] if not r['available']]
        if missing:
            blocked.append('Missing dependencies: ' + ', '.join(missing) + '; use cedar dependencies to review installation')
        if not evidence['writable']:
            blocked.append('Recovery state directory is not writable')
        if not evidence['disk'] or evidence['disk']['free'] < 32 * 1024 ** 2:
            blocked.append('At least 32 MiB of free recovery space is required')
        if any(r['session'] != 'other' for r in evidence['unknown']):
            blocked.append('An unknown Quickshell configuration needs an ownership review')
        active = [m for m in evidence['matches'] if m['states']['active'] and m['id'] != 'plain-hyprland']
        unsafe = [m for m in active if not m['adapter']]
        if unsafe:
            blocked.append('Automatic handoff is not reviewed for: ' + ', '.join(m['name'] for m in unsafe))
        adapter_name = 'omarchy' if any(m['id'] == 'omarchy' for m in active) else 'portable'
        # Ambiguous hybrid providers are resolved by actual adapter inspection, never by distro priority.
        if any(m['id'] == 'omarchy' for m in active) and any(m['id'] != 'omarchy' for m in active):
            blocked.append('Multiple active shells include Omarchy; explicit provider ownership review required')
        snapshot, operations = {}, []
        current = pending()
        if current:
            blocked.append('Existing migration ' + current['id'] + ' (' + current['stage'] + '); use status or rollback first')
        if not blocked:
            try:
                snapshot, operations = self.adapter_factory(adapter_name).inspect(self.root, options)
                if snapshot.get('adapter') == 'hyprland' and not evidence['startup']['complete']:
                    blocked.append('Standalone startup graph is incomplete; review wrappers/includes before takeover')
                commands = [r['command'] for r in evidence['startup']['commands']]
                repeated = sorted({c for c in commands if commands.count(c) > 1})
                if repeated:
                    blocked.append('Duplicate startup declarations require resolution: ' + '; '.join(repeated))
                for process in snapshot.get('paused', []):
                    if process.get('unit') and not {'active', 'state'} <= evidence['units'].get(process['unit'], {}).keys():
                        blocked.append('Cannot record complete service restoration state: ' + process['unit'])

            except (d.Refused, OSError, ValueError) as error:
                blocked.append(str(error))
        if options['bindings']:
            # Two independent journals must never edit the same main file in one operation.
            if options['login'] or options['trailwatch']:
                blocked.append('Apply bindings separately from login/locker handoff; their journals must not overlap')
            if not evidence['startup']['complete']:
                blocked.append('Bindings require a fully resolved startup graph; computed Lua stays manual')
            if not compositor['config']:
                blocked.append('No binding include target identified')
        shortcuts = keybindings.plan(evidence['bindings'], options.get('assignments'))
        if options['bindings'] and not blocked:
            try:
                # Package ownership is inspected, never changed.
                main = compositor['config']
                for package_tool, argv in [('pacman', ['pacman', '-Qo', main]), ('dpkg-query', ['dpkg-query', '-S', main]), ('rpm', ['rpm', '-qf', main])]:
                    if self.host.which(package_tool) and self.host.run(argv)[0] == 0:
                        raise d.Refused('Main config is package-owned; use its supported user include instead')
                files = keybindings.files(main, self.host.config_home() / 'cedar/compatibility', shortcuts, self.root)
            except (d.Refused, OSError, ValueError) as error:
                blocked.append(str(error))
        for file in files:
            actions.append({'classification': 'Add' if file['before']['type'] == 'absent' else 'Modify',
                            'target': file['path'], 'description': 'Separate conflict-preserving CEDAR bindings',
                            'before': file['before'], 'after': file['content']})
        for op in operations:
            actions.append({'classification': 'Disable' if op['kind'] == 'pause-provider' else 'Modify' if op['kind'] in ('patch-provider-settings', 'login-file', 'conditional-lock-settings') or op.get('before', {}).get('type') == 'file' else 'Add',
                            'target': op.get('target', ''), 'description': op['kind'], 'details': op})
        for role in ('monitors', 'input', 'applications', 'user data', 'unrelated keybindings', 'packages', 'original shell installation'):
            actions.append({'classification': 'Preserve', 'target': role, 'description': 'No ownership transfer'})
        if options['login']:
            actions.append({'classification': 'Add', 'target': 'adapter-owned login hook', 'description': 'Enable CEDAR on subsequent logins; restored by the session journal'})
        for reason in blocked:
            actions.append({'classification': 'Requires manual intervention', 'target': 'preflight', 'description': reason})
        # Stable mutation evidence only: free memory/disk, timestamps and widget readings
        # are diagnostics, not reasons to invalidate a previously approved plan.
        relevant = {k: evidence[k] for k in ('compositor', 'startup', 'units', 'bindings', 'activeShells', 'unknown')}
        plan = {'format': 1, 'source': str(self.root), 'adapter': adapter_name, 'options': options,
                'blocked': blocked, 'actions': actions, 'files': files, 'shortcuts': shortcuts,
                'snapshot': snapshot, 'sourceIdentity': fingerprint({str(rel): d.digest(path) for path, rel in d.files(self.root)}), 'evidenceDigest': fingerprint(relevant),
                'startup': evidence['startup'], 'servicesBefore': {p['unit']: evidence['units'].get(p['unit'], {}) for p in snapshot.get('paused', []) if p.get('unit')},
                'servicesObserved': evidence['units'],
                'compatibility': [{'id': m['id'], 'level': m['compatibility']} for m in evidence['matches']]}
        plan['digest'] = fingerprint(plan)
        return {'plan': plan, 'detection': evidence}

    def _load(self, entry):
        path = Path(entry['path'])
        tx = d.Transaction.__new__(d.Transaction)
        tx.path, tx.directory, tx.record = path, path.parent, d.read_json(path)
        return tx

    def apply(self, approved_digest, options=None):
        with operation_lock():
            existing = pending()
            if existing and existing['stage'] == 'commit' and existing['planDigest'] == approved_digest:
                return {'id': existing['id'], 'alreadyApplied': True, 'health': self.adapter_factory(existing['adapter']).validate()}
            report = self.preview(options)
            plan = report['plan']
            if plan['blocked']:
                raise d.Refused('; '.join(plan['blocked']))
            if approved_digest != plan['digest']:
                raise d.Refused('The approved plan is stale. Review a fresh preview; nothing changed')
            adapter = self.adapter_factory(plan['adapter'])
            if adapter.record() and adapter.record().get('stage') != 'restored':
                raise d.Refused('A CEDAR session already exists; preserve it or restore it first')
            tx = d.Transaction(ACTION)
            tx.record.update(plan=plan, sessionBefore=adapter.record(), sessionId=None)
            tx.save()
            # Complete every backup before the first mutation.
            for file in plan['files']:
                if not d.same(d.info(Path(file['path'])), file['before']):
                    raise d.Refused('Configuration changed since preview')
                tx.backup(Path(file['path']))
            tx.stage('back-up')
            try:
                for file, entry in zip(plan['files'], tx.record['files']):
                    tx.apply_file(entry, file['content'].encode(), file['mode'])
                if plan['files']:
                    self._reload()
                tx.stage('activating')  # Durable before spawning any external effect.
                adapter.activate(self.root, plan['options'], tx.directory.name, plan['snapshot'])
                row = adapter.record()
                tx.record['sessionId'] = row['id']; tx.save()
                tx.stage('validating')
                health = adapter.validate()
                adapter.keep()
                if plan['options']['login']:
                    import adoption_plan
                    login_change = next((a['details'] for a in plan['actions'] if a.get('details', {}).get('kind') == 'login-file'), None)
                    expected = adoption_plan.fingerprint({'path': login_change['target'], 'before': login_change['before'], 'content': login_change['desired']}) if login_change else None
                    adapter.keep(login=True, expected_login_digest=expected)
                tx.record['health'] = adapter.validate()
                tx.commit()
                return {'id': tx.directory.name, 'health': health, 'stage': 'commit'}
            except (Exception, KeyboardInterrupt) as error:
                tx.record['error'] = str(error); tx.save()
                try:
                    self._rollback(tx, adapter)
                except Exception as recovery:
                    tx.record['recoveryError'] = str(recovery); tx.stage('recovery-required')
                    raise d.Refused(str(error) + '; recovery pending: ' + str(recovery) + '; journal: ' + str(tx.path)) from error
                raise d.Refused(str(error) + '; previous desktop restoration verified') from error

    def _reload(self):
        code, _, error = self.host.run(['hyprctl', 'reload'])
        check, out, detail = self.host.run(['hyprctl', 'configerrors'])
        if code or check or out.strip() not in ('', 'ok', '[]'):
            raise d.Refused('Hyprland configuration validation failed: ' + (error or detail or out))

    def _rollback(self, tx, adapter):
        d.check_restore_journal(tx.path)
        row = adapter.record()
        if row and row.get('stage') != 'restored':
            before = tx.record.get('sessionBefore') or {}
            identity = tx.record.get('sessionId')
            if row.get('compatibilityMigration') != tx.directory.name or row.get('id') == before.get('id') or identity and row.get('id') != identity:
                raise d.Refused('Active session identity differs from this migration; leave it running')
            if str(Path(row['root']).resolve()) != tx.record['plan']['source']:
                raise d.Refused('Interrupted migration cannot claim a different CEDAR release')
        adapter.check_restore()
        tx.stage('restoring')
        adapter.restore()
        if row and row.get('compatibilityMigration') == tx.directory.name:
            deadline = time.monotonic() + 12
            while True:
                try:
                    adapter.verify_restored(tx.record['plan']['snapshot'])
                    break
                except d.Refused:
                    if time.monotonic() >= deadline: raise
                    time.sleep(.2)
        d.restore_journal(tx.path)
        # Never accept the journal stage as proof of service restoration.
        restored = self.host.user_units()
        for unit, original in tx.record['plan']['servicesBefore'].items():
            now = restored.get(unit, {})
            for key in ('active', 'state'):
                if original.get(key) != now.get(key):
                    tx.record = d.read_json(tx.path)
                    tx.stage('recovery-required')
                    raise d.Refused('Service restoration differs: ' + unit + ' (' + key + ')')
        if tx.record['files']:
            self._reload()
        # File restoration may have succeeded while the above checks did not.
        tx.record = d.read_json(tx.path)
        tx.record['restorationVerified'] = True
        tx.stage('restored')

    def rollback(self, identity=None):
        with operation_lock():
            entry = next((r for r in history() if r['id'] == identity), None) if identity else pending()
            if not entry:
                raise d.Refused('No recorded compatibility migration to restore')
            tx = self._load(entry)
            if tx.record['stage'] == 'restored':
                return {'id': entry['id'], 'alreadyRestored': True}
            try:
                self._rollback(tx, self.adapter_factory(entry['adapter']))
            except Exception as error:
                tx.record = d.read_json(tx.path)
                tx.record['recoveryError'] = str(error); tx.stage('recovery-required')
                raise
            return {'id': entry['id'], 'restorationVerified': True}

    def status(self):
        adapter = active_adapter()
        row = adapter.record() if adapter else None
        health = {'healthy': False, 'reason': 'No managed CEDAR session'}
        if adapter:
            try:
                health = adapter.validate()
            except (d.Refused, ValueError, OSError) as error:
                health['reason'] = str(error)
        return {'stage': row.get('stage') if row else 'not active', 'login': bool(row and row.get('login')),
                'locker': row.get('locker') if row else None, 'health': health, 'history': history(),
                'adapter': adapter.name if adapter else None}
