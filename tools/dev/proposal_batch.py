"""Morning capture of the screen proposals in one go (docs/SCREEN-DESIGN-HARNESS.ko.md 6 T-2/T-3/T-5; it replaces the
"commands to run in the morning" of _local/ui/growth-proposals/REPORT.txt and _local/ui/title-proposals/REPORT.txt 6).

    python tools/dev/proposal_batch.py --dry-run                  # list the jobs, run nothing
    python tools/dev/proposal_batch.py                            # everything, both resolutions
    python tools/dev/proposal_batch.py --only title/a --res 1920x1080 --kinds still,strip-intro
    python tools/dev/proposal_batch.py --list-kinds

Needs a REAL WINDOW (a desktop that is awake): every job starts one Godot window process through tools/dev/godot.py
(--fixed-fps 60, --timeout-s, isolated APPDATA, --chapter1-profile-off). A window that does not answer is ended by the
time limit and the batch goes on to the next job. Jobs run one after the other (one window at a time). It never
touches the user's save and writes under _local/shots/ only.

Matrix: proposal x job kind x resolution. Proposals are those below (PROPOSALS). Job kinds:
  still            the settled screen of every fixture            (<fixture>.<W>x<H>.png + .json layout dump)
  still-title      title/c only: the title state                  (<fixture>.title.<W>x<H>.png)
  strip-<kind>     0.05 s contact sheet: intro, focus, confirm, reduced (title proposals), title (title/c)
  strip            the older intro -> focus -> confirm sheet (growth proposals, --strip-step=3)
  input            synthetic key events (T-5)
  reduce           growth proposals: the reduced-motion intro
Then, when stills were taken: hud_layout_check.py on the layout dumps and the contrast check of
screen_contract_check.py (--layout-dump) on the same dumps; both are read-outs, they do not stop the batch.

Result: a table on screen, <out>/batch.json and <out>/batch.txt (job, resolution, exit code, seconds, files written,
PROPOSAL_* lines seen, SCRIPT ERROR count, verdict ok/failed/timeout), one log per job in <out>/logs/. Exit 1 when a job failed.
A job "ok" means: the process ended with exit 0, no SCRIPT ERROR, and it wrote the files it should. It does NOT mean the picture is good:
nobody has looked at it. Looking is the art-lead's and the director's.
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GODOT_PY = HERE / 'godot.py'
SLOT = ['slot_frost_normal', 'slot_frost_scarce', 'slot_frost_fated', 'slot_frost_first', 'slot_ember_normal', 'slot_ember_scarce',
        'slot_ember_fated', 'slot_ember_pity', 'slot_arc_normal', 'slot_arc_scarce', 'slot_arc_fated', 'slot_long']
SLOT_STRIP = ['slot_frost_fated', 'slot_ember_fated', 'slot_arc_fated', 'slot_ember_pity', 'slot_frost_normal', 'slot_ember_normal', 'slot_arc_normal', 'slot_frost_scarce']
TITLE_FIX = ['normal', 'long', 'fresh', 'profile_off', 'points_many', 'focus_ember', 'focus_storm', 'no_devil', 'devil_shade']
RES = ['1920x1080', '1280x720']

# proposal -> {prefix, fixtures for stills, fixtures for strips and input, kinds it supports}
PROPOSALS = {
    'growth_choice/e_hand': {'prefix': None, 'still': SLOT, 'strip': ['slot_ember_fated', 'slot_frost_fated', 'slot_arc_fated', 'slot_frost_normal', 'slot_long'], 'input': ['slot_frost_normal', 'slot_frost_fated'], 'reduce': ['slot_ember_fated'],
                             'kinds': ['still', 'strip-intro', 'strip-focus', 'strip-confirm', 'input', 'reduce'], 'strip_res': ['1920x1080']},
    'title/a': {'prefix': 'title_v0', 'still': TITLE_FIX, 'strip': ['normal', 'focus_ember', 'focus_storm'], 'input': ['normal'],
                'kinds': ['still', 'strip-intro', 'strip-focus', 'strip-confirm', 'strip-reduced', 'input'], 'strip_res': ['1920x1080']},
    'title/c': {'prefix': 'title_v0', 'still': TITLE_FIX, 'strip': ['normal', 'focus_ember', 'focus_storm'], 'input': ['normal'],
                'kinds': ['still', 'still-title', 'strip-title', 'strip-intro', 'strip-focus', 'strip-confirm', 'strip-reduced', 'input'], 'strip_res': ['1920x1080']},
}
OLD = {}
ALL_KINDS = ['still', 'still-title', 'strip', 'strip-intro', 'strip-focus', 'strip-confirm', 'strip-reduced', 'strip-title', 'input', 'reduce']


def jobs_for(name, spec, kinds, resolutions):
    """[(kind, resolution, fixtures, extra args, expected file patterns)] for one proposal."""
    out = []
    short = name.split('/')[1]
    for kind in spec['kinds']:
        if kinds and kind not in kinds:
            continue
        if kind in ('still', 'still-title'):
            fixtures, res = spec['still'], resolutions
        elif kind == 'input':
            fixtures, res = spec['input'], [r for r in resolutions if r in spec['strip_res']] or resolutions[:1]
        elif kind == 'reduce':
            fixtures, res = spec['reduce'], [r for r in resolutions if r in spec['strip_res']] or resolutions[:1]
        else:
            fixtures, res = spec['strip'], [r for r in resolutions if r in spec['strip_res']]
        if not fixtures:
            continue
        for r in res:
            extra, files = [], []
            if kind == 'still':
                files = ['%s.%s.png' % (f, r) for f in fixtures]
            elif kind == 'still-title':
                extra = ['--stage=title']
                files = ['%s.title.%s.png' % (f, r) for f in fixtures]
            elif kind == 'strip':
                extra = ['--strip', '--strip-step=3']
                files = ['strip-%s.%s.png' % (f, r) for f in fixtures]
            elif kind.startswith('strip-'):
                k = kind.split('-', 1)[1]
                extra = ['--strip-kind=' + k, '--strip-step=3']
                files = ['strip-%s-%s.%s.png' % (k, f, r) for f in fixtures]
            elif kind == 'input':
                extra = ['--input-test']
            elif kind == 'reduce':
                extra = ['--reduce-motion']
                files = ['%s.%s.png' % (f, r) for f in fixtures]
            out.append({'proposal': name, 'short': short, 'kind': kind, 'res': r, 'fixtures': fixtures, 'extra': extra, 'files': files, 'prefix': spec['prefix']})
    return out


def shots_dir(out, job):
    # input tests and reduced stills must not overwrite the normal stills
    sub = job['short'] + ('-input' if job['kind'] == 'input' else '-reduce' if job['kind'] == 'reduce' else '')
    return out / sub


def command(job, out, timeout):
    args = [sys.executable, str(GODOT_PY), '--timeout-s=%d' % timeout, '--fixed-fps', '60', '--resolution', job['res'], '--path', str(ROOT),
            '--script', 'res://chapter1/tests/proposal_shot.gd', '--', '--chapter1-profile-off', '--proposal=' + job['proposal'],
            '--fixtures=' + ','.join(job['fixtures']), '--shots=' + shots_dir(out, job).resolve().as_posix()]
    if job['prefix']:
        args.append('--fixture-prefix=' + job['prefix'])
    return args + job['extra'] + job.get('game_args', [])


def run_job(job, out, timeout, logs):
    d = shots_dir(out, job)
    d.mkdir(parents=True, exist_ok=True)
    cmd = command(job, out, timeout)
    log = logs / ('%s.%s.%s.log' % (job['short'], job['kind'], job['res']))
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout + 120)
        text, code = p.stdout + p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        text, code = ((e.stdout or '') if isinstance(e.stdout, str) else '') + '\nBATCH_TIMEOUT', -999
    secs = time.time() - t0
    log.write_text(text, encoding='utf-8', newline='\n')
    errors = len(re.findall(r'SCRIPT ERROR|Parse Error|Compile Error', text))
    missing = [f for f in job['files'] if not (d / f).is_file()]
    lines = len(re.findall(r'^PROPOSAL_SHOT', text, re.M))
    if code == -999 or 'GODOT_TIMEOUT' in text:
        verdict = 'timeout'
    elif code != 0 or errors or missing:
        verdict = 'failed'
    else:
        verdict = 'ok'
    return {'proposal': job['proposal'], 'kind': job['kind'], 'res': job['res'], 'fixtures': len(job['fixtures']), 'exit': code, 'seconds': round(secs, 1),
            'files_missing': missing, 'proposal_lines': lines, 'script_errors': errors, 'verdict': verdict, 'log': log.as_posix(), 'shots': d.as_posix()}


def readouts(out, results):
    """hud_layout_check and the contrast check on the layout dumps the stills wrote. Read-outs only."""
    notes = {}
    dumps = sorted(p.as_posix() for r in results if r['kind'] in ('still', 'still-title') and r['verdict'] == 'ok' for p in Path(r['shots']).glob('*.json'))
    dumps = sorted(set(dumps))
    if not dumps:
        return {'layout': 'no layout dumps (no still job succeeded)', 'contrast': 'no layout dumps'}
    for name, cmd in (('layout', [sys.executable, str(HERE / 'hud_layout_check.py')] + dumps + ['--json', (out / 'layout-check.json').as_posix()]),
                      ('contrast', [sys.executable, str(HERE / 'screen_contract_check.py')] + ['--layout-dump=' + d for d in dumps])):
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', env=dict(__import__('os').environ, PYTHONUTF8='1'))
        tail = [l for l in (p.stdout + p.stderr).splitlines() if l.strip()]
        (out / 'logs' / (name + '.log')).write_text(p.stdout + p.stderr, encoding='utf-8', newline='\n')
        notes[name] = 'exit %d: %s' % (p.returncode, (tail[-1] if tail else 'no output')[:300])
    return notes


def table(results):
    rows = [('proposal', 'kind', 'res', 'fx', 'exit', 'sec', 'err', 'lines', 'missing', 'verdict')]
    for r in results:
        rows.append((r['proposal'], r['kind'], r['res'], str(r['fixtures']), str(r['exit']), str(r['seconds']), str(r['script_errors']), str(r['proposal_lines']),
                     str(len(r['files_missing'])), r['verdict']))
    width = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    return '\n'.join('  '.join(c.ljust(width[i]) for i, c in enumerate(row)) for row in rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--only', default='', help='comma list of proposals (default: the current three)')
    ap.add_argument('--include-old', action='store_true', help='also the older growth proposals a_oath, b_seal, c_two_beat')
    ap.add_argument('--kinds', default='', help='comma list of job kinds (see --list-kinds)')
    ap.add_argument('--res', default=','.join(RES), help='comma list of WxH (default both)')
    ap.add_argument('--out', default='', help='folder under _local/shots (default _local/shots/proposal-batch/<stamp>)')
    ap.add_argument('--timeout', type=int, default=300, help='seconds per window job before it is ended (default 300)')
    ap.add_argument('--game-args', default='', help='more game arguments for every job, e.g. "--chapter1-trial=spells"')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--list-kinds', action='store_true')
    a = ap.parse_args(argv)
    if a.list_kinds:
        print(' '.join(ALL_KINDS))
        return 0
    table_ = dict(PROPOSALS, **(OLD if a.include_old else {}))
    names = [n for n in a.only.split(',') if n] or list(PROPOSALS)
    bad = [n for n in names if n not in dict(PROPOSALS, **OLD)]
    kinds = [k for k in a.kinds.split(',') if k]
    resolutions = [r for r in a.res.split(',') if r]
    if bad or [k for k in kinds if k not in ALL_KINDS] or [r for r in resolutions if not re.fullmatch(r'\d+x\d+', r)]:
        print('bad argument: unknown proposal %s / kind / resolution' % bad, file=sys.stderr)
        return 2
    table_ = dict(PROPOSALS, **OLD)
    out = (ROOT / a.out) if a.out and not Path(a.out).is_absolute() else Path(a.out) if a.out else ROOT / '_local' / 'shots' / 'proposal-batch' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    try:
        out.resolve().relative_to((ROOT / '_local' / 'shots').resolve())
    except ValueError:
        print('--out must be under %s' % (ROOT / '_local' / 'shots'), file=sys.stderr)
        return 2
    jobs = []
    for n in names:
        jobs += jobs_for(n, table_[n], kinds, resolutions)
    for j in jobs:
        j['game_args'] = a.game_args.split() if a.game_args else []
    if a.dry_run:
        for j in jobs:
            print(' '.join(command(j, out, a.timeout)))
        print('%d jobs (dry run, nothing started)' % len(jobs))
        return 0
    if not jobs:
        print('no jobs')
        return 2
    logs = out / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for i, j in enumerate(jobs, 1):
        print('[%d/%d] %s %s %s ...' % (i, len(jobs), j['proposal'], j['kind'], j['res']), flush=True)
        r = run_job(j, out, a.timeout, logs)
        print('    %s (exit %s, %.0f s, %d script errors, %d files missing)' % (r['verdict'], r['exit'], r['seconds'], r['script_errors'], len(r['files_missing'])), flush=True)
        results.append(r)
    notes = readouts(out, results)
    text = table(results) + '\n\n' + '\n'.join('%s: %s' % kv for kv in notes.items())
    (out / 'batch.txt').write_text(text + '\n', encoding='utf-8', newline='\n')
    (out / 'batch.json').write_text(json.dumps({'results': results, 'readouts': notes}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8', newline='\n')
    print('\n' + text)
    print('raw: %s' % out)
    failed = [r for r in results if r['verdict'] != 'ok']
    print('PROPOSAL_BATCH ' + json.dumps({'jobs': len(results), 'failed': len(failed), 'out': out.as_posix()}))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
