"""List the Godot processes that are running now, and end the stale ones this repository's tools started.

    python tools/dev/godot_ps.py                    # table: PID, start, age, window/headless, script and main arguments, project folder
    python tools/dev/godot_ps.py --stale-min=60     # only processes older than 60 minutes
    python tools/dev/godot_ps.py --stale-min=60 --kill-stale --dry-run   # show what would be ended
    python tools/dev/godot_ps.py --stale-min=60 --kill-stale             # end them (whole process tree each)

--kill-stale ends a process only when ALL hold: its --path is this repository or one of its .claude/worktrees/, it was started
the way tools/dev does it (a --script or --headless run, or a game window with --chapter1-profile-off AND --chapter1-pilot or --chapter1-quit-after;
a window with profile-off but without those, such as the trial build, is treated as a person's play), its parent (if alive)
is not an unrelated program, and it is older than --stale-min (default 60 with --kill-stale). Everything else is only shown, with
the reason ("user play" = a window run without --chapter1-profile-off, never ended; "unclear" = shown, not ended).
Windows only (process list from CIM). Exit code 0, or 2 for a bad argument.
"""
from pathlib import Path
import argparse, datetime, json, os, re, shlex, subprocess, sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_guard

ROOT = Path(__file__).resolve().parents[2]
TOOL_PARENTS = ('godot.py', 'run_dev.py', 'run_all.py', 'build.py', 'perf_ab.py')
DEFAULT_KILL_STALE_MIN = 60


def main_root(root=ROOT):
    """The main checkout: a worktree lives in <main>/.claude/worktrees/<name>."""
    parts = Path(root).resolve().parts
    for index in range(len(parts) - 2):
        if parts[index] == '.claude' and parts[index + 1] == 'worktrees':
            return Path(*parts[:index])
    return Path(root).resolve()


def norm(path):
    return str(path).replace('\\', '/').rstrip('/').lower()


def process_cwd(pid):
    """Current directory of a same-user 64-bit process read from its PEB (ctypes), or '' when it cannot be read.
    CIM has no working directory, and a relative --path "." is only meaningful with it."""
    if os.name != 'nt':
        return ''
    import ctypes
    from ctypes import wintypes
    k32, nt = ctypes.windll.kernel32, ctypes.windll.ntdll
    k32.OpenProcess.restype = wintypes.HANDLE
    handle = k32.OpenProcess(0x0400 | 0x0010, False, pid)  # QUERY_INFORMATION | VM_READ
    if not handle:
        return ''
    try:
        class PBI(ctypes.Structure):
            _fields_ = [('Reserved1', ctypes.c_void_p), ('PebBaseAddress', ctypes.c_void_p), ('Reserved2', ctypes.c_void_p * 2),
                        ('UniqueProcessId', ctypes.c_void_p), ('Reserved3', ctypes.c_void_p)]
        pbi = PBI()
        if nt.NtQueryInformationProcess(handle, 0, ctypes.byref(pbi), ctypes.sizeof(pbi), None) != 0 or not pbi.PebBaseAddress:
            return ''

        def read(address, size):
            buffer = ctypes.create_string_buffer(size)
            got = ctypes.c_size_t(0)
            if not k32.ReadProcessMemory(handle, ctypes.c_void_p(address), buffer, size, ctypes.byref(got)) or got.value != size:
                return None
            return buffer.raw
        peb = read(pbi.PebBaseAddress, 0x28)
        if peb is None:
            return ''
        params = int.from_bytes(peb[0x20:0x28], 'little')
        block = read(params + 0x38, 16)  # CurrentDirectory.DosPath: UNICODE_STRING {Length u16, MaxLength u16, pad, Buffer ptr}
        if block is None:
            return ''
        length, pointer = int.from_bytes(block[0:2], 'little'), int.from_bytes(block[8:16], 'little')
        data = read(pointer, length) if length and pointer else None
        return data.decode('utf-16-le').rstrip(chr(92)) if data else ''
    except Exception:
        return ''
    finally:
        k32.CloseHandle(handle)


