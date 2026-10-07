"""One scan, one fact model. Every later decision derives from this.

scan() asks the Host once for everything the installer, the plan, the
migration providers and the UI need, and returns a JSON-serializable
dictionary. Nothing downstream re-detects; the engine updates a fact only
when one of its own operations changed the relevant state.
"""
import json
from pathlib import Path
import re

from . import operations
from ..migration import intent, providers

GPU_VENDORS = {'0x10de': 'NVIDIA', '0x1002': 'AMD', '0x8086': 'Intel', '0x1a03': 'ASPEED', '0x15ad': 'VMware', '0x1af4': 'virtio'}
GPU_MODULES = (('nvidia', 'nvidia'), ('nouveau', 'nouveau'), ('amdgpu', 'amdgpu'), ('radeon', 'radeon'), ('xe', 'xe'), ('i915', 'i915'), ('virtio_gpu', 'virtio'))
POLKIT_AGENTS = {'polkit-gnome-authentication-agent-1', 'polkit-kde-authentication-agent-1', 'polkit-kde-authentication-agent', 'lxqt-policykit-agent',
                 'hyprpolkitagent', 'xfce-polkit', 'polkit-mate-authentication-agent-1', 'pantheon-agent-polkit', 'ts-polkitagent', 'polkit-dumb-agent'}
SECURE_BOOT = '/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c'
COMPOSITORS = ('hyprland', 'sway', 'niri', 'river', 'kwin_wayland', 'gnome-shell', 'wayfire', 'labwc')


def read_json(host, path):
    text = host.read(path)
    if text is None:
        return None
    try:
        return json.loads(text)
    except ValueError:
        return None


def version_of(host, argv, pattern=r'(\d+\.\d+(?:\.\d+)?)'):
    code, out, err = host.run(argv, timeout=5)
    if code != 0:
        return ''
    match = re.search(pattern, out + err)
    return match.group(1) if match else (out.strip().splitlines() or [''])[0][:40]


def quickshell_instances(host):
    if not host.which('qs'):
        return []
    code, out, _ = host.run(['qs', 'list', '--all', '-j'], timeout=5)
    if code != 0 or out.startswith('No running instances'):
        return []
    try:
        value = json.loads(out)
    except ValueError:
        return []
    return [row for row in value if isinstance(row, dict)] if isinstance(value, list) else []


def gpu(host):
    vendor, driver = '', ''
    for card in host.listdir('/sys/class/drm'):
        if re.fullmatch(r'card\d+', card):
            raw = (host.read('/sys/class/drm/' + card + '/device/vendor') or '').strip().lower()
            if raw in GPU_VENDORS:
                vendor = GPU_VENDORS[raw]; break
    modules = set(host.listdir('/sys/module'))
    for module, name in GPU_MODULES:
        if module in modules:
            driver = name; break
    return {'vendor': vendor or 'Unknown', 'driver': driver or 'unknown'}


def secure_boot(host):
    raw = host.read_bytes(SECURE_BOOT, 16)
    if not raw:
        return 'unavailable'
    return 'enabled' if raw[-1] == 1 else 'disabled'


def display_manager(host):
    code, out, _ = host.run(['systemctl', 'show', 'display-manager.service', '-p', 'Id', '--value'], timeout=5)
    name = out.strip().replace('.service', '') if code == 0 else ''
    return name if name and name != 'display-manager' else 'none detected'


def network_manager(host):
    for unit, name in (('NetworkManager', 'NetworkManager'), ('iwd', 'iwd'), ('systemd-networkd', 'systemd-networkd'), ('connman', 'ConnMan')):
        code, out, _ = host.run(['systemctl', 'is-active', unit], timeout=5)
        if code == 0 and out.strip() == 'active':
            return name
    return 'none detected'


def connectivity(host):
    if host.which('nmcli'):
        code, out, _ = host.run(['nmcli', '-t', '-f', 'CONNECTIVITY', 'general'], timeout=5)
        if code == 0:
            return out.strip() in ('full', 'limited')
    return None


