"""Performance before/after measurement: alternate variants, watch foreign Godot processes, print one fixed table set.

    python tools/dev/perf_ab.py run  PLAN.json --out _local/perf/<date>-<name>        # measure (opens real windows, one at a time)
    python tools/dev/perf_ab.py run  PLAN.json --out ... --dry-run                     # print the expanded run list and commands only
    python tools/dev/perf_ab.py report _local/perf/<date>-<name> [--plan PLAN.json] [--compare a,b] [--md out.md]

What it does
  run     Expands the plan into runs (variants alternate round by round; round 0 is a warm-up that is recorded but never counted),
          starts each run as exe or editor window with chapter1/tests/perf_probe.gd, one window at a time. Before a run it waits
          (up to --wait-limit seconds) while another windowed Godot exists; during a run it samples Godot processes that are not
          its own children. Any foreign Godot, or a forced start, marks the run contaminated. CPU seconds of the busiest other
          processes are recorded at start and end. Raw output per run: <name>.json (probe), <name>.env.json (monitoring), <name>.log.
  report  Reads those files and prints the fixed tables: per run, per condition (median and min~max over clean runs), difference
          tables (other minus first variant of each block), contamination, order-drift warnings, conditions that differ from the
          official quality-target measurement.

Verdict words (the tool never writes "no effect"):
  "분리"                two conditions' min~max ranges do not overlap. A range test with few runs, not a statistical test.
  "가르지 못함"         the ranges overlap. It says the sample cannot tell the two apart, not that they are equal.
  "판정 불가"           fewer than 3 clean runs on a side.

Plan file (JSON). Either the explicit run list an earlier session wrote (a list of {name, exe, args, seconds}) or:
  {"title": "...", "seconds": 300, "resolution": "1920x1080", "late_from": 180,
   "base_args": ["--chapter1-start", "--chapter1-pilot", "--chapter1-profile-off", "--chapter1-qa-ignore-focus",
                 "--chapter1-seed=11", "--chapter1-primary=chapter1.skill.ember"],
   "variants": [{"name": "before", "exe": "C:/.../WitchMoira.exe", "rounds": 5, "warmup": true, "args": []},
                {"name": "after",  "project": "C:/.../worktree",   "rounds": 5, "warmup": true, "args": [],
                 "block": "main"}]}
  exe = exported build, project = editor run of a folder (--path; import it first), launcher = a command prefix used instead
  (test hook). Variants of one block alternate each round: r0 (warm-up), then r1..rN. Blocks run one after another.
  The probe is chapter1/tests/perf_probe.gd; an exe cannot see chapter1/tests/ (the export excludes it), so it is passed by
  absolute path. Building the exe is not done here.
"""
import argparse
import ctypes
import datetime
import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from isolated_env import isolated_env  # noqa: E402

GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))
PROBE = ROOT / 'chapter1' / 'tests' / 'perf_probe.gd'
DEFAULT_BASE_ARGS = ['--chapter1-start', '--chapter1-pilot', '--chapter1-profile-off', '--chapter1-qa-ignore-focus',
                     '--chapter1-seed=11', '--chapter1-primary=chapter1.skill.ember']
MIN_CLEAN = 3
TREND_RHO = 0.6

# (key, decimals, plain-language name). The key names are the probe-era names so old tables stay comparable.
COLS = [('p50', 2, '프레임 시간 p50(ms)'), ('p95', 2, 'p95'), ('p99', 2, 'p99'), ('max', 0, '최악(ms)'),
        ('gt50', 0, '50ms 초과 프레임 수'), ('gt100', 0, '100ms 초과'), ('n_gt300', 0, '300ms 초과(판 전체)'),
        ('late_p95', 2, '후반 p95'), ('late_mean_dt', 2, '후반 평균'),
        ('late_act', 2, '후반 적 표시'), ('late_hud', 2, '후반 HUD'), ('fxj', 2, '후반 효과+연출'), ('late_other', 2, '후반 그 밖(그리기 등)'),
        ('late_phys', 2, '후반 물리 프레임 처리'), ('tick_ms', 2, '틱 1회 비용'), ('late_nt', 2, '프레임당 틱 수'),
        ('late1_dt50', 2, '틱 1회 프레임의 중앙값'), ('late_draw', 0, '그리기 호출'), ('late_rgpu', 2, '렌더 GPU'),
        ('late_rcpu', 2, '렌더 CPU'), ('late_en', 0, '적 수'), ('final_tick', 0, '마지막 틱')]
TREND_KEYS = ['p50', 'p95', 'late_p95', 'late_mean_dt']
NAN = float('nan')


class ProbeError(Exception):
    pass


# ---------------------------------------------------------------- metrics (pure Python, no numpy)