def list_processes():
    """Rows {pid, ppid, name, started (datetime), cmd} for every process (needed for the parent check)."""
    script = ("Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine,"
              "@{n='Started';e={if($_.CreationDate){$_.CreationDate.ToString('o')}else{''}}} | ConvertTo-Json -Compress")
    done = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', script], capture_output=True, timeout=60)
    raw = done.stdout.decode('utf-8', 'replace').strip()
    if not raw:
        return []
    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]
    rows = []
    for item in data:
        started = None
        match = re.match(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)', item.get('Started') or '')
        if match:  # ToString('o') is local time with an offset; the local clock is what age is compared with
            started = datetime.datetime.fromisoformat(match.group(1))
        cwd = process_cwd(int(item['ProcessId'])) if re.match(r'godot', item.get('Name') or '', re.I) else ''
        rows.append({'pid': int(item['ProcessId']), 'ppid': int(item.get('ParentProcessId') or 0), 'name': item.get('Name') or '',
                     'started': started, 'cmd': item.get('CommandLine') or '', 'cwd': cwd})
    return rows


def split_cmd(cmd):
    try:
        return shlex.split(cmd, posix=False)
    except ValueError:
        return cmd.split()


def describe(row):
    """Pure parse of one Godot command line: mode, script/scene, main arguments, project path."""
    tokens = [t.strip('"') for t in split_cmd(row['cmd'])]
    engine, user = tokens[1:], []
    if '--' in engine:
        index = engine.index('--')
        engine, user = engine[:index], engine[index + 1:]
    path = ''
    script = ''
    for index, token in enumerate(engine):
        if token == '--path' and index + 1 < len(engine):
            path = engine[index + 1]
        if token in ('--script', '-s') and index + 1 < len(engine):
            script = engine[index + 1]
    if not script:
        scenes = [t for t in engine if t.startswith('res://')]
        script = scenes[0] if scenes else ''
    keep = [u for u in user if re.match(r'--(until|dump|scene|flow-shots|chapter1-playlog|primary|shots|seed|chapter1-seed|chapter1-primary|chapter1-start|chapter1-pilot|chapter1-profile-off|chapter1-qa-ignore-focus|run-spells|burst|menu-tour|tree-shots)\b', u)]
    return {'headless': '--headless' in engine, 'script': script.replace('res://', ''), 'path': path,
            'profile_off': '--chapter1-profile-off' in user,
            'automated': '--chapter1-pilot' in user or any(u.startswith('--chapter1-quit-after') for u in user), 'import': '--import' in engine or '--version' in engine,
            'args': ' '.join(keep)[:90], 'has_window_flag': '--headless' not in engine}


def classify(row, info, by_pid, roots):
    """('tool'|'user play'|'unclear'|'foreign', reason). Only 'tool' may be ended."""
    raw_path = info['path']
    if raw_path and not re.match(r'^([A-Za-z]:|[/\\])', raw_path):
        cwd = row.get('cwd') or ''
        if not cwd:
            return 'unclear', 'relative --path and the working folder could not be read'
        raw_path = os.path.normpath(os.path.join(cwd, raw_path))
        info['path'] = raw_path
    if not raw_path:
        cwd = row.get('cwd') or ''
        if not cwd:
            return 'unclear', 'no --path and the working folder could not be read'
        raw_path = info['path'] = cwd
    path = norm(raw_path)
    in_repo = any(path == r or path.startswith(r + '/') for r in roots)
    if not in_repo:
        return 'foreign', 'project outside this repository'
    scripted = bool(info['script']) and info['script'].endswith('.gd')
    if not (info['headless'] or scripted or info['import']):
        # A plain game window: ended only when it is an automated run (pilot or wall-clock quit) with isolation. A person's play,
        # also the trial build (--chapter1-trial needs --chapter1-profile-off), has neither and is never ended.
        if not info['profile_off']:
            return 'user play', 'window run without --chapter1-profile-off'
        if not info['automated']:
            return 'user play', 'game window with profile-off but no pilot/quit-after (a person may be playing, e.g. the trial build)'
    parent = by_pid.get(row['ppid'])
    if parent is not None and not re.search(r'godot', parent['name'], re.I):
        pcmd = parent['cmd'].replace('\\', '/').lower()
        if parent['name'].lower() in ('python.exe', 'pythonw.exe', 'py.exe'):
            if not any(t in pcmd for t in TOOL_PARENTS):
                return 'unclear', 'parent is a python process that is not a dev tool'
        else:
            return 'unclear', 'parent %s (%d) is not a dev tool' % (parent['name'], parent['pid'])
    return 'tool', 'isolated/tool-style run in this repository'


