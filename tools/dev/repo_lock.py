"""Lock files that keep Godot processes from tripping over each other (TECH-REVIEW-20261120 M2 and M3).

Two kinds, both plain files created with O_CREAT|O_EXCL that hold {"pid", "time", "label"}:

  * import lock (per work tree: <tree>/_local/locks/import.lock). An import (`godot --import`) rewrites .godot while
    other Godot processes of the same tree read it. import_lock() takes the file, then waits for the runs that were already
    going (their markers run-*.run) to end; run_guard() (every other Godot run of the tree) waits while the file exists.
  * seats (per machine: <main checkout>/_local/locks/godot-slot-<k>, k = 1..K). At most K Godot processes (default 6,
    MOIRA_GODOT_SLOTS changes it) run at the same time across all work trees, because a pile of Godot process trees is the
    prime suspect for WinError 1450 / exit 3221225477. Windows the user starts by hand never take a seat (no caller does).

A lock whose holder process is gone, or that is older than MAX_AGE_S, is a dead lock and is removed by whoever finds it.
Waiting is bounded: LockTimeout is raised afterwards. Standard library only.
"""
from pathlib import Path
import contextlib, json, os, random, sys, time

ROOT = Path(__file__).resolve().parents[2]
SEATS_ENV = 'MOIRA_GODOT_SLOTS'
DEFAULT_SEATS = 6
SEAT_WAIT_ENV = 'MOIRA_GODOT_SLOT_WAIT_S'
DEFAULT_SEAT_WAIT_S = 1200
IMPORT_WAIT_ENV = 'MOIRA_IMPORT_LOCK_WAIT_S'
DEFAULT_IMPORT_WAIT_S = 600
MAX_AGE_S = 4 * 3600      # longest legitimate hold is a 40 minute headless run; a live pid older than this is a reused pid
HALF_WRITTEN_S = 10       # an empty or unreadable lock file this young may be one being written right now


class LockTimeout(Exception):
    """A lock or seat was not available inside the time limit."""


def main_root(root=ROOT):
    """The main checkout (a work tree lives in <main>/.claude/worktrees/<name>). Same rule as godot_ps.main_root."""
    parts = Path(root).resolve().parts
    for index in range(len(parts) - 2):
        if parts[index] == '.claude' and parts[index + 1] == 'worktrees':
            return Path(*parts[:index])
    return Path(root).resolve()


def tree_locks_dir(root=ROOT):
    return Path(root) / '_local' / 'locks'


def seat_locks_dir(root=ROOT):
    return main_root(root) / '_local' / 'locks'


