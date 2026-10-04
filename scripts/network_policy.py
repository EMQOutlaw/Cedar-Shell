"""Local-only by default. One permission check shared by network helpers."""
import json
import os
from pathlib import Path

def settings():
    base=Path(os.environ.get('XDG_CONFIG_HOME') or Path.home()/'.config')
    if not base.is_absolute():base=Path.home()/'.config'
    try:
        value=json.loads((base/'cedar/settings.json').read_text())
        return value if isinstance(value,dict) else {}
    except (OSError,ValueError):return {}

def require(feature):
    value=settings()
    if os.environ.get('CEDAR_LOCAL_ONLY')=='1' or value.get('localOnly',True) is not False:
        raise PermissionError('Local-only mode blocks external requests. Review Settings → Desktop → External access.')
    permission={'weather':'weatherEnabled','location':'weatherAutomatic','city-search':'weatherEnabled'}[feature]
    if value.get(permission) is not True:
        raise PermissionError('This external integration has not been enabled.')
