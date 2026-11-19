"""Time limit and process-tree kill for Godot child processes (used by godot.py and run_all.py).

On Windows the console Godot (Godot_*_console.exe) starts the real engine (Godot_*_win64.exe) as a child. Ending
only the parent (what subprocess.run(timeout=) does) leaves the child window on screen. run_guarded() ends the whole tree.

Default limits (seconds): window run 1200, headless run 2400. The longest normal run is run_all's run-spells-full,
about 16-20 minutes headless (its own run_all limit is 2400); a window run is a capture or a frame probe of a few minutes.
Override: --timeout-s=N before "--" (godot.py), or the environment variable MOIRA_GODOT_TIMEOUT_S. 0 means no limit.

run_seated() / run_import() add the lock files of repo_lock.py around run_guarded(): a machine-wide Godot seat (default 6,
MOIRA_GODOT_SLOTS) and the work tree's import lock. They raise repo_lock.LockTimeout when a seat or the lock is not free in time.
"""
import os, subprocess, sys

import repo_lock

DEFAULT_WINDOW_S = 1200
DEFAULT_HEADLESS_S = 2400
TIMEOUT_EXIT = 124
ENV_NAME = 'MOIRA_GODOT_TIMEOUT_S'


def default_timeout(args):
    engine = args[:args.index('--')] if '--' in args else args
    return DEFAULT_HEADLESS_S if '--headless' in engine else DEFAULT_WINDOW_S


def split_timeout_arg(args):
    """Return (args without --timeout-s=N, N or None). Only the engine part (before "--") is searched."""
    end = args.index('--') if '--' in args else len(args)
    value, kept = None, []
    for index, arg in enumerate(args):
        if index < end and arg.startswith('--timeout-s='):
            value = arg.split('=', 1)[1]
        else:
            kept.append(arg)
    return kept, value


def resolve_timeout(args, cli_value=None, environ=None):
    """Seconds (float) or 0 for no limit. Raises ValueError for a value that is not a non-negative number."""
    environ = os.environ if environ is None else environ
    raw = cli_value if cli_value is not None else environ.get(ENV_NAME, '')
    if raw in (None, ''):
        return float(default_timeout(args))
    value = float(raw)
    if value < 0:
        raise ValueError('negative timeout')
    return value


def kill_tree(pid):
    """End a process and everything it started."""
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(int(pid)), '/T', '/F'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        try:
            os.killpg(os.getpgid(pid), 9)
        except OSError:
            pass


def run_guarded(command, timeout, env=None, cwd=None, capture=False):
    """Run command. Returns (exit code, output bytes or None, timed_out). After the limit the whole tree is ended and the
    code is TIMEOUT_EXIT. timeout 0 or None means no limit. Ctrl-C also ends the tree."""
    kwargs = {'env': env, 'cwd': cwd}
    if capture:
        kwargs['stdout'] = subprocess.PIPE
        kwargs['stderr'] = subprocess.STDOUT
    if os.name != 'nt':
        kwargs['start_new_session'] = True
    proc = subprocess.Popen(command, **kwargs)
    try:
        out, _ = proc.communicate(timeout=timeout or None)
    except subprocess.TimeoutExpired:
        kill_tree(proc.pid)
        try:
            out, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            out = b''
        return TIMEOUT_EXIT, out if capture else None, True
    except BaseException:
        kill_tree(proc.pid)
        raise
    return proc.returncode, out if capture else None, False


def run_seated(command, timeout, env=None, cwd=None, capture=False, label='godot', seat_dir=None, lock_dir=None):
    """run_guarded() inside one machine-wide Godot seat and after any import of this work tree has finished.
    Same return value. Raises repo_lock.LockTimeout (message starts with GODOT_SLOT or IMPORT_LOCK)."""
    with repo_lock.seat(label, locks_dir=seat_dir):
        with repo_lock.run_guard(label, locks_dir=lock_dir):
            return run_guarded(command, timeout, env=env, cwd=cwd, capture=capture)


def run_import(command, timeout, env=None, cwd=None, capture=False, label='import', seat_dir=None, lock_dir=None):
    """run_guarded() for `godot --import`: one seat (taken first, so a waiting run never blocks the import) and the import lock."""
    with repo_lock.seat(label, locks_dir=seat_dir):
        with repo_lock.import_lock(label, locks_dir=lock_dir):
            return run_guarded(command, timeout, env=env, cwd=cwd, capture=capture)