def pct(values, q):
    """Linear-interpolated percentile (same rule as numpy's default)."""
    if not values:
        return NAN
    s = sorted(values)
    k = (len(s) - 1) * q / 100.0
    f = math.floor(k)
    c = min(f + 1, len(s) - 1)
    return s[f] + (s[c] - s[f]) * (k - f)


def mean(values):
    return sum(values) / len(values) if values else NAN


def finite(values):
    return [v for v in values if v == v]


def _col(j, key, scale=1.0, required=True):
    if key not in j:
        if required:
            raise ProbeError('probe output lacks %s' % key)
        return None
    return [float(v) / scale for v in j[key]]


def metrics(j, late_from=180.0, whole_from=10.0):
    """One run's numbers. Whole = frames from whole_from seconds on; late = frames from late_from seconds on."""
    t = _col(j, 'f_t', 1e6)
    dt = _col(j, 'f_dt', 1000.0)
    n = len(dt)
    nt = [int(v) for v in j['f_nticks']] if 'f_nticks' in j else None
    if nt is None:
        raise ProbeError('probe output lacks f_nticks')
    cols = {k: _col(j, 'f_' + k, 1000.0) for k in ('phys', 'cam', 'act', 'fx', 'juice', 'hud', 'world')}
    x = _col(j, 'f_x', 1000.0, required=False) or [0.0] * n
    raw = {k: _col(j, 'f_' + k) for k in ('draw', 'rcpu', 'rgpu', 'en')}
    for name, arr in list(cols.items()) + list(raw.items()):
        if len(arr) != n:
            raise ProbeError('column length differs: ' + name)
    other = [dt[i] - cols['phys'][i] - (cols['cam'][i] + cols['act'][i] + cols['fx'][i] + cols['juice'][i] + cols['hud'][i] + cols['world'][i]) - x[i]
             for i in range(n)]
    whole = [i for i in range(n) if t[i] >= whole_from]
    late = [i for i in range(n) if t[i] >= late_from]
    m = {'frames': len(whole), 'late_n': len(late)}
    wdt = [dt[i] for i in whole]
    ldt = [dt[i] for i in late]
    m['p50'] = pct(wdt, 50)
    m['p95'] = pct(wdt, 95)
    m['p99'] = pct(wdt, 99)
    m['max'] = max(wdt) if wdt else NAN
    m['gt50'] = sum(1 for v in wdt if v > 50)
    m['gt100'] = sum(1 for v in wdt if v > 100)
    m['n_gt300'] = sum(1 for v in dt if v > 300)
    m['late_p95'] = pct(ldt, 95)
    m['late_mean_dt'] = mean(ldt)
    for k in ('act', 'fx', 'hud', 'juice', 'phys'):
        m['late_' + k] = mean([cols[k][i] for i in late])
    m['late_other'] = mean([other[i] for i in late])
    for k in ('draw', 'rcpu', 'rgpu', 'en'):
        m['late_' + k] = mean([raw[k][i] for i in late])
    m['late_nt'] = mean([float(nt[i]) for i in late])
    m['late1_dt50'] = pct([dt[i] for i in late if nt[i] == 1], 50)
    m['fxj'] = m['late_fx'] + m['late_juice']
    kt = _col(j, 'k_t', 1e6, required=False)
    if kt is not None and all(k in j for k in ('k_pilot', 'k_step', 'k_cons', 'k_audio')):
        tot = [(float(j['k_pilot'][i]) + float(j['k_step'][i]) + float(j['k_cons'][i]) + float(j['k_audio'][i])) / 1000.0 for i in range(len(kt))]
        m['tick_ms'] = mean([tot[i] for i in range(len(kt)) if kt[i] >= late_from])
    else:
        m['tick_ms'] = NAN
    info = j.get('info', {})
    m['final_tick'] = int(info.get('final_tick', 0))
    m['seconds'] = float(info.get('seconds', 0) or 0)
    m['info'] = info
    return m


def fmt(v, nd):
    return 'n/a' if v != v else '%.*f' % (nd, v)


def summ(values):
    v = finite(values)
    if not v:
        return None
    return statistics.median(v), min(v), max(v)


def cell(s, nd):
    return 'n/a' if s is None else '%.*f (%.*f~%.*f)' % (nd, s[0], nd, s[1], nd, s[2])


def ranks(values):
    order = sorted(range(len(values)), key=lambda i: values[i])
    r = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2.0 + 1
        i = j + 1
    return r


def spearman(x, y):
    if len(x) < 3 or len(x) != len(y):
        return None
    rx, ry = ranks(x), ranks(y)
    mx, my = mean(rx), mean(ry)
    sxx = sum((a - mx) ** 2 for a in rx)
    syy = sum((b - my) ** 2 for b in ry)
    if sxx == 0 or syy == 0:
        return None
    return sum((a - mx) * (b - my) for a, b in zip(rx, ry)) / math.sqrt(sxx * syy)


# ---------------------------------------------------------------- plan

