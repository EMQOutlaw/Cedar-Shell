#!/usr/bin/env python3
"""Omarchy shell plugin registry for CEDAR's Go menu.

The Omarchy shell answers `omarchy-shell shell listPlugins|enablePlugin|
setPluginEnabled` from its in-memory registry. While CEDAR is the selected
theme that shell is stopped, so this helper reads the same manifests and edits
the same ~/.config/omarchy/shell.json with the same rules (PluginRegistry.qml):

* a `bar` plugin is active when `bar.id` names it (`omarchy.bar` by default);
* a `bar-widget` is on when it sits in `bar.layout`;
* other first-party plugins load unless listed in `disabledPlugins`;
* other third-party plugins load when listed in `plugins`.

Commands: list | rows [enable|disable|clone|remove|all] | enable <id> [placementJson]
          | disable <id> | set <id> <true|false> | toggle <id>
"""
import json
import os
from pathlib import Path
import sys

HOME_DIR = Path.home()
OMARCHY = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))
CONFIG_DIR = Path(os.environ.get('XDG_CONFIG_HOME', str(HOME_DIR/'.config')))
FIRST_PARTY = OMARCHY/'shell/plugins'
THIRD_PARTY = CONFIG_DIR/'omarchy/plugins'
USER_CONFIG = CONFIG_DIR/'omarchy/shell.json'
DEFAULT_CONFIG = OMARCHY/'config/omarchy/shell.json'
SECTIONS = ('left', 'center', 'right')
PLUGIN_GLYPH = '\U000f0431'


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def scan(first_party=FIRST_PARTY, third_party=THIRD_PARTY):
    """id -> manifest, flagged like the shell does (__isFirstParty)."""
    plugins = {}
    if first_party.is_dir():
        for manifest in sorted(first_party.rglob('*manifest.json')):
            depth = len(manifest.relative_to(first_party).parts)
            if depth < 2 or depth > 3: continue
            data = read_json(manifest)
            if isinstance(data, dict) and data.get('id'):
                data['__isFirstParty'] = True
                data['__source'] = str(manifest.parent)
                plugins[str(data['id'])] = data
    if third_party.is_dir():
        for manifest in sorted(third_party.glob('*/manifest.json')):
            data = read_json(manifest)
            if isinstance(data, dict) and data.get('id'):
                data['__isFirstParty'] = False
                data['__source'] = str(manifest.parent)
                plugins[str(data['id'])] = data
    return plugins


def load_config(user=USER_CONFIG, default=DEFAULT_CONFIG):
    source = user if user.exists() and user.stat().st_size else default
    config = read_json(source)
    return config if isinstance(config, dict) else {}


def ensure_shape(config):
    config['version'] = 1
    bar = config.setdefault('bar', {})
    if not isinstance(bar, dict): bar = config['bar'] = {}
    layout = bar.setdefault('layout', {})
    if not isinstance(layout, dict): layout = bar['layout'] = {}
    for section in SECTIONS:
        if not isinstance(layout.get(section), list): layout[section] = []
    if not isinstance(config.get('plugins'), list): config['plugins'] = []
    return config


def kinds_of(manifest):
    kinds = manifest.get('kinds') if manifest else None
    return [str(k) for k in kinds] if isinstance(kinds, list) else []


def cloned_from(manifest):
    meta = manifest.get('omarchy') if manifest else None
    return str(meta.get('clonedFrom') or '') if isinstance(meta, dict) else ''


def entry_id(entry):
    if isinstance(entry, dict): return str(entry.get('id') or '')
    return str(entry or '')


def find_entry(config, plugin_id):
    layout = ((config.get('bar') or {}).get('layout') or {})
    for section in SECTIONS:
        for index, entry in enumerate(layout.get(section) or []):
            if entry_id(entry) == plugin_id: return dict(kind='bar', section=section, index=index)
    for index, entry in enumerate(config.get('plugins') or []):
        if entry_id(entry) == plugin_id: return dict(kind='plugin', index=index)
    return None


def is_disabled(config, plugin_id):
    return plugin_id in (config.get('disabledPlugins') or [])


def selected_bar(config):
    return str(((config.get('bar') or {}).get('id')) or 'omarchy.bar')