def pid_alive(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name == 'nt':
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return ctypes.get_last_error() == 5  # access denied: the process exists
        try:
            code = wintypes.DWORD(0)
            return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259  # STILL_ACTIVE
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_lock(path):
    """The lock file's JSON as a dict, or None when it is missing, empty or unreadable."""
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def is_dead(path, alive=pid_alive, now=time.time):
    """True when the lock file's holder is gone or it is older than MAX_AGE_S. A missing file is not "dead" (it is free)."""
    try:
        mtime = Path(path).stat().st_mtime
    except OSError:
        return False
    data = read_lock(path)
    if data is None:
        return now() - mtime > HALF_WRITTEN_S
    if now() - float(data.get('time', mtime)) > MAX_AGE_S:
        return True
    return not alive(data.get('pid'))


def try_create(path, label='', pid=None):
    """Create the lock file exclusively. True when this call made it."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(str(path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return False
    with os.fdopen(fd, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps({'pid': os.getpid() if pid is None else pid, 'time': time.time(), 'label': label}))
    return True


def remove_if_dead(path, alive=pid_alive, now=time.time):
    """Remove a dead lock. The check is repeated right before the removal (two finders of one dead lock must not
    remove a lock the other one has just taken)."""
    if is_dead(path, alive, now) and is_dead(path, alive, now):
        try:
            os.remove(str(path))
        except OSError:
            return False
        return True
    return False


def release(path):
    try:
        os.remove(str(path))
    except OSError:
        pass


def env_number(name, default, environ=None):
    raw = (os.environ if environ is None else environ).get(name, '')
    try:
        value = float(raw)
    except ValueError:
        return default
    return value if value >= 0 else default


def seat_count(environ=None):
    raw = (os.environ if environ is None else environ).get(SEATS_ENV, '')
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_SEATS
    return value if value >= 1 else DEFAULT_SEATS


def say(text):
    print(text, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------------------------------- seats

@contextlib.contextmanager
def seat(label='godot', locks_dir=None, count=None, wait_s=None, alive=pid_alive, sleep=time.sleep, clock=time.time, out=say):
    """One machine-wide Godot seat. Waits (and prints one line) when all seats are taken; LockTimeout after wait_s."""
    folder = Path(locks_dir) if locks_dir is not None else seat_locks_dir()
    count = seat_count() if count is None else count
    wait_s = env_number(SEAT_WAIT_ENV, DEFAULT_SEAT_WAIT_S) if wait_s is None else wait_s
    started = clock()
    announced = False
    taken = None
    while taken is None:
        order = list(range(1, count + 1))
        random.shuffle(order)  # processes starting at once do not all fight over seat 1
        for index in order:
            path = folder / ('godot-slot-%d' % index)
            if try_create(path, label) or (remove_if_dead(path, alive, clock) and try_create(path, label)):
                taken = path
                break
        if taken is not None:
            break
        if clock() - started > wait_s:
            raise LockTimeout('GODOT_SLOT no free seat of %d after %g s (%s)' % (count, wait_s, label))
        if not announced:
            announced = True
            out('GODOT_SLOT waiting: all %d Godot seats are taken (%s; MOIRA_GODOT_SLOTS changes the count, limit %g s)' % (count, label, wait_s))
        sleep(0.5 + random.random() * 0.5)
    try:
        yield taken
    finally:
        release(taken)


# ---------------------------------------------------------------------------------------------------- import lock

def _live_markers(folder, alive, clock):
    found = []
    for path in Path(folder).glob('run-*.run'):
        if is_dead(path, alive, clock):
            remove_if_dead(path, alive, clock)
        elif path.exists():
            found.append(path)
    return found


@contextlib.contextmanager
def import_lock(label='import', locks_dir=None, wait_s=None, drain_s=None, alive=pid_alive, sleep=time.sleep, clock=time.time, out=say):
    """Hold the tree's import lock. New runs wait (run_guard); runs already going are waited for up to drain_s,
    then the import goes ahead with a warning line. LockTimeout when the lock itself is not free inside wait_s."""
    folder = Path(locks_dir) if locks_dir is not None else tree_locks_dir()
    wait_s = env_number(IMPORT_WAIT_ENV, DEFAULT_IMPORT_WAIT_S) if wait_s is None else wait_s
    drain_s = wait_s if drain_s is None else drain_s
    path = folder / 'import.lock'
    started = clock()
    announced = False
    while not (try_create(path, label) or (remove_if_dead(path, alive, clock) and try_create(path, label))):
        if clock() - started > wait_s:
            raise LockTimeout('IMPORT_LOCK held by another import for more than %g s (%s)' % (wait_s, path))
        if not announced:
            announced = True
            out('IMPORT_LOCK waiting: another import of this work tree is running (limit %g s)' % wait_s)
        sleep(0.5 + random.random() * 0.5)
    try:
        drain_started = clock()
        while _live_markers(folder, alive, clock):
            if clock() - drain_started > drain_s:
                out('IMPORT_LOCK warning: runs that began before the import were still going after %g s; importing anyway' % drain_s)
                break
            sleep(0.5)
        yield path
    finally:
        release(path)


@contextlib.contextmanager
def run_guard(label='godot', locks_dir=None, wait_s=None, alive=pid_alive, sleep=time.sleep, clock=time.time, out=say):
    """Wait while the tree's import lock is held, then register as a running Godot (the marker an import waits for).
    The lock is checked again after the marker exists, so an import that started in between is not overlapped."""
    folder = Path(locks_dir) if locks_dir is not None else tree_locks_dir()
    wait_s = env_number(IMPORT_WAIT_ENV, DEFAULT_IMPORT_WAIT_S) if wait_s is None else wait_s
    lock = folder / 'import.lock'
    marker = folder / ('run-%d-%06d.run' % (os.getpid(), random.randrange(1000000)))
    started = clock()
    announced = False
    while True:
        if lock.exists() and is_dead(lock, alive, clock):
            remove_if_dead(lock, alive, clock)
        if not lock.exists():
            try_create(marker, label)
            if not lock.exists():
                break
            release(marker)
        if clock() - started > wait_s:
            raise LockTimeout('IMPORT_LOCK the project was being imported for more than %g s (%s)' % (wait_s, lock))
        if not announced:
            announced = True
            out('IMPORT_LOCK waiting: this work tree is being imported (%s; limit %g s)' % (label, wait_s))
        sleep(0.5)
    try:
        yield marker
    finally:
        release(marker)
