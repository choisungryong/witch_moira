"""Thin Godot launcher for checks, goldens, measurements and captures.

    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_loc.gd
    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --update

Arguments pass through unchanged and the exit code is Godot's. The child runs with APPDATA
pointed at _local/appdata/godot-<script name>/ (godot-window, godot-import without a script) so nothing is written to
%APPDATA%/WitchMoira and runs of different scripts do not share logs or the shader cache.
An isolated run waits for a free machine-wide Godot seat (default 6, MOIRA_GODOT_SLOTS; one GODOT_SLOT line is printed while
it waits, GODOT_SLOT_TIMEOUT and exit code 125 after MOIRA_GODOT_SLOT_WAIT_S, default 1200) and for a running import of this
work tree (repo_lock.py). The user's own play (a window run without --chapter1-profile-off) takes no seat.
A run that goes past its time limit is ended with its whole process tree (console parent and engine child), exit code 124
and one GODOT_TIMEOUT line on stderr. Limits: window 20 min, headless 40 min; change with --timeout-s=N (before "--",
not passed on to Godot) or MOIRA_GODOT_TIMEOUT_S; 0 means no limit. See godot_guard.py. Leftover Godot processes: godot_ps.py.
A window run (no --script, no --headless) is isolated only when the user arguments after "--"
contain --chapter1-profile-off; otherwise it is the user's own play, runs unisolated, and a
warning is printed.
"""
from pathlib import Path
import os, re, subprocess, sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env
import godot_guard
import repo_lock

GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))


def needs_isolation(args):
    engine, user = args, []
    if '--' in args:
        index = args.index('--')
        engine, user = args[:index], args[index + 1:]
    scripted = '--script' in engine or '-s' in engine or '--import' in engine or '--version' in engine or '--headless' in engine
    return scripted or '--chapter1-profile-off' in user


def purpose_of(args):
    """APPDATA folder name for this run: godot-<script file name>, godot-import or godot-window."""
    engine = args[:args.index('--')] if '--' in args else args
    for flag in ('--script', '-s'):
        if flag in engine and engine.index(flag) + 1 < len(engine):
            name = re.split(r'[\\/]', engine[engine.index(flag) + 1])[-1]
            name = re.sub(r'\.[A-Za-z0-9]+$', '', name)
            return 'godot-' + (re.sub(r'[^A-Za-z0-9._-]', '_', name).strip('.') or 'script')
    if '--version' in engine:
        return 'godot-version'
    return 'godot-import' if '--import' in engine else 'godot-window'


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
        env = isolated_env(purpose_of(args))
    else:
        env = None
        print('GODOT_WARN window run without --chapter1-profile-off: not isolated, saves go to %APPDATA%/WitchMoira', file=sys.stderr)
    try:
        if env is None:  # the user's own play: no seat, no wait
            code, _, timed_out = godot_guard.run_guarded([str(GODOT)] + args, limit, env=env)
        else:
            code, _, timed_out = godot_guard.run_seated([str(GODOT)] + args, limit, env=env, label=purpose_of(args))
    except repo_lock.LockTimeout as error:
        tag, _, rest = str(error).partition(' ')
        print('%s_TIMEOUT %s' % (tag, rest), file=sys.stderr)
        return 125
    if timed_out:
        print('GODOT_TIMEOUT ended the process tree after %d s (limit; change with --timeout-s=N or %s): %s' % (limit, godot_guard.ENV_NAME, ' '.join(args[:6])), file=sys.stderr)
    return code


if __name__ == '__main__':
    sys.exit(main())