def build_table(rows, now, roots):
    by_pid = {r['pid']: r for r in rows}
    table = []
    for row in rows:
        if not re.match(r'godot', row['name'], re.I):
            continue
        info = describe(row)
        kind, why = classify(row, info, by_pid, roots)
        age = (now - row['started']).total_seconds() / 60 if row['started'] else None
        parent = by_pid.get(row['ppid'])
        is_child_of_godot = parent is not None and bool(re.match(r'godot', parent['name'], re.I))
        table.append({'pid': row['pid'], 'ppid': row['ppid'], 'name': row['name'], 'started': row['started'], 'age_min': age,
                      'mode': 'headless' if info['headless'] else 'window', 'script': info['script'], 'args': info['args'],
                      'path': info['path'], 'kind': kind, 'why': why, 'child_of_godot': is_child_of_godot})
    return sorted(table, key=lambda t: t['started'] or datetime.datetime.min)


def stale_targets(table, stale_min):
    """The pids to end: 'tool' rows older than stale_min. A child whose Godot parent is also a target is covered by the tree kill."""
    chosen = [t for t in table if t['kind'] == 'tool' and t['age_min'] is not None and t['age_min'] >= stale_min]
    pids = {t['pid'] for t in chosen}
    return [t for t in chosen if t['ppid'] not in pids]


def fmt_age(minutes):
    if minutes is None:
        return '?'
    return '%dh%02dm' % (minutes // 60, minutes % 60)


def render(table):
    lines = ['%-7s %-8s %-8s %-9s %-10s %-28s %s' % ('PID', 'START', 'AGE', 'MODE', 'KIND', 'SCRIPT', 'ARGS / PROJECT')]
    for t in table:
        start = t['started'].strftime('%m-%d %H:%M') if t['started'] else '?'
        lines.append('%-7d %-8s %-8s %-9s %-10s %-28s %s' % (t['pid'], start, fmt_age(t['age_min']), t['mode'],
                     t['kind'] + ('*' if t['child_of_godot'] else ''), (t['script'] or '-')[-28:], (t['args'] + ' | ' if t['args'] else '') + (t['path'] or '?')))
    if not table:
        lines.append('(no Godot process)')
    lines.append('KIND: tool = started the tools/dev way in this repository; user play = never ended; unclear/foreign = shown only; * = engine child of a console parent')
    return '\n'.join(lines)


def main(argv=None, processes=None, killer=None, now=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--stale-min', type=float, default=None, help='only processes at least this many minutes old')
    parser.add_argument('--kill-stale', action='store_true', help='end the old tool-started processes of this repository (whole trees)')
    parser.add_argument('--dry-run', action='store_true', help='with --kill-stale: print, end nothing')
    args = parser.parse_args(argv)
    if args.stale_min is not None and args.stale_min < 0:
        print('GODOT_PS bad --stale-min', file=sys.stderr)
        return 2
    rows = list_processes() if processes is None else processes
    now = now or datetime.datetime.now()
    roots = {norm(ROOT), norm(main_root()), norm(main_root() / '.claude' / 'worktrees')}
    table = build_table(rows, now, roots)
    stale_min = args.stale_min if args.stale_min is not None else (DEFAULT_KILL_STALE_MIN if args.kill_stale else None)
    if stale_min is not None:
        table = [t for t in table if t['age_min'] is not None and t['age_min'] >= stale_min]
    print(render(table))
    if args.kill_stale:
        targets = stale_targets(table, stale_min)
        for t in targets:
            print('%s %d (%s, %s)' % ('WOULD END' if args.dry_run else 'ENDING', t['pid'], fmt_age(t['age_min']), t['script'] or t['mode']))
            if not args.dry_run:
                (killer or godot_guard.kill_tree)(t['pid'])
        print('GODOT_PS stale=%d ended=%d%s' % (len(targets), 0 if args.dry_run else len(targets), ' (dry run)' if args.dry_run else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
