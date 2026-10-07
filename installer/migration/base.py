"""Migration providers: one per environment CEDAR knows how to recognize.

A provider declares markers (config folders, packages, user units, a
Quickshell profile, a running process, Hyprland includes, environment
variables). Detection scores them; no folder name alone proves an
installation. Each provider also says what CEDAR keeps, what it replaces,
which files to back up, which components conflict and whether a validated
desktop handoff exists for it. Providers without a validated handoff still
install CEDAR, migrate intent and leave the existing session running.
"""
from pathlib import Path

HARD, SOFT, COMPATIBLE = 'hard', 'soft', 'compatible'
VALIDATED, EXPERIMENTAL, PREVIEW = 'validated', 'experimental', 'preview'

# Components CEDAR provides itself and quiets while it runs. Nothing here is
# uninstalled: a soft conflict is disabled for the session and restored.
REPLACES = {
    'waybar': ('Waybar', 'bar'), 'dunst': ('Dunst', 'notification daemon'), 'mako': ('Mako', 'notification daemon'),
    'swaync': ('SwayNC', 'notification daemon'), 'hyprpaper': ('Hyprpaper', 'wallpaper daemon'),
    'swww-daemon': ('swww', 'wallpaper daemon'), 'awww-daemon': ('awww', 'wallpaper daemon'), 'swaybg': ('swaybg', 'wallpaper daemon'),
    'wlogout': ('wlogout', 'power menu'), 'rofi': ('Rofi', 'launcher'), 'wofi': ('Wofi', 'launcher'), 'walker': ('Walker', 'launcher'),
    'ags': ('AGS', 'shell'), 'eww': ('eww', 'widgets'),
}
RETAINED = {'hypridle': 'idle daemon', 'swayidle': 'idle daemon', 'hyprlock': 'locker', 'swaylock': 'locker',
            'cliphist': 'clipboard history', 'wl-paste': 'clipboard', 'wl-clip-persist': 'clipboard',
            'NetworkManager': 'network', 'pipewire': 'audio', 'wireplumber': 'audio', 'polkit': 'authentication'}


class Marker:
    def __init__(self, kind, value, weight=1, label=None):
        self.kind, self.value, self.weight, self.label = kind, value, weight, label or value

    def check(self, facts, host):
        kind, value = self.kind, self.value
        if kind == 'dir':
            return host.is_dir(host.home / value if not str(value).startswith('/') else value)
        if kind == 'file':
            return host.is_file(host.home / value if not str(value).startswith('/') else value)
        if kind == 'package':
            return any(name == value or name.startswith(value + '-') for name in facts['packages'])
        if kind == 'command':
            return bool(host.which(value))
        if kind == 'unit':
            return value in facts['userUnits']
        if kind == 'process':
            return any(Path(p['exe']).name == value for p in facts['processes'])
        if kind == 'qsprofile':
            return any(value in str(row.get('config_path', '')) for row in facts['quickshellInstances'])
        if kind == 'qsfile':
            return any(host.is_file(Path(row.get('config_path', '/none')).parent / value) for row in facts['quickshellInstances'])
        if kind == 'include':
            return any(value in f for f in facts['hyprland']['files'])
        if kind == 'env':
            return bool(host.environ.get(value))
        return False


class MigrationProvider:
    id = 'generic'
    name = 'Unknown environment'
    stack = 'Hyprland'
    summary = ''
    markers = ()
    threshold = 2
    handoff = PREVIEW
    adapter = ''          # which CEDAR session adapter can take over, if any
    keeps = ('Monitor configuration', 'Keyboard layout', 'Existing applications', 'Wallpaper library', 'Hyprland device rules')
    replaces = ()
    settings_paths = ()   # home-relative files to back up because CEDAR may touch or disable them

    def detect(self, facts, host):
        evidence = []
        score = 0
        for marker in self.markers:
            try:
                hit = marker.check(facts, host)
            except (OSError, ValueError):
                hit = False
            if hit:
                score += marker.weight
                evidence.append(marker.label)
        return {'id': self.id, 'name': self.name, 'score': score, 'evidence': evidence, 'detected': score >= self.threshold}

    def backup_targets(self, facts, host):
        targets = []
        for rel in self.settings_paths:
            path = host.home / rel
            if host.exists(path):
                targets.append(str(path))
        return targets

    def conflicts(self, facts):
        rows = []
        seen = set()
        for process in facts['processes']:
            name = Path(process['exe']).name
            if name in REPLACES and name not in seen:
                seen.add(name)
                label, role = REPLACES[name]
                rows.append({'component': label, 'role': role, 'kind': SOFT, 'process': name,
                             'reason': 'CEDAR provides its own ' + role + '; this one is paused for the CEDAR session and restored when you leave.'})
            elif name in RETAINED and name not in seen:
                seen.add(name)
                rows.append({'component': name, 'role': RETAINED[name], 'kind': COMPATIBLE, 'process': name, 'reason': 'Kept running; CEDAR works with it.'})
        return rows

    def plan_rows(self, facts):
        """Migration section rows for the plan, in the order they are done."""
        rows = ['Back up the Hyprland configuration CEDAR may touch']
        if facts['hyprland']['monitors']:
            rows.append('Import ' + str(len(facts['hyprland']['monitors'])) + ' monitor' + ('s' if len(facts['hyprland']['monitors']) != 1 else '') + ' (mode, position, scale, rotation)')
        if facts['hyprland']['keyboard']:
            rows.append('Import keyboard layout' + (' and options' if facts['hyprland']['keyboard'].get('kb_options') else ''))
        if facts['apps']:
            rows.append('Keep preferred ' + ', '.join(sorted(facts['apps'])))
        if facts['wallpapers']:
            rows.append('Point CEDAR at your wallpaper library (' + str(sum(w['images'] for w in facts['wallpapers'])) + ' images)')
        for row in self.conflicts(facts):
            if row['kind'] == SOFT:
                rows.append('Pause ' + row['component'] + ' while CEDAR runs')
        return rows

    def describe(self, facts):
        return {'id': self.id, 'name': self.name, 'stack': self.stack, 'summary': self.summary, 'handoff': self.handoff,
                'adapter': self.adapter, 'keep': list(self.keeps), 'replace': list(self.replaces) or [r['component'] for r in self.conflicts(facts) if r['kind'] == SOFT]}