def is_enabled(plugins, config, plugin_id):
    manifest = plugins.get(plugin_id)
    if manifest:
        if 'bar' in kinds_of(manifest): return selected_bar(config) == plugin_id
        if is_disabled(config, plugin_id): return False
        if manifest.get('__isFirstParty'): return True
    return find_entry(config, plugin_id) is not None


def listing(plugins=None, config=None):
    plugins = scan() if plugins is None else plugins
    config = load_config() if config is None else config
    rows = []
    for plugin_id, manifest in plugins.items():
        kinds = kinds_of(manifest)
        is_bar = 'bar' in kinds
        is_widget = 'bar-widget' in kinds
        active = is_bar and selected_bar(config) == plugin_id
        location = find_entry(config, plugin_id)
        rows.append(dict(
            id=plugin_id, name=str(manifest.get('name') or plugin_id), kinds=kinds,
            description=str(manifest.get('description') or ''),
            enabled=active if is_bar else (location is not None and location['kind'] == 'bar') if is_widget else is_enabled(plugins, config, plugin_id),
            active=active, canDisable=not is_bar, firstParty=bool(manifest.get('__isFirstParty')),
            clonedFrom=cloned_from(manifest)))
    rows.sort(key=lambda row: (row['name'].lower(), row['id']))
    return rows


def add_disabled(config, plugin_id):
    disabled = config.setdefault('disabledPlugins', [])
    if plugin_id not in disabled: disabled.append(plugin_id)


def remove_disabled(config, plugin_id):
    disabled = [d for d in config.get('disabledPlugins') or [] if d != plugin_id]
    if disabled: config['disabledPlugins'] = disabled
    else: config.pop('disabledPlugins', None)


def restores_source(config, clone_id):
    return clone_id in (config.get('cloneSourceRestores') or [])


def set_restores_source(config, clone_id, value):
    restores = [r for r in config.get('cloneSourceRestores') or [] if r != clone_id]
    if value: restores.append(clone_id)
    if restores: config['cloneSourceRestores'] = restores
    else: config.pop('cloneSourceRestores', None)


def active_clone_for(plugins, config, source_id):
    for candidate, manifest in plugins.items():
        if cloned_from(manifest) == source_id and is_enabled(plugins, config, candidate): return candidate
    return ''


def remove_location(config, location):
    if not location: return
    if location['kind'] == 'bar': del config['bar']['layout'][location['section']][location['index']]
    else: del config['plugins'][location['index']]


def restore_clone_source(plugins, config, clone_id, source_id):
    location = find_entry(config, clone_id)
    source_manifest = plugins.get(source_id) or {}
    if location and location['kind'] == 'bar':
        entry = config['bar']['layout'][location['section']][location['index']]
        if source_manifest and 'bar-widget' in kinds_of(source_manifest):
            replacement = dict(entry) if isinstance(entry, dict) else {}
            replacement['id'] = source_id
            config['bar']['layout'][location['section']][location['index']] = replacement
        else: remove_location(config, location)
    elif location: remove_location(config, location)
    if restores_source(config, clone_id): remove_disabled(config, source_id)
    set_restores_source(config, clone_id, False)


def default_section(manifest):
    meta = manifest.get('barWidget') if manifest else None
    section = str(meta.get('defaultSection') or '') if isinstance(meta, dict) else ''
    return section if section in SECTIONS else 'center'


def bar_target(config, placement, fallback_section):
    layout = config['bar']['layout']
    section = placement.get('section') if placement.get('section') in SECTIONS else fallback_section
    relative = placement.get('before') or placement.get('after')
    if relative:
        for candidate in ([section] if placement.get('section') else SECTIONS):
            for index, entry in enumerate(layout[candidate]):
                if entry_id(entry) == str(relative):
                    return candidate, index + (0 if placement.get('before') else 1)
        raise ValueError('could not find target widget ' + str(relative))
    if isinstance(placement.get('index'), int):
        return section, max(0, min(len(layout[section]), placement['index']))
    return section, len(layout[section])


