"""From facts to a concrete plan: what will be checked, migrated and installed.

The same builder serves the graphical installer, the terminal flow and
--dry-run, so a dry run shows exactly what a real run would do. The plan
also carries the attention list (states that stop the installer until the
person decides) and a digest, so an approved plan that no longer matches
the machine is refused instead of applied.
"""
import hashlib
import json

from ..migration import providers
from ..providers import packages as package_providers
from ..providers import privilege

OPERATIONS = ('backup', 'leave', 'dependencies', 'runtime', 'shell', 'migrate', 'session', 'verify')
MIN_FREE = 600 * 1024 * 1024


def default_options(facts):
    env = facts['environment']
    # An active CEDAR session is handed back by the leave step, then re-entered.
    can_handoff = bool(env.get('adapter')) and facts['compositor']['name'] == 'hyprland' and facts['compositor']['running']
    # CEDAR's keybinds (Caelestia layout) by default where no shell binding set exists; environments with their own keep theirs unless asked.
    keybinds = env.get('id') in ('plain-hyprland', 'waybar', 'generic-quickshell') and facts['compositor']['name'] == 'hyprland'
    return {'session': can_handoff, 'launcher': False, 'trailwatch': False, 'fonts': False, 'wallpapers': bool(facts['wallpapers']), 'migrate': True, 'keybinds': keybinds}


def attention(facts, options):
    """Risky states the installer refuses to walk past silently."""
    rows = []
    def add(id, title, detail, severity='stop', learn=''):
        rows.append({'id': id, 'title': title, 'detail': detail, 'severity': severity, 'learn': learn})
    if facts['root']:
        add('root', 'Running as root', 'CEDAR installs into your own home directory. Run the installer as your ordinary user.')
    if tuple(facts['python'][:2]) < (3, 11):
        add('python', 'Python 3.11 or newer is needed', 'The installer and CEDAR’s helpers need Python 3.11+. Update Python with your package manager first.')
    if facts['architecture'] not in ('x86_64',):
        add('arch', 'Unsupported architecture: ' + facts['architecture'], 'CEDAR is built and tested on x86_64. Other architectures are not published yet.')
    if facts['compositor']['name'] and facts['compositor']['name'] != 'hyprland':
        add('compositor', 'Another compositor is running: ' + facts['compositor']['name'], 'CEDAR is a Hyprland desktop. It can be installed now and started from a Hyprland session later; no session handoff will be attempted here.', 'warn')
    if not facts['hyprlandInstalled']:
        add('hyprland', 'Hyprland is not installed', 'CEDAR runs on Hyprland. Install and start Hyprland first; the installer does not replace your compositor or login manager.')
    if facts['existingCedar'].get('commandOwner') == 'other':
        add('command', 'Another program owns the cedar command', '~/.local/bin/cedar exists and is not CEDAR’s, so the installer will not replace it. Move it aside (mv ~/.local/bin/cedar ~/.local/bin/cedar.other), then check again.')
    if facts['locked']:
        add('locked', 'The session is locked', 'Unlock the desktop normally, then continue. The installer never interrupts a locker.')
    # The Omarchy handoff pauses the stock Omarchy shell and refuses when it is not running, or
    # when another CEDAR (a checkout selected as the Omarchy theme) already has the display.
    if facts['environment'].get('id') == 'omarchy' and options.get('session') and facts['existingCedar']['session'] == 'not active':
        paths = [str(row.get('config_path', '')) for row in facts.get('quickshellInstances', [])]
        omarchy_shells = [p for p in paths if p.endswith('/omarchy/shell/shell.qml')]
        other_cedar = [p for p in paths if p.endswith('shell.qml') and ('cedar' in p.lower() or 'foxfire' in p.lower())]
        if other_cedar:
            add('session', 'Another CEDAR is already running as the desktop', 'A CEDAR shell is running from ' + other_cedar[0] + ', so the session step cannot hand this release the display; CEDAR installs and the session step is skipped with a note. To run the installed release instead, select another Omarchy theme first (that returns the stock shell), then run cedar try and cedar keep.', 'warn')
        elif len(omarchy_shells) != 1:
            add('session', 'The Omarchy shell is not running', 'The session step pauses Omarchy’s own shell and starts CEDAR in its place; with ' + ('no' if not omarchy_shells else str(len(omarchy_shells))) + ' Omarchy shell running it is refused and CEDAR is installed without starting. Start the Omarchy shell (omarchy-restart-shell), or install now and run cedar try later.', 'warn')
    if facts['defaultQuickshellProfile']:
        add('qsdefault', 'A default Quickshell profile masks named shells', '~/.config/quickshell/shell.qml would hide CEDAR’s named profile. Move it aside before installing; the installer will not replace it.')
    disk = facts.get('disk') or {}
    if disk and disk.get('free', 0) < MIN_FREE:
        add('disk', 'Not enough free space', 'CEDAR needs about 600 MB free under ' + disk.get('path', '~') + ' for its versioned copy and recovery checkpoints.')
    if not facts['dataWritable']:
        add('readonly', 'The data directory is read-only', facts['configPaths']['data'] + ' cannot be written. Check the filesystem and permissions.')
    missing = facts['dependencies']['missing']
    if missing:
        if facts['support']['status'] == 'unsupported':
            add('unsupported', 'Dependencies are missing on an unsupported distribution',
                'CEDAR has no automatic package setup for ' + facts['distro']['name'] + '. Install these with your package manager, then run the installer again: ' + ', '.join(missing) + '.')
        elif facts['support']['status'] == 'experimental':
            add('experimental', 'Experimental package setup on ' + facts['distro']['name'],
                'This Arch-based distribution is not individually reviewed. pacman will be used with your configured repositories after you confirm; or install the packages yourself first: ' + ', '.join(missing) + '.', 'warn')
        if facts['online'] is False:
            add('offline', 'No network connection', 'Packages have to be downloaded: ' + ', '.join(missing) + '. Connect to a network, or install them yourself first.')
        if facts['packageManager'] == 'pacman' and facts['support']['status'] != 'unsupported' and not privilege.method_name(facts):
            add('privilege', 'No way to ask for your password', privilege.describe('') + ' Packages to install: ' + ', '.join(missing) + '.')
    if facts['gpu']['vendor'] == 'NVIDIA' and facts['secureBoot'] == 'enabled' and facts['gpu']['driver'] not in ('nvidia', 'nouveau'):
        add('nvidia', 'NVIDIA with Secure Boot and no loaded driver', 'Secure Boot can keep an unsigned NVIDIA kernel module from loading. CEDAR does not install drivers; a desktop without a loaded GPU driver may not start after a reboot.', 'warn',
            'https://wiki.archlinux.org/title/NVIDIA#Secure_Boot')
    if facts['hyprland'].get('unresolved'):
        add('includes', 'Some Hyprland includes could not be read', 'Monitor and keyboard settings were read from the files that were readable; these were not: ' + ', '.join(facts['hyprland']['unresolved'][:4]) + '. Check them in Settings after installation.', 'warn')
    return rows


