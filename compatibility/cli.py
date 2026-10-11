"""Shared CLI; approval is tied to a current plan, never to a detection label."""
import argparse
import json
from pathlib import Path
import sys
from .support import ROOT, d
from .engine import Engine, history, pending, operation_lock
from .adapters import active_adapter


def emit(value):
    print(json.dumps(value, indent=2, ensure_ascii=False))


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description='CEDAR compatibility: inspect, preview, migrate and restore the shell only.')
    parser.add_argument('action', choices=['compatibility', 'migrate', 'start', 'stop', 'restart', 'status', 'doctor', 'history', 'rollback', 'restore'])
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--json', action='store_true', help='Structured read-only output (the default for diagnostics)')
    parser.add_argument('--approve-plan', help='Digest from the exact reviewed migration preview')
    parser.add_argument('--login', action='store_true', help='Include persistent startup in the approved migration')
    parser.add_argument('--trailwatch', action='store_true', help='Include the existing interactive lock handoff tests')
    parser.add_argument('--bindings', action='store_true', help='Generate only unoccupied/reassigned defaults; keep existing bindings')
    parser.add_argument('--assignments', type=Path, help='JSON mapping of action to key combination or null to skip')
    parser.add_argument('--assignments-json', help=argparse.SUPPRESS)
    parser.add_argument('--migration', help='Restore this migration ID rather than the pending one')
    args = parser.parse_args(argv)
    options = {'login': args.login, 'trailwatch': args.trailwatch, 'bindings': args.bindings}
    if args.assignments and args.assignments_json:
        raise d.Refused('Choose one assignments input')
    if args.assignments or args.assignments_json:
        options['assignments'] = json.loads(args.assignments.read_text() if args.assignments else args.assignments_json)
        if not isinstance(options['assignments'], dict):
            raise d.Refused('Assignments must be a JSON object')
    engine = Engine(root)
    if args.action == 'history':
        emit({'migrations': history()}); return
    if args.action == 'status':
        emit(engine.status()); return
    if args.action in ('doctor', 'compatibility'):
        result = engine.status()
        result['detection'] = engine.scan()
        if args.action == 'compatibility':
            result['preview'] = engine.preview(options)['plan']
        emit(result); return
    if args.action == 'restart':
        if args.dry_run:
            emit({'action': 'Restart only the managed CEDAR instance through its supervisor'}); return
        with operation_lock():
            adapter = active_adapter()
            if not adapter: raise d.Refused('No managed CEDAR session to restart; run cedar migrate --dry-run')
            emit(adapter.restart())
        return
    if args.action in ('stop', 'rollback', 'restore'):
        entry = pending()
        if args.dry_run:
            emit({'action': 'Restore original shell from its journals', 'migration': entry,
                  'legacySession': engine.status() if not entry else None}); return
        if entry or args.migration:
            emit(engine.rollback(args.migration)); return
        # Existing installs still have their own guarded restoration interface.
        adapter = active_adapter()
        if not adapter:
            emit({'stage': 'not active', 'changed': False}); return
        with operation_lock():
            adapter.check_restore()
            before = adapter.record()
            adapter.restore()
            adapter.verify_restored(before)
        emit({'stage': 'restored', 'restorationVerified': True}); return
    if args.action == 'start':
        adapter = active_adapter()
        if adapter:
            row = adapter.record()
            if row.get('stage') != 'kept':
                raise d.Refused('Existing session is not committed; use status or rollback')
            if not args.dry_run:
                with operation_lock():
                    if row.get('login'):
                        adapter.backend.login()
                    emit(adapter.validate())
                return
    # A fresh start is a migration, with exactly the same approval and recovery.
    report = engine.preview(options)
    emit(report)
    if args.dry_run:
        return
    if report['plan']['blocked']:
        raise d.Refused('Migration blocked. Resolve the listed manual-intervention actions first')
    approval = args.approve_plan
    if not approval:
        if not sys.stdin.isatty():
            raise d.Refused('Review --dry-run, then pass --approve-plan DIGEST; nothing changed')
        reply = input('Apply this exact plan? Type migrate to approve: ')
        if reply != 'migrate':
            raise d.Refused('Canceled; nothing changed')
        approval = report['plan']['digest']
    emit(engine.apply(approval, options))
