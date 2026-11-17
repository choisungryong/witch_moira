"""Environment for Godot child processes that must not touch the user folder.

Godot resolves user:// (project folder %APPDATA%/WitchMoira) and its own logs/caches from
%APPDATA%. Pointing APPDATA at _local/appdata/<purpose>/ moves every one of those writes
into the repository's disposable area. Only the child process gets the changed variable.
"""
from pathlib import Path
import os, re

ROOT = Path(__file__).resolve().parents[2]
APPDATA_ROOT = ROOT / '_local' / 'appdata'


def isolated_env(purpose):
    """Return a copy of os.environ with APPDATA under _local/appdata/<purpose>/ (created if missing)."""
    name = re.sub(r'[^A-Za-z0-9._-]', '_', str(purpose)).strip('.') or 'default'
    folder = APPDATA_ROOT / name
    folder.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['APPDATA'] = str(folder)
    return env