def compositor(host, processes):
    names = {Path(p['exe']).name.lower() for p in processes}
    running = next((c for c in COMPOSITORS if c in names), '')
    session = host.environ.get('XDG_SESSION_TYPE', '') or ('wayland' if host.environ.get('WAYLAND_DISPLAY') else '')
    return {'name': running or ('hyprland' if host.which('hyprctl') else ''), 'running': bool(running), 'session': session,
            'display': bool(host.environ.get('WAYLAND_DISPLAY') or host.environ.get('DISPLAY'))}


def hyprland_main(host, processes):
    config = host.config_home() / 'hypr'
    for process in processes:
        if Path(process['exe']).name.lower() == 'hyprland':
            argv = process['argv']
            for index, arg in enumerate(argv):
                if arg in ('--config', '-c') and index + 1 < len(argv):
                    return Path(argv[index + 1]), False
                if arg.startswith('--config='):
                    return Path(arg.split('=', 1)[1]), False
    candidates = [config / name for name in ('hyprland.lua', 'hyprland.conf') if host.is_file(config / name)]
    if not candidates:
        return None, False
    return candidates[0], len(candidates) > 1


def dependency_report(host, source):
    manifest = read_json(host, Path(source) / 'data/dependencies.json') or {}
    rows, missing, recommended = [], [], []
    for row in manifest.get('commands', []):
        if row.get('scope') in ('development', 'omarchy-adapter'):
            continue
        present = bool(host.which(row['command']))
        rows.append({'id': row['command'], 'present': present, 'required': row['status'] == 'required', 'package': row.get('archPackage'), 'feature': row.get('feature', '')})
        if not present and row['status'] in ('required', 'feature-required') and row.get('autoInstall', True) and row.get('archPackage'):
            missing.append(row['archPackage'])
    for row in manifest.get('pythonModules', []):
        code, _, _ = host.run(['python3', '-c', row.get('probe', 'import ' + row['name'])], timeout=10)
        present = code == 0
        rows.append({'id': row['name'], 'present': present, 'required': row['status'] == 'required', 'package': row.get('archPackage'), 'feature': row.get('feature', '')})
        if not present and row['status'] in ('required', 'feature-required') and row.get('archPackage'):
            missing.append(row['archPackage'])
    if not host.which('qs'):
        for row in manifest.get('modules', []) + manifest.get('imageFormats', []):
            package = row.get('archPackage') or row.get('package')
            if package:
                missing.append(package)
    for row in manifest.get('fonts', []):
        present = False
        if host.which('fc-match'):
            code, out, _ = host.run(['fc-match', '--format=%{family}', row['family']], timeout=5)
            present = code == 0 and row['family'].lower() in out.lower()
        rows.append({'id': row['family'], 'present': present, 'required': False, 'package': row.get('archPackage'), 'feature': 'Display font; fallback ' + row.get('fallback', '')})
        if not present and row.get('archPackage'):
            recommended.append(row['archPackage'])
    return {'rows': rows, 'missing': sorted(set(missing)), 'recommendedMissing': sorted(set(recommended)),
            'backends': (manifest.get('packageManagement') or {}).get('backends', [])}


def support(distro, architecture, backends):
    for backend in backends:
        if distro['id'] in backend.get('distributions', {}) and architecture in backend.get('architectures', []):
            return {'status': 'supported', 'backend': backend['id'], 'label': backend['distributions'][distro['id']],
                    'note': 'Automatic package setup is ' + backend.get('status', 'reviewed').lower() + ' on ' + backend['distributions'][distro['id']] + '.'}
    if 'arch' in distro['like'] or distro['id'] == 'arch':
        return {'status': 'experimental', 'backend': 'pacman', 'label': distro['name'],
                'note': 'Arch-based but not individually reviewed; CEDAR installs when its dependencies are present and can use pacman only after you confirm.'}
    return {'status': 'unsupported', 'backend': '', 'label': distro['name'],
            'note': 'No automatic package setup for this distribution. CEDAR installs when its dependencies are already present.'}


