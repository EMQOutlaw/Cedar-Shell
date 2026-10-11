"""Delegate effects to CEDAR's existing reviewed, supervised adapters."""
import json
import os
from pathlib import Path
import shlex
import sys
import time
from .support import ROOT, d


class SessionAdapter:
    def __init__(self, name):
        if name == 'omarchy':
            import omarchy_session as backend
        elif name == 'portable':
            import portable_session as backend
        else:
            raise d.Refused('No reviewed activation adapter for this environment')
        self.name, self.backend = name, backend

    def record(self):
        return self.backend.read_record()

    def inspect(self, root, options):
        if Path(root).resolve() != d.installed().resolve():
            raise d.Refused('Install this candidate before activation; checkout previews do not deploy source')
        if self.name == 'portable':
            row, plan = self.backend.inspect_plan(root, False, options.get('trailwatch', False))
            operations = plan['operations']
            for operation in operations:
                if operation['kind'] == 'patch-provider-settings':
                    operation['desired'] = row['settingsAfter']
            if row.get('controls'):
                controls = row['controls']
                for key, content in (('file', controls['content']), ('loginFile', ''), ('main', controls['mainAfter'])):
                    path = controls[key]
                    operations.append({'kind': 'control-file', 'target': path, 'before': controls['before'][path],
                                       'desired': content, 'mode': controls['before'][path].get('mode', 0o600)})
            if row.get('trailwatch'):
                operations.append({'kind': 'conditional-lock-settings', 'target': row['providerSettings'],
                                   'desired': row['trailwatch']['settings'], 'condition': 'After successful local PAM and secure-unlock test'})
            if options.get('login'):
                path, content = self.backend.startup_entry(row)
                operations.append({'kind': 'login-file', 'target': str(path), 'before': d.info(path),
                                   'desired': content.decode(), 'mode': d.info(path).get('mode', 0o600)})
            return row, operations
        row = self.backend.inspect(root)
        desired = self.backend.transformed(row['original'], row.get('omacale'))
        desired['bar']['cedarShellPath'] = str(root / 'shell.qml')
        operations = [{'kind': 'patch-provider-settings', 'target': row['config'],
                      'before': row['original'], 'desired': desired,
                      'inverse': 'Restore journaled Omarchy settings'},
                     {'kind': 'start-cedar', 'target': str(root), 'desired': 'Healthy full desktop; resident authentication preserved'}]
        if options.get('trailwatch'):
            lock_id = (row.get('omacale') or {}).get('lockId') or 'omarchy.lock'
            lock_plan = {**row, 'configAfter': desired, 'trailwatch': {'lockId': lock_id}}
            operations.append({'kind': 'conditional-lock-settings', 'target': row['config'],
                               'desired': self.backend.handoff_config(lock_plan), 'condition': 'After successful local PAM and secure-unlock test'})
        config = Path(row['config']).parent
        for name in ('manifest.json', 'Bridge.qml'):
            path = config / 'plugins/cedar.integration' / name
            operations.append({'kind': 'integration-file', 'target': str(path), 'before': d.info(path),
                               'desired': (root / 'integrations/omarchy' / name).read_text(), 'mode': 0o600})
        helper = d.paths()['data'] / 'recovery/omarchy_session.py'
        hook = '#!/bin/bash\n# CEDAR-owned trial recovery and confirmed login startup\nexec ' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(helper)) + ' login\n'
        path = config / 'hooks/post-boot.d/95-cedar-session'
        operations.append({'kind': 'integration-file', 'target': str(path), 'before': d.info(path), 'desired': hook, 'mode': 0o700})
        if row.get('omacale'):
            from omarchy_providers import GUARD
            for name in ('manifest.json', 'Service.qml'):
                path = config / 'plugins' / GUARD / name
                operations.append({'kind': 'integration-file', 'target': str(path), 'before': d.info(path),
                                   'desired': (root / 'integrations/omarchy/omacale-guard' / name).read_text(), 'mode': 0o600})
        return row, operations

    def activate(self, root, options, identity, snapshot):
        previous = os.environ.get('CEDAR_COMPATIBILITY_MIGRATION')
        os.environ['CEDAR_COMPATIBILITY_MIGRATION'] = identity
        try:
            arguments = {'approved': True, 'trailwatch': options.get('trailwatch', False)}
            if self.name == 'portable':
                import adoption_plan
                arguments['expected_plan'] = adoption_plan.build_plan(snapshot, {'launcher': False, 'trailwatch': options.get('trailwatch', False)})['digest']
            else:
                arguments['expected_snapshot'] = snapshot
            self.backend.trial(root, **arguments)
        finally:
            if previous is None:
                os.environ.pop('CEDAR_COMPATIBILITY_MIGRATION', None)
            else:
                os.environ['CEDAR_COMPATIBILITY_MIGRATION'] = previous

    def verify_restored(self, snapshot):
        import portable_providers as providers
        if self.name == 'omarchy':
            shell = snapshot['omarchyShell']
            if self.backend.ipc(shell, 'shell', 'ping').strip() not in ('pong', 'true', 'ok'):
                raise d.Refused('Original Omarchy IPC did not recover')
            # File journal restores the bar selection; verify its live config too.
            plugins = json.loads(self.backend.ipc(shell, 'shell', 'listPlugins'))
            original = snapshot.get('original')
            if original is None:
                journal = Path(snapshot['journal'])
                entry = d.read_json(journal)['files'][0]
                original = d.read_json(journal.parent / entry['backup'])
            bar = original['bar']['id']
            if not any(p.get('id') == bar and p.get('enabled') for p in plugins):
                raise d.Refused('Original Omarchy bar did not become enabled')
            self.backend.ipc(shell, 'lock', 'status')
        elif snapshot['adapter'].startswith('noctalia-'):
            state = providers.noctalia_state(snapshot)
            if state.get('barVisible') != snapshot.get('barWasVisible'):
                raise d.Refused('Original Noctalia bar visibility did not recover')
        else:
            running = providers.processes()
            for original in snapshot.get('paused', []):
                if not any(p['exe'] == original['exe'] and p['argv'] == original['argv'] for p in running):
                    raise d.Refused('Original provider did not recover: ' + original['exe'])
            notifications = [p for p in snapshot.get('paused', []) if Path(p['exe']).name in ('mako', 'dunst')]
            if notifications and providers.notification_owner() not in [p['pid'] for p in running if Path(p['exe']).name in ('mako', 'dunst')]:
                raise d.Refused('Original notification service did not recover')
        if self.backend.cedar_rows(self.record() or {'root': str(ROOT)}):
            raise d.Refused('CEDAR is still running after restoration')

    def keep(self, login=False, expected_login_digest=None):
        arguments = {'login': login, 'approved': True}
        if self.name == 'portable':
            arguments['expected_login_digest'] = expected_login_digest
        self.backend.keep(**arguments)

    def validate(self):
        row = self.record()
        if not row or row.get('stage') not in ('trial', 'kept'):
            raise d.Refused('CEDAR has no ready supervised session')
        process = self.backend.healthy(row)
        if self.name == 'portable':
            state = json.loads(self.backend.ipc(row, 'shell', 'sessionInfo'))
        else:
            state = self.backend.cedar_info(row)
        if state.get('stage') != 3 or state.get('screenCount', 0) < 1:
            raise d.Refused('CEDAR full desktop surfaces are not ready')
        errors = d.command(['hyprctl', 'configerrors']).strip()
        if errors not in ('', 'ok', '[]'):
            raise d.Refused('Hyprland reports configuration errors: ' + errors[:400])
        layers = json.loads(d.command(['hyprctl', '-j', 'layers']))
        def surfaces(value):
            if isinstance(value, dict):
                if value.get('namespace') == 'cedar-bar':
                    yield value
                for child in value.values():
                    yield from surfaces(child)
            elif isinstance(value, list):
                for child in value:
                    yield from surfaces(child)
        bars = list(surfaces(layers))
        if len(bars) < state['screenCount'] or any('pid' in bar and bar['pid'] != process['pid'] for bar in bars):
            raise d.Refused('CEDAR bar surfaces are not mapped on every output or belong to another instance')
        interfaces = d.command(['qs', '-p', str(Path(row['root']) / 'shell.qml'), 'ipc', 'show'])
        import re
        if not all(re.search(r'\b' + target + r'\b', interfaces) for target in ('shell', 'menu', 'control', 'station')):
            raise d.Refused('Required CEDAR control interfaces did not register')
        return {'healthy': True, 'desktopStage': state['stage'], 'screens': state['screenCount'],
                'checks': ['adapter health', 'session generation', 'shell IPC', 'notification ownership', 'Hyprland configuration', 'mapped bars', 'control interfaces']}

    def check_restore(self):
        row = self.record()
        if not row or row.get('stage') == 'restored':
            return
        self.backend.unlocked(row)
        for key in ('journal', 'loginJournal'):
            if row.get(key):
                d.check_restore_journal(Path(row[key]))

    def restore(self):
        row = self.record()
        if row and row.get('stage') != 'restored':
            self.backend.request_restore()
        row = self.record()
        if row and row.get('stage') != 'restored':
            raise d.Refused('Underlying restoration has not completed; recovery remains pending')

    def restart(self):
        row = self.record()
        if not row or row.get('stage') != 'kept':
            raise d.Refused('Restart requires a kept CEDAR session')
        with self.backend.guard():
            row = self.record()
            self.backend.unlocked(row)
            row.update(stage='starting', restartKept=True, readyDeadline=time.time() + 35)
            self.backend.save(row)
            if self.name == 'portable':
                self.backend.ipc(row, 'shell', 'stop')
            else:
                self.backend.cedar_ipc(row, 'shell', 'stop')
            deadline = time.monotonic() + 8
            while self.backend.cedar_rows(row) and time.monotonic() < deadline:
                time.sleep(.1)
            if self.backend.cedar_rows(row):
                raise d.Refused('CEDAR did not close gracefully; no process was killed')
        # Existing supervisors own restart and lock protection, not this CLI.
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            try:
                return self.validate()
            except (d.Refused, ValueError):
                time.sleep(.25)
        raise d.Refused('CEDAR did not recover; inspect migration history before retrying')


def active_adapter():
    found = []
    for name in ('omarchy', 'portable'):
        adapter = SessionAdapter(name)
        row = adapter.record()
        if row and row.get('stage') not in ('restored', None):
            found.append(adapter)
    if len(found) > 1:
        raise d.Refused('Multiple CEDAR session records need reconciliation')
    return found[0] if found else None