def build(facts, options=None):
    options = {**default_options(facts), **(options or {})}
    provider = providers.by_id(facts['environment']['chosen'])
    env = facts['environment']
    missing = list(facts['dependencies']['missing'])
    if options.get('fonts'):
        missing = sorted(set(missing + facts['dependencies']['recommendedMissing']))
    package_provider = package_providers.select(facts)
    notes = []
    package_error = ''
    if missing:
        try:
            notes = package_provider.check(_host_for_checks(), missing) if _host_for_checks() else []
        except package_providers.Unsupported as error:
            package_error = str(error)

    system = []
    def row(text, state='ok'):
        system.append({'text': text, 'state': state})
    row(('Hyprland ' + facts['hyprlandVersion']).strip() + (' already installed' if facts['hyprlandInstalled'] else ' is missing'), 'ok' if facts['hyprlandInstalled'] else 'warn')
    row(facts['gpu']['vendor'] + ' graphics' + (' · ' + facts['gpu']['driver'] + ' driver' if facts['gpu']['driver'] != 'unknown' else ' · no driver detected'), 'ok' if facts['gpu']['driver'] != 'unknown' else 'warn')
    row(facts['networkManager'] + ' configured' if facts['networkManager'] != 'none detected' else 'No network manager detected', 'ok' if facts['networkManager'] != 'none detected' else 'info')
    row('Quickshell ' + facts['quickshellVersion'] + ' present' if facts['quickshellInstalled'] else 'Quickshell will be installed', 'ok' if facts['quickshellInstalled'] else 'info')
    row(facts['distro']['name'] + ' · ' + facts['support']['status'], 'ok' if facts['support']['status'] == 'supported' else 'warn' if facts['support']['status'] == 'experimental' else 'info')

    migration = provider.plan_rows(facts) if options.get('migrate') else ['Keep the existing configuration untouched (migration turned off)']
    cedar = []
    if missing:
        cedar.append('Install dependencies: ' + ', '.join(missing))
    else:
        cedar.append('Dependencies already present')
    if facts['existingCedar']['session'] != 'not active':
        cedar.append('Hand the desktop back to the previous shell while CEDAR ' + facts['cedarVersion'] + ' installs, then start it again')
    if facts['existingCedar'].get('commandOwner') == 'source':
        cedar.append('Replace the cedar command from the earlier local-source registration (restorable from the journal)')
    cedar.append('Install CEDAR ' + facts['cedarVersion'] + ' as a versioned copy with the cedar command and offline recovery')
    cedar.append('Check that the CEDAR shell loads with this Quickshell and Qt')
    cedar.append('Install CEDAR application entries (Shield)')
    if options.get('migrate'):
        cedar.append('Write CEDAR’s display and input settings from what was imported')
    if options.get('keybinds'):
        cedar.append('Install CEDAR’s keybinds (Caelestia layout) through CEDAR’s journaled Hyprland loader; your other bindings stay')
    if options.get('session'):
        cedar.append('Start CEDAR in this session, keep it after a health check, and enable it at login (' + env['name'] + ' providers paused, restorable with cedar restore)')
    elif env.get('adapter'):
        cedar.append('Session handoff later: cedar try, then cedar keep')
    else:
        cedar.append('Session handoff for ' + env['name'] + ' is not validated yet: CEDAR installs and opens as a preview; your current shell keeps running')
    cedar.append('Verify the installation')

    active_session = facts['existingCedar']['session'] != 'not active'
    operations = []
    def op(id, title, description, optional=False, enabled=True, group=''):
        operations.append({'id': id, 'title': title, 'description': description, 'optional': optional, 'enabled': enabled, 'group': group})
    op('backup', 'System backup', 'Copy the configuration this plan may touch into a versioned backup with a manifest and restore script')
    op('leave', 'Hand back the desktop', 'Return to the previous desktop while CEDAR updates; CEDAR comes back in the session step' if active_session else 'No CEDAR session is running', enabled=active_session)
    op('dependencies', 'Dependencies', package_provider.describe(missing) if missing else 'All required software is already present')
    op('runtime', 'CEDAR runtime', 'Install the versioned release, the cedar command and the offline recovery tools')
    op('shell', 'CEDAR shell', 'Load the shell offscreen with the installed Quickshell and Qt to prove it runs here', group='ready')
    op('migrate', 'Configuration', 'Translate monitor, keyboard, application and wallpaper intent into CEDAR’s own settings', enabled=bool(options.get('migrate')), group='ready')
    op('session', 'Session', 'Start CEDAR, confirm it is healthy, and enable it at login' if options.get('session') else 'Not part of this run', enabled=bool(options.get('session')))
    op('verify', 'Verification', 'Check the installed files, the shell imports, the command and the session')

    plan = {'format': 1, 'version': facts['cedarVersion'], 'environment': env, 'options': options, 'system': system, 'migration': migration, 'cedar': cedar,
            'packages': missing, 'packageProvider': package_provider.id, 'packageNotes': notes, 'packageError': package_error,
            'privilege': privilege.method_name(facts) if missing else '', 'conflicts': facts['conflicts'], 'operations': operations,
            'attention': attention(facts, options), 'backupDestination': facts['configPaths']['state'] + '/installations/<timestamp>',
            'keep': env.get('keep', []), 'replace': env.get('replace', []), 'imports': imports(facts)}
    if package_error:
        plan['attention'].append({'id': 'packages', 'title': 'Packages cannot be prepared automatically', 'detail': package_error, 'severity': 'stop', 'learn': ''})
    plan['blocked'] = any(a['severity'] == 'stop' for a in plan['attention'])
    plan['digest'] = hashlib.sha256(json.dumps({'ops': operations, 'options': options, 'packages': missing, 'env': env['id'], 'version': facts['cedarVersion']}, sort_keys=True).encode()).hexdigest()[:16]
    return plan