def cedar_agent(host, instances):
    """A running CEDAR shell registers its own polkit agent; ask it rather than guessing from process names."""
    for row in instances:
        source = str(row.get('config_path', ''))
        if '/cedar' not in source and 'cedar-shell' not in source:
            continue
        code, out, _ = host.run(['qs', 'ipc', '-p', source, 'call', 'permission', 'status'], timeout=5)
        if code == 0:
            try:
                return bool(json.loads(out).get('registered'))
            except (ValueError, AttributeError):
                continue
    return False


def existing_cedar(host):
    data = host.data_home() / 'cedar'
    state = host.state_home() / 'cedar'
    current = data / 'current'
    result = {'installed': host.is_symlink(current) or host.is_dir(current), 'version': '', 'command': False, 'session': 'not active', 'releases': []}
    if result['installed']:
        result['version'] = (host.read(current / 'VERSION') or '').strip()
    result['releases'] = host.listdir(data / 'releases')
    launcher = host.read(host.home / '.local/bin/cedar')
    result['command'] = bool(launcher and 'CEDAR distribution launcher' in launcher)
    for name in ('portable-session.json', 'session.json'):
        row = read_json(host, state / name)
        if isinstance(row, dict) and row.get('stage') not in (None, 'restored'):
            result['session'] = row.get('stage', 'unknown')
    result['config'] = host.is_dir(host.config_home() / 'cedar')
    return result


def scan(host, source, state_dir=None):
    source = Path(source)
    release = host.os_release()
    processes = host.processes()
    facts = {'format': 1}
    facts['installerVersion'] = (host.read(source / 'VERSION') or 'unknown').strip()
    facts['cedarVersion'] = facts['installerVersion']
    facts['distro'] = {'id': release.get('ID', 'unknown'), 'name': release.get('PRETTY_NAME') or release.get('NAME', 'Unknown Linux'),
                       'like': (release.get('ID_LIKE') or '').split(), 'version': release.get('VERSION_ID', '')}
    facts['architecture'] = host.machine()
    facts['kernel'] = host.kernel()
    facts['python'] = list(host.python_version())
    facts['packageManager'] = next((name for name in ('pacman', 'apt-get', 'dnf', 'zypper') if host.which(name)), '')
    # The installer's own window is a Quickshell program; it is not a desktop.
    own = ('installer.qml', 'installer-preview.qml', 'preview.qml', 'auth-test.qml')
    processes = [p for p in processes if not (Path(p['exe']).name in ('qs', 'quickshell') and any(Path(a).name in own for a in p['argv']))]
    facts['processes'] = processes
    facts['userUnits'] = host.user_units()
    facts['packages'] = host.packages()
    facts['quickshellInstances'] = [row for row in quickshell_instances(host) if Path(str(row.get('config_path', ''))).name not in own]
    facts['compositor'] = compositor(host, processes)
    facts['hyprlandInstalled'] = bool(host.which('hyprctl') or host.which('Hyprland'))
    facts['hyprlandVersion'] = version_of(host, ['hyprctl', 'version']) if host.which('hyprctl') else ''
    facts['quickshellInstalled'] = bool(host.which('qs'))
    facts['quickshellVersion'] = version_of(host, ['qs', '--version']) if host.which('qs') else ''
    facts['gpu'] = gpu(host)
    facts['displayManager'] = display_manager(host)
    facts['networkManager'] = network_manager(host)
    facts['online'] = connectivity(host)
    facts['secureBoot'] = secure_boot(host)
    facts['home'] = str(host.home)
    facts['configPaths'] = {'hypr': str(host.config_home() / 'hypr'), 'cedar': str(host.config_home() / 'cedar'), 'quickshell': str(host.config_home() / 'quickshell'),
                            'data': str(host.data_home() / 'cedar'), 'state': str(host.state_home() / 'cedar')}
    main, ambiguous = hyprland_main(host, processes)
    facts['hyprland'] = intent.inspect_hyprland(host, main)
    facts['hyprland']['ambiguous'] = ambiguous
    facts['apps'] = intent.preferred_apps(host)
    facts['wallpapers'] = intent.wallpaper_library(host)
    facts['existingCedar'] = existing_cedar(host)
    facts['polkitAgent'] = any(Path(p['exe']).name in POLKIT_AGENTS for p in processes) or cedar_agent(host, facts['quickshellInstances'])
    facts['tty'] = host.has_tty()
    facts['pkexec'] = bool(host.which('pkexec'))
    facts['sudo'] = bool(host.which('sudo'))
    facts['root'] = host.uid() == 0
    facts['disk'] = host.disk_free(host.data_home())
    facts['dataWritable'] = host.writable(host.data_home())
    facts['defaultQuickshellProfile'] = host.is_file(host.config_home() / 'quickshell/shell.qml')
    facts['locked'] = False
    if facts['compositor']['name'] == 'hyprland' and facts['compositor']['running'] and host.which('hyprctl'):
        try:
            code, out, _ = host.run(['hyprctl', '-j', 'monitors'], timeout=5)
            monitors = json.loads(out) if code == 0 else []
            facts['locked'] = any('LOCK' in (m.get('solitaryBlockedBy') or []) for m in monitors if isinstance(m, dict))
        except ValueError:
            pass
    facts['dependencies'] = dependency_report(host, source)
    facts['support'] = support(facts['distro'], facts['architecture'], facts['dependencies']['backends'])
    detected = providers.detect(facts, host)
    provider = providers.by_id(detected['chosen'])
    chosen = next((r for r in detected['results'] if r['id'] == detected['chosen']), {'evidence': []})
    facts['environment'] = {**detected, **provider.describe(facts), 'evidence': chosen.get('evidence', [])}
    facts['conflicts'] = provider.conflicts(facts)
    facts['previousInstall'] = operations.describe_state(operations.load_state(Path(state_dir) / 'state.json')) if state_dir else None
    return facts


