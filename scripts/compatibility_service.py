#!/usr/bin/env python3
"""Field Station bridge. Read-only reports here; changes survive QML shutdown."""
import json
from pathlib import Path
import re
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from compatibility.support import ROOT, d
from compatibility.engine import Engine, history
from compatibility.cli import main as cli
from desktop_runtime import terminal_argv


def handle(request):
    engine = Engine(ROOT)
    action = request.get('action', 'snapshot')
    if action == 'snapshot':
        return {'status': engine.status(), 'detection': engine.scan()}
    if action == 'preview':
        options = request.get('options', {})
        if not isinstance(options, dict) or set(options) - {'bindings', 'login', 'trailwatch', 'assignments'}:
            raise d.Refused('Invalid preview options')
        return engine.preview(options)
    if action == 'terminal':
        operation = request.get('operation')
        args = []
        if operation == 'migrate':
            digest = request.get('digest', '')
            if not re.fullmatch('[a-f0-9]{64}', digest):
                raise d.Refused('Review the migration preview first')
            options = request.get('options', {})
            if engine.preview(options)['plan']['digest'] != digest:
                raise d.Refused('The preview is stale; refresh before approval')
            args = ['migrate', '--approve-plan', digest]
            for flag in ('bindings', 'login', 'trailwatch'):
                if options.get(flag): args.append('--' + flag)
            if options.get('assignments'):
                # Pass data as a single argv element; never evaluate shell text.
                args.extend(['--assignments-json', json.dumps(options['assignments'])])
        elif operation == 'rollback':
            identity = request.get('migration')
            if identity and identity not in [r['id'] for r in history()]:
                raise d.Refused('Unknown migration ID')
            args = ['rollback'] + (['--migration', identity] if identity else [])
        elif operation == 'restart':
            args = ['restart']
        else:
            raise d.Refused('Unknown desktop operation')
        argv = terminal_argv([sys.executable, str(Path(__file__).resolve()), '--terminal', *args])
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {'message': 'Opened the desktop operation in a terminal. It remains available if CEDAR closes. Refresh when finished.'}
    raise d.Refused('Unknown compatibility request')


if __name__ == '__main__':
    if sys.argv[1:2] == ['--terminal']:
        try:
            cli(sys.argv[2:], root=ROOT)
        except (d.Refused, OSError, ValueError) as error:
            print('CEDAR: ' + str(error))
        if sys.stdin.isatty():
            input('\nPress Enter to close this window.')
    else:
        try:
            request = json.loads(sys.stdin.readline(65537))
            if not isinstance(request, dict): raise ValueError('Expected a JSON request')
            print(json.dumps({'ok': True, 'data': handle(request)}))
        except (d.Refused, OSError, ValueError, subprocess.SubprocessError) as error:
            print(json.dumps({'ok': False, 'error': str(error)}))
