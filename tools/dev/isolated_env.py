"""Environment for Godot child processes that must not touch the user folder.

Godot resolves user:// (project folder %APPDATA%/WitchMoira) and its own logs/caches from
%APPDATA%. Pointing APPDATA at _local/appdata/<purpose>/ moves every one of those writes
into the repository's disposable area. Only the child process gets the changed variable.

MOIRA_LOCAL_ROOT (optional, environment of the tool that starts Godot): another base folder for that area. The isolated folders then
live in <MOIRA_LOCAL_ROOT>/_local/appdata/<purpose>/ instead of <repository>/_local/appdata/<purpose>/ (for example on another
drive). The "_local/appdata" tail is kept on purpose: the profile checks in chapter1/tests refuse to run unless the user data folder
path contains /_local/appdata/. Unset or empty = the repository, exactly as before. It must be an absolute path and must not
be inside the user folder %APPDATA%/WitchMoira.
"""
from pathlib import Path
import os, re

ROOT = Path(__file__).resolve().parents[2]
APPDATA_ROOT = ROOT / '_local' / 'appdata'   # the default; appdata_root() is what isolated_env() uses
LOCAL_ROOT_ENV = 'MOIRA_LOCAL_ROOT'


def appdata_root(environ=None):
    """<base>/_local/appdata, where base is MOIRA_LOCAL_ROOT when set, otherwise the repository."""
    environ = os.environ if environ is None else environ
    value = environ.get(LOCAL_ROOT_ENV, '').strip()
    if not value:
        return APPDATA_ROOT
    base = Path(value)
    if not base.is_absolute():
        raise ValueError('%s must be an absolute path: %s' % (LOCAL_ROOT_ENV, value))
    here = str(base).replace(chr(92), '/').rstrip('/').lower() + '/'
    for user in (environ.get('APPDATA', ''), str(Path.home() / 'AppData' / 'Roaming')):
        if user and here.startswith(user.replace(chr(92), '/').rstrip('/').lower() + '/witchmoira/'):
            raise ValueError('%s must not be inside the user save folder: %s' % (LOCAL_ROOT_ENV, value))
    return base / '_local' / 'appdata'


def isolated_env(purpose):
    """Return a copy of os.environ with APPDATA under _local/appdata/<purpose>/ (created if missing); the base can be moved with MOIRA_LOCAL_ROOT."""
    name = re.sub(r'[^A-Za-z0-9._-]', '_', str(purpose)).strip('.') or 'default'
    folder = appdata_root() / name
    folder.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['APPDATA'] = str(folder)
    return env