def technical(facts):
    """The Advanced view: one label per subsystem, nothing a beginner has to read."""
    hypr = facts['hyprland']
    rows = [('Distribution', facts['distro']['name']), ('Architecture', facts['architecture']), ('Kernel', facts['kernel']),
            ('Package manager', facts['packageManager'] or 'none detected'), ('Support', facts['support']['status'] + ' · ' + facts['support']['note']),
            ('GPU', facts['gpu']['vendor'] + ' (' + facts['gpu']['driver'] + ')'),
            ('Compositor', (facts['compositor']['name'] or 'none') + (' · running' if facts['compositor']['running'] else ' · not running') + (' ' + facts['hyprlandVersion'] if facts['hyprlandVersion'] else '')),
            ('Quickshell', facts['quickshellVersion'] or 'not installed'),
            ('Existing environment', facts['environment']['name'] + (' · ' + ', '.join(facts['environment']['evidence']) if facts['environment'].get('evidence') else '')),
            ('Display manager', facts['displayManager']), ('Networking', facts['networkManager']),
            ('Secure Boot', facts['secureBoot']), ('Config source', hypr['config'] or 'none found'),
            ('Monitors', ', '.join(m['name'] + ' ' + m['mode'] for m in hypr['monitors']) or 'none recorded'),
            ('Keyboard', ' '.join(k + '=' + v for k, v in hypr['keyboard'].items()) or 'compositor default'),
            ('Existing CEDAR', (facts['existingCedar']['version'] or 'none') + (' · session ' + facts['existingCedar']['session'] if facts['existingCedar']['installed'] else '')),
            ('Data directory', facts['configPaths']['data']), ('Free space', str(round((facts['disk'] or {}).get('free', 0) / 1024 ** 3, 1)) + ' GB')]
    return [{'label': label, 'value': str(value)} for label, value in rows]
