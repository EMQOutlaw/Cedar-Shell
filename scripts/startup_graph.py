"""Bounded, read-only startup/include evidence. Never evaluate config as code."""
import glob
import hashlib
import os
from pathlib import Path
import re
import shlex


def inspect(main, config_home, home, max_files=64, max_bytes=1048576, max_depth=16):
    variables={'HOME':str(home),'XDG_CONFIG_HOME':str(config_home)}
    result={'files':[],'commands':[],'unresolved':[],'complete':True}
    visited=set();active=set();used=0
    def unknown(reason):
        result['complete']=False
        if reason not in result['unresolved']:result['unresolved'].append(reason)
    def expand(value):
        def variable(match):
            key=match.group(1) or match.group(2)
            if key not in variables:raise ValueError('Unresolved variable '+key)
            return variables[key]
        if any(char in value for char in ('`','\0')) or '$(' in value:raise ValueError('Dynamic configuration expression')
        value=re.sub(r'\$\{([A-Za-z_][A-Za-z_0-9]*)\}|\$([A-Za-z_][A-Za-z_0-9]*)',variable,value)
        if value.startswith('~/'):value=str(home)+value[1:]
        return value
    def visit(path,depth):
        nonlocal used
        path=Path(os.path.abspath(path))
        resolved=path.resolve()
        if resolved in active:unknown('Include cycle');return
        if resolved in visited:return
        if depth>max_depth or len(visited)>=max_files:unknown('Include graph limit');return
        visited.add(resolved);active.add(resolved)
        try:
            size=path.stat().st_size
            if size>max_bytes-used:unknown('Configuration byte limit');return
            with path.open('rb') as stream:raw=stream.read(max_bytes-used+1)
            if len(raw)>max_bytes-used:unknown('Configuration byte limit');return
            used+=len(raw);text=raw.decode()
            managed=path.is_symlink() or any(parent.is_symlink() for parent in path.parents)
            result['files'].append({'path':str(path),'sha256':hashlib.sha256(raw).hexdigest(),
                                    'ownership':'managed-link' if managed else 'ordinary','syntax':path.suffix})
            for number,line in enumerate(text.splitlines(),1):
                stripped=line.strip()
                if not stripped or stripped.startswith(('#','--')):continue
                if path.suffix=='.lua':
                    # Only literal top-level includes are interpreted; callbacks,
                    # arbitrary Lua and computed imports remain review evidence.
                    match=re.fullmatch(r'dofile\(("[^"\n]*"|\'[^\'\n]*\')\)\s*;?',stripped)
                    if match:
                        target=Path(expand(match[1][1:-1]))
                        visit(target if target.is_absolute() else path.parent/target,depth+1)
                    elif any(token in stripped for token in ('dofile','require(','require ','exec_cmd','hl.on','os.execute')):
                        unknown('Lua startup/include expression requires adapter review')
                    continue
                if '=' not in stripped:continue
                key,value=map(str.strip,stripped.split('=',1))
                if key.startswith('$') and re.fullmatch(r'\$[A-Za-z_][A-Za-z_0-9]*',key):
                    try:variables[key[1:]]=expand(value)
                    except ValueError:unknown('Unresolved variable definition')
                elif key=='source':
                    try:
                        parts=shlex.split(value,comments=True)
                        # Hyprland accepts unquoted paths with spaces too.
                        included=expand(' '.join(parts))
                        target=Path(included)
                        if not target.is_absolute():target=path.parent/target
                        matches=sorted(glob.glob(str(target)))[:max_files+1]
                        if not matches:unknown('Missing include')
                        for match in matches:visit(Path(match),depth+1)
                    except (ValueError,OSError):unknown('Unresolved include')
                elif key in ('exec','exec-once'):
                    try:command=expand(value)
                    except ValueError:unknown('Unresolved startup command');continue
                    result['commands'].append({'path':str(path),'line':number,'kind':key,'command':command})
        except (OSError,UnicodeError):unknown('Unreadable configuration')
        finally:active.discard(resolved)
    visit(Path(main),0)
    return result
