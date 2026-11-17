"""Thin Godot launcher for checks, goldens, measurements and captures.

    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_loc.gd
    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --update

Arguments pass through unchanged and the exit code is Godot's. The child runs with APPDATA
pointed at _local/appdata/godot/ so nothing is written to %APPDATA%/WitchMoira.
A window run (no --script, no --headless) is isolated only when the user arguments after "--"
contain --chapter1-profile-off; otherwise it is the user's own play, runs unisolated, and a
warning is printed.
"""
from pathlib import Path
import os, subprocess, sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env

GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))


def needs_isolation(args):
    engine, user = args, []
    if '--' in args:
        index = args.index('--')
        engine, user = args[:index], args[index + 1:]
    scripted = '--script' in engine or '-s' in engine or '--import' in engine or '--version' in engine or '--headless' in engine
    return scripted or '--chapter1-profile-off' in user


def main():
    args = sys.argv[1:]
    if not GODOT.is_file():
        print('Godot not found: ' + str(GODOT) + ' (set MOIRA_GODOT)', file=sys.stderr)
        return 2
    if needs_isolation(args):
        env = isolated_env('godot')
    else:
        env = None
        print('GODOT_WARN window run without --chapter1-profile-off: not isolated, saves go to %APPDATA%/WitchMoira', file=sys.stderr)
    return subprocess.call([str(GODOT)] + args, env=env)


if __name__ == '__main__':
    sys.exit(main())