RUN_NAME = re.compile(r'^(?P<v>.+)-r(?P<r>\d+)$')


def split_name(name):
    m = RUN_NAME.match(name)
    if not m:
        return name, 0
    return m.group('v'), int(m.group('r'))


def expand_plan(plan):
    """Plan (list or dict) -> list of run dicts in execution order, each with name, variant, round, warmup, block, args, seconds, target."""
    if isinstance(plan, list):  # explicit run list from earlier sessions
        runs, sigs = [], []
        for order, it in enumerate(plan):
            variant, rnd = split_name(it['name'])
            sig = tuple(sorted(it.get('args', [])))
            if sig not in sigs:
                sigs.append(sig)
            run = dict(it)
            run.update(variant=variant, round=rnd, warmup=(rnd == 0), block='block%d' % (sigs.index(sig) + 1), order=order,
                       seconds=it.get('seconds', 300), args=list(it.get('args', [])), base_args=it.get('base_args', DEFAULT_BASE_ARGS),
                       resolution=it.get('resolution', '1920x1080'))
            runs.append(run)
        return runs
    base_args = plan.get('base_args', DEFAULT_BASE_ARGS)
    variants = plan.get('variants', [])
    if not variants:
        raise ValueError('plan has no variants')
    names = [v['name'] for v in variants]
    if len(set(names)) != len(names):
        raise ValueError('variant names must be unique')
    block_order, blocks = [], {}
    for v in variants:
        if not any(k in v for k in ('exe', 'project', 'launcher')):
            raise ValueError('variant %s needs exe, project or launcher' % v['name'])
        b = v.get('block', 'main')
        if b not in blocks:
            blocks[b] = []
            block_order.append(b)
        blocks[b].append(v)
    runs = []
    for b in block_order:
        vs = blocks[b]
        top = max([int(v.get('rounds', plan.get('rounds', 5))) for v in vs] + [0])
        first = 0 if any(v.get('warmup', plan.get('warmup', True)) for v in vs) else 1
        for r in range(first, top + 1):
            for v in vs:
                rounds = int(v.get('rounds', plan.get('rounds', 5)))
                warm = bool(v.get('warmup', plan.get('warmup', True)))
                if (r == 0 and warm) or 1 <= r <= rounds:
                    run = {k: v[k] for k in ('exe', 'project', 'launcher', 'probe', 'label') if k in v}
                    run.update(name='%s-r%d' % (v['name'], r), variant=v['name'], round=r, warmup=(r == 0), block=b,
                               args=list(v.get('args', [])), seconds=int(v.get('seconds', plan.get('seconds', 300))), base_args=list(v.get('base_args', base_args)),
                               resolution=plan.get('resolution', '1920x1080'), order=len(runs))
                    runs.append(run)
    return runs


def probe_script_for(run):
    if run.get('probe'):
        return str(run['probe']).replace('\\', '/')
    if 'project' in run:
        local = Path(run['project']) / 'chapter1' / 'tests' / 'perf_probe.gd'
        if local.is_file():
            return 'res://chapter1/tests/perf_probe.gd'
    return str(PROBE).replace('\\', '/')


def build_command(run, out_json):
    if 'launcher' in run:
        cmd = list(run['launcher'])
    elif 'exe' in run:
        cmd = [str(run['exe'])]
    else:
        cmd = [str(GODOT), '--path', str(run['project'])]
    cmd += ['--resolution', run.get('resolution', '1920x1080'), '--script', probe_script_for(run), '--']
    cmd += list(run['base_args']) + list(run['args'])
    cmd += ['--probe-seconds=%d' % int(run['seconds']), '--probe-out=' + str(out_json).replace('\\', '/')]
    return cmd


# ---------------------------------------------------------------- process monitoring (Windows)