def imports(facts):
    """What the finish screen can say was imported."""
    rows = []
    monitors = facts['hyprland']['monitors']
    if monitors:
        rows.append(str(len(monitors)) + (' monitors' if len(monitors) != 1 else ' monitor'))
    if facts['hyprland']['keyboard']:
        rows.append('Keyboard layout')
    if facts['apps']:
        rows.append('Preferred ' + ', '.join(sorted(facts['apps'])))
    if facts['wallpapers']:
        rows.append('Existing wallpaper library')
    return rows


_check_host = None


def set_check_host(host):
    """The host used for read-only package checks while planning (tests pass a FakeHost)."""
    global _check_host
    _check_host = host


def _host_for_checks():
    return _check_host


def render(plan, facts=None):
    """The plan as plain text for the terminal and --dry-run."""
    lines = ['CEDAR Installation Plan', '', 'Environment: ' + plan['environment']['name'] + ' (' + plan['environment']['stack'] + ')', '', 'SYSTEM']
    for row in plan['system']:
        lines.append(('  ✓ ' if row['state'] == 'ok' else '  ! ' if row['state'] == 'warn' else '  · ') + row['text'])
    lines += ['', 'MIGRATION']
    lines += ['  ✓ ' + r for r in plan['migration']]
    lines += ['', 'CEDAR']
    lines += ['  ✓ ' + r for r in plan['cedar']]
    if plan['packageNotes']:
        lines += ['', 'PACKAGES'] + ['  · ' + n for n in plan['packageNotes']]
        if plan['privilege']:
            lines.append('  · ' + privilege.describe(plan['privilege']))
    if plan['attention']:
        lines += ['', 'NEEDS ATTENTION']
        for row in plan['attention']:
            lines.append(('  ✗ ' if row['severity'] == 'stop' else '  ! ') + row['title'] + ' — ' + row['detail'])
    lines += ['', 'Backup: ' + plan['backupDestination'], 'Plan digest: ' + plan['digest']]
    return '\n'.join(lines)
