"""The environments CEDAR recognizes. Markers only; nothing here is executed.

Weights: a folder or command alone scores 1 and never reaches the threshold of
2; a running shell, a state file or an installed package scores 2.
"""
from .base import Marker, MigrationProvider, VALIDATED, EXPERIMENTAL, PREVIEW


class PlainHyprland(MigrationProvider):
    id, name, stack = 'plain-hyprland', 'Hyprland', 'Hyprland'
    summary = 'A plain Hyprland session with standalone components.'
    handoff, adapter = EXPERIMENTAL, 'hyprland'
    threshold = 1
    markers = (Marker('command', 'hyprctl', 1, 'hyprctl command'),)
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua', '.config/hypr/autostart.conf', '.config/hypr/autostart.lua', '.config/waybar', '.config/mako', '.config/dunst')


class Omarchy(MigrationProvider):
    id, name, stack = 'omarchy', 'Omarchy', 'Hyprland + Quickshell'
    summary = 'Omarchy with its own Quickshell shell, menu, lock and theme system.'
    handoff, adapter = EXPERIMENTAL, 'omarchy'
    markers = (Marker('dir', '/usr/share/omarchy', 1, 'Omarchy installation'), Marker('command', 'omarchy', 1, 'omarchy command'),
               Marker('dir', '.config/omarchy', 1, '~/.config/omarchy'), Marker('qsprofile', '/omarchy/', 2, 'Omarchy shell running'),
               Marker('package', 'omarchy', 1, 'omarchy package'))
    keeps = ('Monitor configuration', 'Keyboard layout', 'Existing applications', 'Wallpaper and theme files', 'Omarchy lock, idle and polkit services')
    replaces = ('Omarchy shell (bar, notifications, OSD)', 'Omarchy menu shortcut')
    settings_paths = ('.config/hypr/hyprland.lua', '.config/hypr/hyprland.conf', '.config/hypr/bindings.lua', '.config/hypr/autostart.lua', '.config/omarchy/shell.json')


