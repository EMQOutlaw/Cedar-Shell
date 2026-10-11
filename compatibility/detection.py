"""Read-only, multi-match evidence. No profile label is execution authority."""
import json
from pathlib import Path
import re
from .support import ROOT, d
from installer.engine.host import Host
from installer.engine.facts import hyprland_main, quickshell_instances
import startup_graph

STATES = ('installed', 'configured', 'active', 'autostarted', 'managed')


def profiles():
    result = []
    for path in sorted((ROOT / 'compatibility/profiles').glob('*.json')):
        p = json.loads(path.read_text())
        if p.get('schema') != 1 or p.get('adapter') not in (None, 'omarchy', 'portable'):
            raise ValueError('Invalid compatibility profile: ' + path.name)
        result.append(p)
    return result


def _json_probe(host, argv, kind):
    code, out, error = host.run(argv, timeout=8)
    try:
        value = json.loads(out)
        if code == 0 and isinstance(value, kind):
            return value, None
    except ValueError:
        pass
    return kind(), 'Unavailable probe: ' + ' '.join(argv)


def _same_session(host, process):
    env = process.get('environment')
    if env is None:
        raw = host.read_bytes('/proc/' + str(process['pid']) + '/environ', 131072)
        if raw is None:
            return None
        env = dict(v.decode(errors='replace').split('=', 1) for v in raw.split(b'\0') if b'=' in v)
    signature = host.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    if not signature or not env.get('HYPRLAND_INSTANCE_SIGNATURE'):
        return None
    return env['HYPRLAND_INSTANCE_SIGNATURE'] == signature


def scan(host=None, facts=None):
    host = host or Host()
    facts = facts or {}
    processes = facts.get('processes') if 'processes' in facts else host.processes()
    qs = facts.get('quickshellInstances') if 'quickshellInstances' in facts else quickshell_instances(host)
    packages = facts.get('packages') if 'packages' in facts else host.packages()
    units = facts.get('userUnits') if 'userUnits' in facts else host.user_units()
    main, ambiguous = hyprland_main(host, processes)
    graph = startup_graph.inspect(main, host.config_home(), host.home) if main else {
        'files': [], 'commands': [], 'complete': False, 'unresolved': ['No unambiguous Hyprland configuration']}
    monitors, error = _json_probe(host, ['hyprctl', '-j', 'monitors'], list)
    bindings, bind_error = _json_probe(host, ['hyprctl', '-j', 'binds'], list)
    errors = [x for x in (error, bind_error) if x]
    substitutions = dict(config=str(host.config_home()), data=str(host.data_home()), home=str(host.home))
    matches, claimed = [], set()
    for profile in profiles():
        evidence = []
        states = {name: False for name in STATES}
        def add(state, kind, source, detail, confidence='high'):
            states[state] = True
            evidence.append(dict(state=state, kind=kind, source=str(source), detail=detail, confidence=confidence))
        sig = profile['signatures']
        for template in sig['paths']:
            path = Path(template.format(**substitutions))
            if host.exists(path) or host.is_symlink(path):
                add('installed', 'path', path, 'Signature exists', 'medium')
                if str(path).startswith(str(host.config_home()) + '/'):
                    add('configured', 'path', path, 'Configuration exists; not evidence of startup', 'medium')
                if host.is_symlink(path) or '/nix/store/' in str(path.resolve()):
                    add('managed', 'symlink', path, 'External configuration ownership; do not follow for writes')
        for name in sig['packages']:
            if name in packages:
                add('installed', 'package', name, str(packages[name]))
        for name in sig['commands']:
            executable = host.which(name)
            if executable:
                add('installed', 'executable', executable, name, 'medium')
        for row in graph['commands']:
            # Evidence only. Never execute parsed configuration.
            if any(re.search(r'(?<![\w-])' + re.escape(token) + r'(?![\w-])', row['command']) for token in sig['startup']):
                add('configured', 'startup', row['path'], row['command'])
                add('autostarted', 'startup', row['path'], 'line ' + str(row['line']) + ': ' + row['command'])
        for file in graph['files']:
            text = host.read(file['path']) or ''
            # Lua is not evaluated: an opaque reference is only configured evidence.
            if any(token in text for token in sig['startup']):
                add('configured', 'config-reference', file['path'], 'Literal reference; dynamic startup requires review', 'medium')
                if file['ownership'] != 'ordinary':
                    add('managed', 'config-owner', file['path'], file['ownership'])
        for unit in sig['units']:
            if unit in units:
                add('installed', 'unit', unit, 'User unit exists')
                add('managed', 'unit', unit, 'Supervised by systemd; preserve enabled/active state')
                if units[unit].get('state') in ('enabled', 'enabled-runtime', 'linked', 'linked-runtime'):
                    add('autostarted', 'unit', unit, units[unit]['state'])
        for process in processes:
            instances = [r for r in qs if r.get('pid') == process['pid']]
            named = Path(process['exe']).name in sig['processes']
            located = any(any(token in str(r.get('config_path', '')) for token in sig['quickshell']) for r in instances)
            if not (named or located):
                continue
            if located:
                claimed.add(process['pid'])
            same = _same_session(host, process)
            source = next((r.get('config_path') for r in instances), process['exe'])
            add('installed', 'process', source, 'Process ' + str(process['pid']))
            if same is True:
                add('active', 'process', source, 'PID ' + str(process['pid']) + ' in this Hyprland session')
            else:
                evidence.append(dict(state='active', kind='process', source=str(source),
                                     detail='Other session' if same is False else 'Session association unverified', confidence='unknown'))
        if any(states.values()):
            matches.append(dict(id=profile['id'], name=profile['name'], compatibility=profile['compatibility'],
                                adapter=profile['adapter'], states=states, evidence=evidence,
                                confidence='high' if states['active'] else 'medium', limitations=profile['limitations']))
    unknown = []
    for row in qs:
        source = Path(str(row.get('config_path', '')))
        if row.get('pid') in claimed or source.name != 'shell.qml':
            continue
        # CEDAR itself is reported separately, never identified from an arbitrary path substring.
        if source.resolve() == (ROOT / 'shell.qml').resolve() or (source.parent / 'data/compatibility.json').is_file() and (source.parent / 'scripts/distribution.py').is_file():
            continue
        proc = next((p for p in processes if p['pid'] == row.get('pid')), None)
        same = _same_session(host, proc) if proc else None
        unknown.append({'kind': 'quickshell', 'source': str(source), 'pid': row.get('pid'),
                        'session': 'current' if same is True else 'other' if same is False else 'unknown',
                        'reason': 'Unknown role; never terminate this configuration automatically'})
    return dict(format=1, matches=matches, unknown=unknown,
                activeShells=[m['id'] for m in matches if m['states']['active'] and m['id'] != 'plain-hyprland'],
                compositor={'name': 'Hyprland' if monitors else 'unknown', 'active': bool(monitors),
                            'session': host.environ.get('HYPRLAND_INSTANCE_SIGNATURE', ''),
                            'config': str(main) if main else None, 'ambiguous': ambiguous,
                            'locked': any('LOCK' in (m.get('solitaryBlockedBy') or []) for m in monitors)},
                startup=graph, units=units, bindings=bindings, probeErrors=errors,
                dependencies=[{'command': n, 'available': bool(host.which(n))} for n in ('qs', 'hyprctl', 'systemctl', 'systemd-run', 'busctl')],
                disk=host.disk_free(host.state_home()), writable=host.writable(host.state_home()))