class _PE32(ctypes.Structure):
    _fields_ = [('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD), ('th32ProcessID', wintypes.DWORD),
                ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', wintypes.DWORD), ('cntThreads', wintypes.DWORD),
                ('th32ParentProcessID', wintypes.DWORD), ('pcPriClassBase', ctypes.c_long), ('dwFlags', wintypes.DWORD),
                ('szExeFile', ctypes.c_wchar * 260)]


def process_table():
    """[(pid, parent pid, exe name)] for every process; a cheap toolhelp snapshot (no child process is started)."""
    k32 = ctypes.windll.kernel32
    k32.CreateToolhelp32Snapshot.restype = ctypes.c_void_p
    k32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    k32.Process32FirstW.argtypes = [ctypes.c_void_p, ctypes.POINTER(_PE32)]
    k32.Process32NextW.argtypes = [ctypes.c_void_p, ctypes.POINTER(_PE32)]
    k32.CloseHandle.argtypes = [ctypes.c_void_p]
    h = k32.CreateToolhelp32Snapshot(2, 0)
    if h in (None, -1, 0xFFFFFFFFFFFFFFFF):
        raise OSError('toolhelp snapshot failed')
    out = []
    try:
        e = _PE32()
        e.dwSize = ctypes.sizeof(_PE32)
        ok = k32.Process32FirstW(h, ctypes.byref(e))
        while ok:
            out.append((int(e.th32ProcessID), int(e.th32ParentProcessID), e.szExeFile))
            ok = k32.Process32NextW(h, ctypes.byref(e))
    finally:
        k32.CloseHandle(h)
    return out


def descendants(table, root_pid):
    kids = {}
    for pid, ppid, _ in table:
        kids.setdefault(ppid, []).append(pid)
    seen, stack = {root_pid}, [root_pid]
    while stack:
        for c in kids.get(stack.pop(), []):
            if c not in seen:
                seen.add(c)
                stack.append(c)
    return seen


def is_godot_name(name):
    n = name.lower()
    return n.startswith('godot') or n.startswith('witchmoira')


def foreign_godots(own_root_pid):
    table = process_table()
    mine = descendants(table, own_root_pid) if own_root_pid else set()
    mine.add(os.getpid())
    return [(pid, name) for pid, _, name in table if is_godot_name(name) and pid not in mine]


def _ps(command):
    r = subprocess.run(['powershell', '-NoProfile', '-Command', command], capture_output=True, text=True, encoding='utf-8', errors='replace')
    text = r.stdout.strip()
    if not text:
        return []
    d = json.loads(text)
    return [d] if isinstance(d, dict) else d


def godot_command_lines():
    """{pid: command line} of every Godot/WitchMoira process (one PowerShell call; used before a run, never during)."""
    try:
        rows = _ps("Get-CimInstance Win32_Process -Filter \"Name like 'Godot%' or Name like 'WitchMoira%'\" | "
                   "Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress")
    except Exception:
        return {}
    return {int(r['ProcessId']): (r.get('CommandLine') or '') for r in rows}


def cpu_snapshot():
    try:
        rows = _ps('Get-Process | Sort-Object CPU -Descending | Select-Object -First 25 Id,ProcessName,CPU | ConvertTo-Json -Compress')
        return {int(r['Id']): (r['ProcessName'], float(r['CPU'] or 0.0)) for r in rows}
    except Exception:
        return {}


# ---------------------------------------------------------------- run

def now():
    return datetime.datetime.now().isoformat(timespec='seconds')


class Log:
    def __init__(self, path):
        self.path = path

    def __call__(self, msg):
        line = '%s %s' % (now(), msg)
        print(line, flush=True)
        with open(self.path, 'a', encoding='utf-8', newline='\n') as f:
            f.write(line + '\n')


def kill_tree(pid):
    subprocess.run(['taskkill', '/T', '/F', '/PID', str(pid)], capture_output=True)


def run_one(run, out, opts, log):
    name = run['name']
    out_json = out / (name + '.json')
    cmd = build_command(run, out_json)
    t0 = time.time()
    pre_cmd = godot_command_lines()
    waited, forced = [], False
    while True:
        windowed = [(pid, c) for pid, c in pre_cmd.items() if '--headless' not in c and pid != os.getpid()]
        if not windowed or opts.no_wait:
            break
        waited.append({'t': now(), 'procs': [(pid, c[:160]) for pid, c in windowed]})
        log('wait %s: %d foreign windowed godot: %s' % (name, len(windowed), ', '.join(str(p) for p, _ in windowed)))
        if time.time() - t0 >= opts.wait_limit:
            forced = True
            log('wait limit reached for %s; starting anyway (forced)' % name)
            break
        time.sleep(opts.wait_poll)
        pre_cmd = godot_command_lines()
    env = {'name': name, 'variant': run['variant'], 'round': run['round'], 'warmup': run['warmup'], 'block': run['block'],
           'args': run['args'], 'cmd': cmd, 'waited': waited, 'forced': forced, 'start': now(), 'foreign_events': [],
           'pre_foreign': [(pid, c[:200]) for pid, c in pre_cmd.items()], 'monitor': 'toolhelp'}
    c0 = cpu_snapshot()
    log('start %s %s' % (name, ' '.join(run['args'])))
    logf = open(out / (name + '.log'), 'w', encoding='utf-8')
    p = subprocess.Popen(cmd, stdout=logf, stderr=subprocess.STDOUT, env=isolated_env('perf-ab'))
    seen = set()
    started = time.time()
    limit = float(run['seconds']) * 1.5 + 180
    while p.poll() is None:
        try:
            fresh = [(pid, pname) for pid, pname in foreign_godots(p.pid) if pid not in seen]
            for pid, pname in fresh:
                seen.add(pid)
                env['foreign_events'].append({'t': now(), 'pid': pid, 'name': pname, 'cmd': pre_cmd.get(pid, '')[:300]})
            if fresh:
                log('FOREIGN Godot during %s: %d new process(es) %s' % (name, len(fresh), _count_names([{'name': n} for _, n in fresh])))
        except Exception as e:  # monitoring must never end a run
            env['monitor'] = 'failed: %s' % e
        if time.time() - started > limit:
            env['timed_out'] = True
            log('timeout for %s after %.0fs; killing only this run\'s process tree' % (name, time.time() - started))
            kill_tree(p.pid)
            break
        time.sleep(opts.poll)
    p.wait()
    c1 = cpu_snapshot()
    logf.close()
    env['exit'] = p.returncode
    env['end'] = now()
    env['wall_s'] = round(time.time() - t0, 1)
    env['contaminated'] = bool(env['foreign_events']) or forced
    top = sorted(((round(c1[pid][1] - c0[pid][1], 1), nm, pid) for pid, (nm, _) in c0.items() if pid in c1 and c1[pid][0] == nm), reverse=True)
    env['cpu_delta_top'] = [list(x) for x in top[:8]]
    env['probe_json'] = out_json.is_file()
    (out / (name + '.env.json')).write_text(json.dumps(env, indent=1, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')
    log('end %s exit=%s json=%s contaminated=%s cpu_top=%s' % (name, env['exit'], env['probe_json'], env['contaminated'], top[:3]))


def under_local(path):
    try:
        Path(path).resolve().relative_to((ROOT / '_local').resolve())
        return True
    except ValueError:
        return False


def cmd_run(args):
    plan = json.loads(Path(args.plan).read_text(encoding='utf-8'))
    runs = expand_plan(plan)
    if args.only:
        wanted = set(args.only.split(','))
        runs = [r for r in runs if r['name'] in wanted]
    out = Path(args.out)
    if args.dry_run:
        for r in runs:
            print('%-14s block=%s warmup=%s' % (r['name'], r['block'], r['warmup']))
            print('   ' + ' '.join(build_command(r, out / (r['name'] + '.json'))))
        print('%d runs' % len(runs))
        return 0
    if not under_local(out):
        print('--out must be under %s' % (ROOT / '_local'), file=sys.stderr)
        return 2
    if out.exists() and any(out.iterdir()) and not args.resume:
        print('--out already holds files: raw results are kept, use a new folder (or --resume to continue this one)', file=sys.stderr)
        return 2
    for r in runs:
        if 'launcher' not in r and 'exe' in r and not Path(r['exe']).is_file():
            print('exe not found: %s' % r['exe'], file=sys.stderr)
            return 2
        if 'project' in r and not (Path(r['project']) / 'project.godot').is_file():
            print('not a Godot project folder: %s' % r['project'], file=sys.stderr)
            return 2
    if 'launcher' not in runs[0] and any('project' in r for r in runs) and not GODOT.is_file():
        print('Godot not found: %s (set MOIRA_GODOT)' % GODOT, file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / 'plan.json').write_text(json.dumps(plan, indent=1, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')
    log = Log(out / 'orchestrator.log')
    log('plan %s: %d runs (variants alternate by round)' % (args.plan, len(runs)))
    for r in runs:
        if args.resume and (out / (r['name'] + '.env.json')).is_file():
            log('skip %s (already measured)' % r['name'])
            continue
        run_one(r, out, args, log)
    log('PLAN DONE')
    text = build_report(out, plan=plan, late_from=args.late_from)
    (out / 'report.md').write_text(text, encoding='utf-8', newline='\n')
    print(text)
    return 0


# ---------------------------------------------------------------- report

def load_run(runs_dir, run, late_from):
    r = dict(run)
    jp = Path(runs_dir) / (run['name'] + '.json')
    ep = Path(runs_dir) / (run['name'] + '.env.json')
    r['env'] = json.loads(ep.read_text(encoding='utf-8')) if ep.is_file() else None
    r['m'] = None
    r['error'] = ''
    if jp.is_file():
        try:
            r['m'] = metrics(json.loads(jp.read_text(encoding='utf-8')), late_from)
        except (ProbeError, ValueError, KeyError) as e:
            r['error'] = 'probe output unreadable: %s' % e
    else:
        r['error'] = 'no probe output'
    r['contaminated'] = bool(r['env'] and r['env'].get('contaminated'))
    return r


def discover(runs_dir):
    runs = []
    for p in sorted(Path(runs_dir).glob('*.json')):
        if p.name.endswith('.env.json') or p.name in ('plan.json', 'runs.json'):
            continue
        name = p.name[:-5]
        if not RUN_NAME.match(name):
            continue
        v, rnd = split_name(name)
        runs.append({'name': name, 'variant': v, 'round': rnd, 'warmup': rnd == 0, 'block': 'all', 'args': [], 'seconds': 0, 'base_args': []})
    for i, r in enumerate(sorted(runs, key=lambda r: (r['round'], r['name']))):
        r['order'] = i
    return runs


def verdict(ref, other, a, b):
    """a, b = lists of clean-run values of the first variant and the other."""
    a, b = finite(a), finite(b)
    if len(a) < MIN_CLEAN or len(b) < MIN_CLEAN:
        return '판정 불가(표본 %d/%d, 최소 %d)' % (len(a), len(b), MIN_CLEAN)
    if max(b) < min(a) or min(b) > max(a):
        word = '낮음' if max(b) < min(a) else '높음'
        weak = ', 약한 증거(표본 5 미만)' if min(len(a), len(b)) < 5 else ''
        return '분리(%s 쪽이 %s, 표본 %d/%d%s)' % (other, word, len(a), len(b), weak)
    return '가르지 못함(범위 겹침, 표본 %d/%d)' % (len(a), len(b))


def official_notes(runs, loaded):
    notes = []
    plan_runs = [r for r in runs if not r.get('synthetic')]
    kinds = {('exe' if 'exe' in r else 'project' if 'project' in r else 'launcher' if 'launcher' in r else '?') for r in runs}
    if 'project' in kinds:
        notes.append('에디터(프로젝트 폴더) 실행이 있다: 공식 측정은 실행 빌드(exe)다')
    if kinds == {'?'}:
        notes.append('계획 파일이 없어 빌드 종류를 알 수 없다(프로브 출력의 debug_build 값만 믿는다)')
    infos = [r['m']['info'] for r in loaded if r['m']]
    if any(i.get('debug_build') for i in infos):
        notes.append('디버그 빌드로 실행된 회차가 있다(info.debug_build=true)')
    if any('--chapter1-qa-ignore-focus' in (r.get('base_args', []) + r.get('args', [])) for r in runs):
        notes.append('--chapter1-qa-ignore-focus 사용: 포커스 상태의 측정이 아니라 자동 조작 창 측정이다')
    elif plan_runs and not any('--chapter1-pilot' in (r.get('base_args', []) + r.get('args', [])) for r in runs):
        pass
    samples = [s for i in infos for s in i.get('focus_samples', [])]
    if samples:
        notes.append('프로브가 기록한 창 포커스 표본: %d/%d' % (sum(samples), len(samples)))
    sizes = {tuple(i.get('window_size', [])) for i in infos if i.get('window_size')} | {tuple(i.get('display_window_size', [])) for i in infos if i.get('display_window_size')}
    if sizes and sizes != {(1920, 1080)}:
        notes.append('창 크기가 1920x1080이 아니다: %s' % sorted(sizes))
    xs = [r['name'] for r in runs if any(a.startswith('--x-') for a in r.get('args', []))]
    if xs:
        notes.append('실험 스위치(--x-*)가 있는 회차가 있다: 출시 게임의 측정이 아니다 (%s)' % ', '.join(xs[:4]))
    counted = {}
    for r in runs:
        if not r['warmup']:
            counted[r['variant']] = counted.get(r['variant'], 0) + 1
    low = [v for v, c in counted.items() if c < MIN_CLEAN]
    if low:
        notes.append('센 회차가 %d 미만인 조건: %s' % (MIN_CLEAN, ', '.join(low)))
    if not any(r['warmup'] for r in runs):
        notes.append('예열 회차가 없다')
    days = {(r['env'] or {}).get('start', '')[:10] for r in loaded if r['env']}
    days.discard('')
    if len(days) > 1:
        notes.append('회차의 날짜가 서로 다르다(%s): 통제 비교가 아니다' % ', '.join(sorted(days)))
    notes.append('프로브가 수직동기를 끈다(VSYNC_DISABLED): 게임 기본 설정과 다를 수 있다')
    return notes


def _count_names(events):
    counts = {}
    for e in events:
        n = e.get('name') or e.get('cmd', '')[:60]
        counts[n] = counts.get(n, 0) + 1
    return ', '.join('%s x%d' % kv for kv in counts.items()) or '-'


def trend_warnings(clean_runs):
    out = []
    ordered = sorted(clean_runs, key=lambda r: r['order'])
    if len(ordered) < 4:
        return out
    for key in TREND_KEYS:
        xs = list(range(len(ordered)))
        ys = [r['m'][key] for r in ordered]
        if any(y != y for y in ys):
            continue
        rho = spearman(xs, ys)
        if rho is not None and abs(rho) >= TREND_RHO and len(ordered) >= 6:
            out.append('%s: 회차 순서와 같이 %s(순위상관 %+.2f, n=%d). 바깥 부하·열 표류일 수 있다. 번갈아 실행해 두 조건에 같이 걸리지만 조건별 범위가 넓어져 작은 차이는 가르지 못한다.' %
                       (key, '내려감' if rho < 0 else '올라감', rho, len(ordered)))
        by = {}
        for r in ordered:
            by.setdefault(r['variant'], []).append(r)
        for v, rs in by.items():
            if len(rs) >= 4:
                rv = spearman(list(range(len(rs))), [r['m'][key] for r in rs])
                if rv is not None and abs(rv) >= 0.8 and not (rho is not None and abs(rho) >= TREND_RHO and len(ordered) >= 6):
                    out.append('%s, 조건 %s만: 회차 순서와 %s(순위상관 %+.2f, n=%d)' % (key, v, '내려감' if rv < 0 else '올라감', rv, len(rs)))
    return out


def build_report(runs_dir, plan=None, compares=None, late_from=180.0):
    if plan is not None:
        runs = expand_plan(plan)
        title = plan.get('title', '') if isinstance(plan, dict) else ''
        late_from = plan.get('late_from', late_from) if isinstance(plan, dict) else late_from
        by_name = {r['name'] for r in runs}
        extra = [r for r in discover(runs_dir) if r['name'] not in by_name]
        for e in extra:
            e['order'] = len(runs)
            runs.append(e)
    else:
        runs, title = discover(runs_dir), ''
    loaded = [load_run(runs_dir, r, late_from) for r in runs]
    # blocks: from compares, else from the plan, else everything in one block
    blocks = {}
    if compares:
        for c in compares:
            blocks['/'.join(c)] = list(c)
    else:
        for r in loaded:
            blocks.setdefault(r['block'], [])
            if r['variant'] not in blocks[r['block']]:
                blocks[r['block']].append(r['variant'])
    L = []
    P = L.append
    P('# 성능 전후 측정 보고' + (' — ' + title if title else ''))
    P('')
    P('측정 폴더: `%s`. 후반 구간 = %g초 이후, 판 전체 = 10초 이후. 시간 단위 ms. 예열(r0)은 표에 보이되 센 값에서 뺀다. 오염 회차도 센 값에서 뺀다.' % (str(runs_dir).replace('\\', '/'), late_from))
    P('')
    P('## 조건(공식 측정과 다른 점)')
    for n in official_notes(runs, loaded):
        P('- ' + n)
    P('- 이 표가 말하지 않는 것: 구성 요소별 원인(켜고 끄기), 실제 출력 픽셀, 소리, 사람이 느끼는 끊김.')
    P('')
    P('열: ' + ', '.join('%s=%s' % (k, label) for k, _, label in COLS) + '.')
    P('')
    for bname, variants in blocks.items():
        P('## 비교 묶음 `%s`: %s' % (bname, ' / '.join(variants)))
        P('')
        block_runs = [r for r in loaded if r['variant'] in variants]
        for v in variants:
            P('### %s (회차별)' % v)
            P('')
            P('| 회차 | ' + ' | '.join(k for k, _, _ in COLS) + ' | 오염 |')
            P('|---|' + '---|' * (len(COLS) + 1))
            for r in sorted([x for x in block_runs if x['variant'] == v], key=lambda x: x['round']):
                if r['m'] is None:
                    P('| r%d | ' % r['round'] + ' | '.join('-' for _ in COLS) + ' | %s |' % r['error'])
                    continue
                note = '예열(제외)' if r['warmup'] else ('**오염**' if r['contaminated'] else '')
                if r['env'] is None:
                    note = (note + ' 감시 기록 없음').strip()
                if r['m']['late_n'] == 0:
                    note = (note + ' 후반 구간 없음').strip()
                elif r['m']['seconds'] and r['m']['final_tick'] < 0.9 * r['m']['seconds'] * 60:
                    note = (note + ' 일찍 끝남(마지막 틱 %d)' % r['m']['final_tick']).strip()
                P('| r%d | ' % r['round'] + ' | '.join(fmt(r['m'][k], nd) for k, nd, _ in COLS) + ' | %s |' % note)
            P('')
        clean = {v: [r for r in block_runs if r['variant'] == v and not r['warmup'] and not r['contaminated'] and r['m'] is not None and r['m']['late_n'] > 0] for v in variants}
        P('### 조건별 중앙값(최소~최대) — 예열·오염 제외')
        P('')
        P('| 조건 | n | ' + ' | '.join(k for k, _, _ in COLS) + ' |')
        P('|---|---|' + '---|' * len(COLS))
        for v in variants:
            rs = clean[v]
            P('| %s | %d | ' % (v, len(rs)) + ' | '.join(cell(summ([r['m'][k] for r in rs]), nd) for k, nd, _ in COLS) + ' |')
        P('')
        ref = variants[0]
        for other in variants[1:]:
            P('### 차이: %s − %s (중앙값 차; 두 범위가 겹치면 가르지 못함)' % (other, ref))
            P('')
            P('| 지표 | %s | %s | 차 | 판정 |' % (ref, other))
            P('|---|---|---|---|---|')
            sep, undecided = [], 0
            for k, nd, _ in COLS:
                a = [r['m'][k] for r in clean[ref]]
                b = [r['m'][k] for r in clean[other]]
                sa, sb = summ(a), summ(b)
                dtxt = '%+.*f' % (nd, sb[0] - sa[0]) if sa and sb else 'n/a'
                vd = verdict(ref, other, a, b)
                if vd.startswith('분리'):
                    sep.append('%s %s' % (k, dtxt))
                if vd.startswith('판정 불가'):
                    undecided += 1
                P('| %s | %s | %s | %s | %s |' % (k, cell(sa, nd), cell(sb, nd), dtxt, vd))
            P('')
            P('요약: %d개 지표 중 분리 %d개%s, 판정 불가 %d개, 나머지는 가르지 못함. 분리는 두 범위가 겹치지 않았다는 뜻이다(범위 검정, 통계 검정이 아님). 가르지 못함은 차이가 없다는 뜻이 아니다.' %
              (len(COLS), len(sep), (' (' + ', '.join(sep) + ')') if sep else '', undecided))
            P('')
        pooled = [r for v in variants for r in clean[v]]
        tw = trend_warnings(pooled)
        P('### 회차 순서에 따른 추세')
        P('')
        if tw:
            for t in tw:
                P('- 경고 ' + t)
        else:
            P('- 경고 없음(순위상관 기준 %.1f, 표본 6 이상일 때). 표본이 적으면 추세를 볼 수 없다.' % TREND_RHO)
        P('')
    P('## 오염·정지 흔적')
    P('')
    any_flag = False
    for r in loaded:
        if r['m'] is None:
            P('- %s: %s' % (r['name'], r['error']))
            any_flag = True
            continue
        env = r['env'] or {}
        if r['contaminated'] or r['m']['n_gt300'] > 0 or r['m']['max'] > 300 or env.get('timed_out') or env.get('exit') not in (None, 0):
            any_flag = True
            P('- %s: 오염=%s 강제 시작=%s 다른 Godot 프로세스=%s 300ms 초과 %d회 최악 %.0fms 종료 코드=%s%s' % (
                r['name'], r['contaminated'], env.get('forced'), _count_names(env.get('foreign_events', [])),
                r['m']['n_gt300'], r['m']['max'], env.get('exit'), ' 시간 초과로 끝냄' if env.get('timed_out') else ''))
    if not any_flag:
        P('- 없음')
    P('')
    P('## 회차별 다른 프로세스 CPU(초 증가, 상위 3)')
    P('')
    for r in loaded:
        env = r['env'] or {}
        if env:
            P('- %s 벽시계 %ss: %s' % (r['name'], env.get('wall_s'), env.get('cpu_delta_top', [])[:3]))
    P('')
    return '\n'.join(L)


def cmd_report(args):
    d = Path(args.runs_dir)
    plan = None
    plan_path = Path(args.plan) if args.plan else d / 'plan.json'
    if plan_path.is_file():
        plan = json.loads(plan_path.read_text(encoding='utf-8'))
    compares = [c.split(',') for c in args.compare] if args.compare else None
    text = build_report(d, plan=plan, compares=compares, late_from=args.late_from)
    if args.md:
        if not under_local(args.md):
            print('--md must be under %s' % (ROOT / '_local'), file=sys.stderr)
            return 2
        Path(args.md).parent.mkdir(parents=True, exist_ok=True)
        Path(args.md).write_text(text, encoding='utf-8', newline='\n')
    print(text)
    return 0


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run', help='measure: alternate variants, one window at a time')
    r.add_argument('plan')
    r.add_argument('--out', required=True, help='new folder under _local/ for raw output')
    r.add_argument('--dry-run', action='store_true')
    r.add_argument('--resume', action='store_true', help='continue a folder: skip runs that already have an env file')
    r.add_argument('--only', default='', help='comma-separated run names')
    r.add_argument('--wait-limit', type=float, default=600, help='seconds to wait for another windowed Godot before forcing (default 600)')
    r.add_argument('--wait-poll', type=float, default=60)
    r.add_argument('--no-wait', action='store_true', help='do not wait for foreign windowed Godot (it is still recorded)')
    r.add_argument('--poll', type=float, default=2.0, help='foreign process sampling interval during a run')
    r.add_argument('--late-from', type=float, default=180.0)
    q = sub.add_parser('report', help='print the fixed tables from raw output')
    q.add_argument('runs_dir')
    q.add_argument('--plan', default='')
    q.add_argument('--compare', action='append', help='variants to compare, first is the reference: a,b (repeatable)')
    q.add_argument('--late-from', type=float, default=180.0)
    q.add_argument('--md', default='')
    args = ap.parse_args(argv)
    return cmd_run(args) if args.cmd == 'run' else cmd_report(args)


if __name__ == '__main__':
    sys.exit(main())
