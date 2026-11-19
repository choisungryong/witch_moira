"""Thin Godot launcher for checks, goldens, measurements and captures.

    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_loc.gd
    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --update

Arguments pass through unchanged and the exit code is Godot's. The child runs with APPDATA
pointed at _local/appdata/godot/ so nothing is written to %APPDATA%/WitchMoira.
A run that goes past its time limit is ended with its whole process tree (console parent and engine child), exit code 124
and one GODOT_TIMEOUT line on stderr. Limits: window 20 min, headless 40 min; change with --timeout-s=N (before "--",
not passed on to Godot) or MOIRA_GODOT_TIMEOUT_S; 0 means no limit. See godot_guard.py. Leftover Godot processes: godot_ps.py.
A window run (no --script, no --headless) is isolated only when the user arguments after "--"
contain --chapter1-profile-off; otherwise it is the user's own play, runs unisolated, and a
warning is printed.
"""
from pathlib import Path
import os, subprocess, sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env
import godot_guard

GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))


def needs_isolation(args):
    engine, user = args, []
    if '--' in args:
        index = args.index('--')
        engine, user = args[:index], args[index + 1:]
    scripted = '--script' in engine or '-s' in engine or '--import' in engine or '--version' in engine or '--headless' in engine
    return scripted or '--chapter1-profile-off' in user


def main():
    args, cli_timeout = godot_guard.split_timeout_arg(sys.argv[1:])
    try:
        limit = godot_guard.resolve_timeout(args, cli_timeout)
    except ValueError:
        print('GODOT_ARGS bad time limit (--timeout-s or %s must be a number of seconds, 0 = none)' % godot_guard.ENV_NAME, file=sys.stderr)
        return 2
    if not GODOT.is_file():
        print('Godot not found: ' + str(GODOT) + ' (set MOIRA_GODOT)', file=sys.stderr)
        return 2
    if needs_isolation(args):
        env = isolated_env('godot')
    else:
        env = None
        print('GODOT_WARN window run without --chapter1-profile-off: not isolated, saves go to %APPDATA%/WitchMoira', file=sys.stderr)
    code, _, timed_out = godot_guard.run_guarded([str(GODOT)] + args, limit, env=env)
    if timed_out:
        print('GODOT_TIMEOUT ended the process tree after %d s (limit; change with --timeout-s=N or %s): %s' % (limit, godot_guard.ENV_NAME, ' '.join(args[:6])), file=sys.stderr)
    return code


if __name__ == '__main__':
    sys.exit(main())