class HyDE(MigrationProvider):
    id, name, stack = 'hyde', 'HyDE', 'Hyprland + Waybar'
    summary = 'HyDE dotfiles: Waybar, Rofi, swww and the hyde theme tooling.'
    markers = (Marker('dir', '.config/hyde', 1, '~/.config/hyde'), Marker('file', '.config/hypr/hyde.conf', 1, 'hyde.conf'),
               Marker('dir', '.local/share/hyde', 1, '~/.local/share/hyde'), Marker('command', 'hyde-shell', 1, 'hyde-shell command'),
               Marker('include', 'hyde', 1, 'Hyprland includes HyDE files'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyde.conf', '.config/hypr/userprefs.conf', '.config/hypr/monitors.conf', '.config/waybar')


class Caelestia(MigrationProvider):
    id, name, stack = 'caelestia', 'Caelestia', 'Hyprland + Quickshell'
    summary = 'Caelestia dots with their Quickshell shell and CLI-managed Hyprland files.'
    markers = (Marker('dir', '.config/caelestia', 1, '~/.config/caelestia'), Marker('file', '.local/state/caelestia/dots-state.json', 2, 'caelestia dots state'),
               Marker('package', 'caelestia-shell', 2, 'caelestia-shell package'), Marker('qsprofile', '/caelestia/', 2, 'Caelestia shell running'),
               Marker('command', 'caelestia', 1, 'caelestia command'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua', '.config/caelestia/hypr-user.lua', '.config/caelestia/hypr-vars.lua', '.config/caelestia/shell.json')


class Noctalia(MigrationProvider):
    id, name, stack = 'noctalia', 'Noctalia', 'Hyprland + Noctalia'
    summary = 'Noctalia shell (native 5.x or the Quickshell 4.x profile).'
    handoff, adapter = EXPERIMENTAL, 'noctalia'
    markers = (Marker('process', 'noctalia', 3, 'Noctalia running'), Marker('qsfile', 'Commons/Settings.qml', 3, 'Noctalia Quickshell profile running'),
               Marker('dir', '.config/noctalia', 1, '~/.config/noctalia'), Marker('package', 'noctalia', 1, 'noctalia package'))
    keeps = ('Monitor configuration', 'Keyboard layout', 'Existing applications', 'Wallpaper library', 'Noctalia lock, idle and authentication')
    replaces = ('Noctalia bar, dock, notifications and OSD (suspended for the CEDAR session)',)
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua', '.config/noctalia/settings.json', '.config/noctalia/noctalia.toml')


class Ryoku(MigrationProvider):
    id, name, stack = 'ryoku', 'Ryoku', 'Hyprland + Quickshell'
    summary = 'Ryoku with its materialized Hyprland files and shell installer state.'
    markers = (Marker('file', '.local/state/ryoku/shell-install-state.json', 2, 'Ryoku install state'), Marker('dir', '.config/ryoku', 1, '~/.config/ryoku'),
               Marker('qsprofile', '/ryoku/', 2, 'Ryoku shell running'), Marker('package', 'ryoku', 1, 'ryoku package'), Marker('command', 'ryoku', 1, 'ryoku command'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua', '.config/ryoku')


class End4(MigrationProvider):
    id, name, stack = 'end4', 'end-4 illogical-impulse', 'Hyprland + Quickshell'
    summary = 'end-4 dots (illogical-impulse) with the ii Quickshell shell.'
    markers = (Marker('dir', '.config/illogical-impulse', 1, '~/.config/illogical-impulse'), Marker('file', '.config/quickshell/ii/shell.qml', 2, 'ii Quickshell profile'),
               Marker('qsprofile', '/quickshell/ii/', 2, 'ii shell running'), Marker('dir', '.config/hypr/hyprland', 1, '~/.config/hypr/hyprland'),
               Marker('dir', '.config/ags', 1, '~/.config/ags'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/custom', '.config/hypr/hyprland')


class ML4W(MigrationProvider):
    id, name, stack = 'ml4w', 'ML4W', 'Hyprland + Waybar'
    summary = 'ML4W dotfiles with Waybar, Rofi and the ML4W settings apps.'
    markers = (Marker('dir', '.config/ml4w', 1, '~/.config/ml4w'), Marker('dir', '.config/com.ml4w.settings', 1, 'ML4W settings app'),
               Marker('file', '.config/hypr/conf/ml4w.conf', 1, 'ml4w.conf'), Marker('dir', '.config/hypr/conf', 1, '~/.config/hypr/conf'),
               Marker('command', 'ml4w-hyprland-setup', 1, 'ML4W setup command'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/conf', '.config/waybar')


class JaKooLit(MigrationProvider):
    id, name, stack = 'jakoolit', 'JaKooLit Hyprland-Dots', 'Hyprland + Waybar'
    summary = 'JaKooLit Hyprland-Dots with Waybar, Rofi, swww and SwayNC.'
    markers = (Marker('dir', '.config/hypr/UserConfigs', 1, 'UserConfigs folder'), Marker('dir', '.config/hypr/UserScripts', 1, 'UserScripts folder'),
               Marker('dir', '.config/hypr/configs', 1, '~/.config/hypr/configs'), Marker('file', '.config/hypr/UserConfigs/Monitors.conf', 1, 'Monitors.conf'),
               Marker('dir', '.config/waybar/style', 1, 'Waybar style folder'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/UserConfigs', '.config/waybar')


class GenericQuickshell(MigrationProvider):
    id, name, stack = 'generic-quickshell', 'Quickshell profile', 'Hyprland + Quickshell'
    summary = 'A Quickshell shell CEDAR does not recognize by name.'
    threshold = 2
    markers = (Marker('process', 'qs', 1, 'Quickshell running'), Marker('process', 'quickshell', 1, 'Quickshell running'),
               Marker('dir', '.config/quickshell', 1, '~/.config/quickshell'))
    replaces = ('The running Quickshell shell is left running; CEDAR opens as a preview until its role is reviewed',)
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua')


class WaybarSetup(MigrationProvider):
    id, name, stack = 'waybar', 'Waybar setup', 'Hyprland + Waybar'
    summary = 'Hyprland with Waybar and standalone daemons.'
    handoff, adapter = EXPERIMENTAL, 'hyprland'
    threshold = 2
    markers = (Marker('process', 'waybar', 2, 'Waybar running'), Marker('dir', '.config/waybar', 1, '~/.config/waybar'), Marker('package', 'waybar', 1, 'waybar package'))
    settings_paths = ('.config/hypr/hyprland.conf', '.config/hypr/hyprland.lua', '.config/waybar', '.config/mako', '.config/dunst')


# Order matters: the most specific environments come first; PlainHyprland is
# the fallback when nothing else is recognized.
PROVIDERS = (Omarchy(), HyDE(), Caelestia(), Noctalia(), Ryoku(), End4(), ML4W(), JaKooLit(), WaybarSetup(), GenericQuickshell(), PlainHyprland())


def by_id(provider_id):
    return next((p for p in PROVIDERS if p.id == provider_id), PROVIDERS[-1])


def detect(facts, host):
    """Every provider's score, the chosen environment, and the runners-up."""
    results = [p.detect(facts, host) for p in PROVIDERS]
    detected = [r for r in results if r['detected']]
    # Prefer the most specific recognized environment; plain Hyprland only when nothing else matched.
    chosen = next((r for r in detected if r['id'] not in ('plain-hyprland', 'waybar', 'generic-quickshell')), None) \
        or next((r for r in detected if r['id'] in ('waybar', 'generic-quickshell')), None) \
        or next((r for r in detected if r['id'] == 'plain-hyprland'), None)
    return {'results': results, 'chosen': chosen['id'] if chosen else '', 'also': [r['id'] for r in detected if chosen and r['id'] != chosen['id']]}