def set_enabled(plugin_id, value, placement=None, plugins=None, config=None):
    plugins = scan() if plugins is None else plugins
    config = ensure_shape(load_config() if config is None else config)
    placement = placement or {}
    manifest = plugins.get(plugin_id)
    if value and not manifest: raise KeyError('unknown plugin ' + plugin_id)
    kinds = kinds_of(manifest)
    is_bar, is_widget = 'bar' in kinds, 'bar-widget' in kinds
    has_other_kind = any(k != 'bar-widget' for k in kinds)
    source = cloned_from(manifest)
    first_party = bool(manifest and manifest.get('__isFirstParty'))
    if value and first_party:
        clone = active_clone_for(plugins, config, plugin_id)
        if clone:
            restore_clone_source(plugins, config, clone, plugin_id)
            remove_disabled(config, plugin_id)
    if is_bar:
        if value: config['bar']['id'] = plugin_id
        elif selected_bar(config) == plugin_id:
            if source and source != 'omarchy.bar': config['bar']['id'] = source
            else: config['bar'].pop('id', None)
        return config
    location = find_entry(config, plugin_id)
    if value:
        remove_disabled(config, plugin_id)
        entry = dict(id=plugin_id)
        if not location and is_widget:
            source_location = find_entry(config, source) if source else None
            if source_location and source_location['kind'] == 'bar':
                current = config['bar']['layout'][source_location['section']][source_location['index']]
                replacement = dict(current) if isinstance(current, dict) else entry
                replacement['id'] = plugin_id
                config['bar']['layout'][source_location['section']][source_location['index']] = replacement
            else:
                section, index = bar_target(config, placement, default_section(manifest))
                config['bar']['layout'][section].insert(index, entry)
        elif not location and not first_party:
            config['plugins'].append(entry)
        if source and has_other_kind and not is_disabled(config, source):
            add_disabled(config, source)
            set_restores_source(config, plugin_id, True)
        return config
    if source: restore_clone_source(plugins, config, plugin_id, source)
    else: remove_location(config, location)
    if first_party and not is_widget: add_disabled(config, plugin_id)
    return config


def save_config(config, path=USER_CONFIG):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.cedar-tmp')
    tmp.write_text(json.dumps(config, indent=2, sort_keys=True) + '\n')
    tmp.replace(path)


def rows(filter_name='all'):
    plugins = scan()
    out = []
    for row in listing(plugins):
        if filter_name == 'enable' and row['enabled']: continue
        if filter_name == 'disable' and not (row['canDisable'] and row['enabled']): continue
        if filter_name == 'clone' and not (row['firstParty'] and not any(r['clonedFrom'] == row['id'] for r in listing(plugins))): continue
        if filter_name == 'remove' and row['firstParty']: continue
        if filter_name == 'menu':
            # Go-menu provider rows: label, value, current (current == value marks ✓).
            out.append('\t'.join([row['name'] + '  ' + row['id'], row['id'], row['id'] if row['enabled'] else '']))
            continue
        label = row['name'] if filter_name != 'all' else row['name'] + ('  ✓' if row['enabled'] else '')
        out.append('\t'.join([PLUGIN_GLYPH, label, row['id']]))
    return out


def main(argv):
    command = argv[0] if argv else 'list'
    if command == 'list':
        print(json.dumps(listing())); return 0
    if command == 'rows':
        print('\n'.join(rows(argv[1] if len(argv) > 1 else 'all'))); return 0
    if command in ('enable', 'disable', 'set', 'toggle'):
        if len(argv) < 2: raise SystemExit('plugin id is required')
        plugin_id = argv[1]
        if command == 'enable':
            placement = json.loads(argv[2]) if len(argv) > 2 and argv[2].strip() else {}
            value = True
        elif command == 'disable': value, placement = False, {}
        elif command == 'set': value, placement = argv[2].lower() == 'true', {}
        else:
            current = next((r for r in listing() if r['id'] == plugin_id), None)
            if current is None: raise SystemExit('unknown plugin ' + plugin_id)
            if current['enabled'] and not current['canDisable']: raise SystemExit('a bar is replaced by enabling another bar')
            value, placement = not current['enabled'], {}
        try:
            save_config(set_enabled(plugin_id, value, placement))
        except (KeyError, ValueError) as error:
            print(str(error).strip("'"), file=sys.stderr); return 1
        if command == 'toggle':
            name = next((r['name'] for r in listing() if r['id'] == plugin_id), plugin_id)
            print(('Enabled ' if value else 'Disabled ') + name + '. Takes effect in the Omarchy shell.')
        else: print('ok')
        return 0
    if command in ('rescan', 'reloadConfig'):
        print('ok'); return 0
    raise SystemExit(__doc__)


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
