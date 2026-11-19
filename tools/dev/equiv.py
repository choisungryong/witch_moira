"""Behaviour-preservation check for refactors: run a base commit and the working folder the same way and compare what they dump.

    python tools/dev/equiv.py                                   # base HEAD vs this folder, frost, --until 1600
    python tools/dev/equiv.py --base f36b0a7 --primary frost,ember,arc --until 2400
    python tools/dev/equiv.py --until 600 --primary frost --skip-golden
    python tools/dev/equiv.py --until 2400 --primary frost,ember,arc --game-args="--chapter1-trial=spells"   # the same run with a test switch on, both sides

What it does
  1. Prints, first, what it does NOT compare. "EQUIV IDENTICAL" holds only for the fields the dumps hold.
  2. Checks the base commit out into a temporary git worktree under _local/equiv/<stamp>/base-tree (removed at the end; --keep-base keeps it),
     copies this folder's import cache, copies this folder's dump scripts into it (so both sides are dumped by the same script;
     --own-dumpers uses each side's own), and imports it.
  3. For every primary, on both sides, headless at a fixed 60 fps with the same arguments (pilot, seed 11, profile off):
       hud_dump.gd --dump --scene   HUD control tree and every Node3D (transform, visibility, light colour, camera, MultiMesh sample)
       equiv_dump.gd                enemy and hero bone poses, animation, materials, cast_shadow, effect MultiMesh and mesh hashes
  4. Runs golden_core.gd on THIS folder against the BASE commit's golden files (plain and text-free), for the chosen primaries.
  5. Compares by moment, node and field. Differences print as  <kind>/<moment>/<node>/<field>  base -> work.
     Rows of nodes that are not visible in the tree are compared only for their visibility (--strict-hidden compares everything).
     Fields that wobble from run to run are listed in tools/dev/equiv_volatile.json with the reason; they are skipped and counted.
  Last line: EQUIV IDENTICAL (exit 0), EQUIV DIFFERENT (exit 1) or EQUIV ERROR (exit 2: a run failed or a dump is missing).

Output goes to _local/equiv/<stamp>/ (dumps, logs, result.json). Nothing under the user's save folder is read or written:
Godot is started through tools/dev/godot.py, which isolates APPDATA.
"""
import argparse
import concurrent.futures
import datetime
import difflib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GODOT_PY = HERE / 'godot.py'
VOLATILE = HERE / 'equiv_volatile.json'
DUMPERS = ['chapter1/tests/hud_dump.gd', 'chapter1/tests/layout_dump.gd', 'chapter1/tests/equiv_dump.gd',
           'chapter1/tests/spells_pick.gd', 'chapter1/tests/support/trial_docs.gd']  # the last two are preloaded by hud_dump.gd (S0-b)
PILOT_ARGS = ['--chapter1-pilot', '--chapter1-profile-off', '--chapter1-qa-ignore-focus', '--chapter1-seed=11']
SKILLS = {'frost': 'chapter1.skill.frost', 'ember': 'chapter1.skill.ember', 'arc': 'chapter1.skill.arc'}
EQ_TICKS = [300, 600, 1200, 2400, 6000, 9000, 12000, 16000, 20000]

NOT_COMPARED = [
    '실제 출력 픽셀·소리·사람 눈(헤드리스 더미 렌더러)',
    'MultiMesh 인스턴스의 변환·색·사용자 데이터(헤드리스가 값을 보관하지 않아 개수만 비교. 장면 덤프의 앞 24개 표본도 같은 이유로 단위 행렬)',
    'ShaderMaterial의 셰이더 값(uniform)과 셰이더 코드(셰이더 파일 경로만)',
    '라이트·환경·그림자 설정(장면 덤프는 라이트 색·세기만, 메시의 cast_shadow는 비교)',
    '트리에서 보이지 않는 노드의 변환과 속성(--strict-hidden이면 비교)',
    'HUD의 글꼴·테마 색(modulate와 글자·위치·크기만)',
    '덤프 시점 사이의 프레임과 --until 이후의 판',
    '고르지 않은 주력·시드',
    '오디오 요청, 저장·프로필 흐름',
    '코어는 골든 사례의 체크포인트 해시(600틱마다)로만',
]


# ---------------------------------------------------------------- comparison (pure functions)

ANON = re.compile(r'@(\w+)@\d+')


def load_volatile(path=VOLATILE):
    if not Path(path).is_file():
        return {'normalize_names': {'pattern': r'@(\w+)@\d+', 'replace': r'@\1'}, 'ignore': []}
    return json.loads(Path(path).read_text(encoding='utf-8'))


def norm_name(name, vol=None):
    p = (vol or {}).get('normalize_names', {}).get('pattern', r'@(\w+)@\d+')
    r = (vol or {}).get('normalize_names', {}).get('replace', r'@\1')
    return re.sub(p, r, str(name))


def split_game_args(text):
    """`--game-args="--chapter1-trial=spells --chapter1-profile-off"` -> ['--chapter1-trial=spells', '--chapter1-profile-off'].
    Quotes keep a value with spaces together. Empty text -> []. The same list goes to BOTH sides, after the pilot arguments."""
    import shlex
    return shlex.split(text or '')


def deep_diff(a, b, path, out, limit=12):
    """Append (path, a, b) for each leaf that differs, at most `limit` per call."""
    if len(out) >= limit:
        return
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a:
                out.append((path + '.' + str(k), '(없음)', _short(b[k])))
            elif k not in b:
                out.append((path + '.' + str(k), _short(a[k]), '(없음)'))
            else:
                deep_diff(a[k], b[k], path + '.' + str(k), out, limit)
            if len(out) >= limit:
                return
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append((path + '.len', len(a), len(b)))
        for i in range(min(len(a), len(b))):
            deep_diff(a[i], b[i], '%s[%d]' % (path, i), out, limit)
            if len(out) >= limit:
                return
    elif a != b:
        out.append((path, _short(a), _short(b)))


def _short(v):
    s = json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v
    return s if len(s) <= 80 else s[:77] + '...'


def effective(rows):
    return [r for r in rows if r.get('visible', True)]


def compare_rows(kind, label, a_rows, b_rows, vol, strict_hidden=False):
    """Rows of one moment of a hud or scene dump. Returns list of (path, base value, work value)."""
    diffs = []
    ra = a_rows if strict_hidden else effective(a_rows)
    rb = b_rows if strict_hidden else effective(b_rows)
    ka = [(r.get('d'), r.get('class'), norm_name(r.get('name'), vol)) for r in ra]
    kb = [(r.get('d'), r.get('class'), norm_name(r.get('name'), vol)) for r in rb]
    if ka == kb:
        pairs = list(zip(range(len(ra)), range(len(rb))))
    else:
        pairs = []
        sm = difflib.SequenceMatcher(None, ka, kb, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == 'equal':
                pairs += list(zip(range(i1, i2), range(j1, j2)))
            else:
                for i in range(i1, i2):
                    diffs.append(('%s/%s/%s:%s#%d' % (kind, label, ka[i][1], ka[i][2], i), '있음(깊이 %s)' % ka[i][0], '없음'))
                for j in range(j1, j2):
                    diffs.append(('%s/%s/%s:%s#%d' % (kind, label, kb[j][1], kb[j][2], j), '없음', '있음(깊이 %s)' % kb[j][0]))
    for i, j in pairs:
        x, y = ra[i], rb[j]
        out = []
        for k in sorted((set(x) | set(y)) - {'d', 'class', 'name'}):
            if k in x and k in y:
                deep_diff(x[k], y[k], k, out)
            else:
                out.append((k, _short(x.get(k, '(없음)')), _short(y.get(k, '(없음)'))))
        for field, va, vb in out:
            diffs.append(('%s/%s/%s:%s#%d/%s' % (kind, label, ka[i][1], ka[i][2], i, field), va, vb))
    return diffs


def compare_moments(kind, a_doc, b_doc, vol, strict_hidden=False):
    """hud dump (key 'dumps') or scene dump (key 'scenes'): same moments in the same order, then rows."""
    key = 'dumps' if kind == 'hud' else 'scenes'
    diffs = []
    oa, ob = a_doc.get('order', []), b_doc.get('order', [])
    if oa != ob:
        diffs.append(('%s/moments' % kind, ' '.join(oa), ' '.join(ob)))
    for label in [m for m in oa if m in ob]:
        diffs += compare_rows(kind, label, a_doc[key][label], b_doc[key][label], vol, strict_hidden)
    return diffs


def part_detail(part, full_a, full_b):
    """Field-level difference of one eq part using the --eq-full files. part like 'a:<id>:bones', 'hero:base', 'fx:<name>'."""
    out = []
    if part.startswith('a:') and part.count(':') >= 2:
        key, _, sub = part[2:].rpartition(':')
        ea, eb = (full_a or {}).get('a:' + key), (full_b or {}).get('a:' + key)
        if ea is None or eb is None:
            return [('(액터 없음)', '있음' if ea is not None else '없음', '있음' if eb is not None else '없음')]
        deep_diff(ea.get(sub), eb.get(sub), sub, out)
    elif part.startswith('hero:'):
        sub = part[5:]
        ea, eb = (full_a or {}).get('hero'), (full_b or {}).get('hero')
        if ea is None or eb is None:
            return [('(주인공 없음)', '있음' if ea is not None else '없음', '있음' if eb is not None else '없음')]
        if sub == 'base':
            for k in ('t', 'staff', 'anim', 'fade'):
                deep_diff(ea.get(k), eb.get(k), k, out)
        else:
            deep_diff(ea.get(sub), eb.get(sub), sub, out)
    elif part.startswith('fx:'):
        ea, eb = (full_a or {}).get(part), (full_b or {}).get(part)
        if ea is None or eb is None:
            return [('(효과 노드 없음)', '있음' if ea is not None else '없음', '있음' if eb is not None else '없음')]
        deep_diff(ea, eb, '', out)
    return out


def compare_eq(a_doc, b_doc, full_a, full_b, vol):
    diffs = []
    sa = {s['label']: s for s in a_doc.get('snapshots', [])}
    sb = {s['label']: s for s in b_doc.get('snapshots', [])}
    if list(sa) != list(sb):
        diffs.append(('eq/moments', ' '.join(sa), ' '.join(sb)))
    for label in [l for l in sa if l in sb]:
        x, y = sa[label], sb[label]
        if x['tick'] != y['tick']:
            diffs.append(('eq/%s/tick' % label, x['tick'], y['tick']))
        for k in sorted(set(x['info']) | set(y['info'])):
            if x['info'].get(k) != y['info'].get(k):
                diffs.append(('eq/%s/info.%s' % (label, k), x['info'].get(k), y['info'].get(k)))
        if x['hash'] == y['hash']:
            continue
        parts = sorted(set(x['parts']) | set(y['parts']))
        for part in parts:
            if x['parts'].get(part) == y['parts'].get(part):
                continue
            pn = norm_name(part, vol)
            if part not in x['parts'] or part not in y['parts']:
                diffs.append(('eq/%s/%s' % (label, pn), '있음' if part in x['parts'] else '없음', '있음' if part in y['parts'] else '없음'))
                continue
            detail = part_detail(part, (full_a or {}).get(label), (full_b or {}).get(label))
            if detail:
                for field, va, vb in detail:
                    diffs.append(('eq/%s/%s/%s' % (label, pn, field), va, vb))
            else:
                diffs.append(('eq/%s/%s' % (label, pn), '해시 ' + x['parts'][part], '해시 ' + y['parts'][part] + ' (자세한 값 없음)'))
    return diffs


def apply_volatile(diffs, vol):
    """Split diffs into (kept, ignored{rule name: count}). A rule is {'name', 'match' (regex on the path), 'why'}."""
    rules = [(r['name'], re.compile(r['match']), r.get('why', '')) for r in vol.get('ignore', [])]
    kept, ignored = [], {}
    for d in diffs:
        for name, rx, _ in rules:
            if rx.search(d[0]):
                ignored[name] = ignored.get(name, 0) + 1
                break
        else:
            kept.append(d)
    return kept, ignored


def mm_note(eq_doc):
    """Observed, not assumed: do the MultiMesh values of this headless run carry any information?"""
    shown = sum(s['info'].get('mm_visible_instances', 0) for s in eq_doc.get('snapshots', []))
    nonid = sum(s['info'].get('mm_nonidentity_transforms', 0) for s in eq_doc.get('snapshots', []))
    if shown and not nonid:
        return 'MultiMesh: 보이는 인스턴스 %d개의 변환이 모두 단위 행렬이다(값을 읽지 못함, 개수만 비교됨)' % shown
    if shown:
        return 'MultiMesh: 보이는 인스턴스 %d개 중 단위 행렬이 아닌 변환 %d개(이번에는 값이 읽혔다)' % (shown, nonid)
    return 'MultiMesh: 보이는 인스턴스가 없었다'


# ---------------------------------------------------------------- running

def run(cmd, cwd=None, log=None, timeout=1800):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
        out, code = p.stdout + p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        out, code = (e.stdout or '') if isinstance(e.stdout, str) else '', -999
        out += '\nTIMEOUT after %ds' % timeout
    if log:
        Path(log).write_text(out, encoding='utf-8', newline='\n')
    return code, out, time.time() - t0


def git(*args, check=True):
    p = subprocess.run(['git', '-C', str(ROOT)] + list(args), capture_output=True, text=True, encoding='utf-8', errors='replace')
    if check and p.returncode != 0:
        raise RuntimeError('git %s failed: %s' % (' '.join(args), (p.stderr or p.stdout).strip()))
    return p.stdout.strip()


def godot(side_path, script, user_args, log, timeout=1800, extra_engine=None):
    cmd = [sys.executable, str(GODOT_PY), '--headless', '--fixed-fps', '60', '--path', str(side_path)] + (extra_engine or []) + ['--script', script, '--'] + user_args
    return run(cmd, log=log, timeout=timeout)


def prepare_base(rev, base_dir, own_dumpers, log):
    git('worktree', 'add', '--detach', str(base_dir), rev)
    src_cache = ROOT / '.godot'
    if src_cache.is_dir():
        shutil.copytree(src_cache, base_dir / '.godot', dirs_exist_ok=True)
    if not own_dumpers:
        for rel in DUMPERS:
            src = ROOT / rel
            if src.is_file():
                (base_dir / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, base_dir / rel)
    for attempt in range(3):  # a fresh import sometimes ends with an access violation on its first pass; the next pass continues
        code, out, secs = run([sys.executable, str(GODOT_PY), '--headless', '--path', str(base_dir), '--import'], log=log, timeout=1800)
        if code == 0:
            return secs
    raise RuntimeError('import of the base folder failed (exit %s), see %s' % (code, log))


def remove_base(base_dir):
    try:
        git('worktree', 'remove', '--force', str(base_dir), check=False)
        git('worktree', 'prune', check=False)
    finally:
        if Path(base_dir).exists():
            shutil.rmtree(base_dir, ignore_errors=True)


def script_errors(text):
    return len(re.findall(r'SCRIPT ERROR|Parse Error|Compile Error', text))


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--base', default='HEAD', help='commit to compare against (default HEAD)')
    ap.add_argument('--primary', default='frost', help='comma list of frost, ember, arc (default frost)')
    ap.add_argument('--until', type=int, default=1600, help='stop the dumps at this tick (default 1600, includes the pause screen)')
    ap.add_argument('--out', default='', help='output folder under _local/ (default _local/equiv/<stamp>)')
    ap.add_argument('--skip-golden', action='store_true')
    ap.add_argument('--only', default='hud,scene,eq', help='dumps to compare: hud,scene,eq (default all)')
    ap.add_argument('--strict-hidden', action='store_true')
    ap.add_argument('--own-dumpers', action='store_true', help="use each side's own dump scripts instead of this folder's")
    ap.add_argument('--keep-base', action='store_true')
    ap.add_argument('--jobs', type=int, default=3)
    ap.add_argument('--max-diffs', type=int, default=40, help='differences printed per primary')
    ap.add_argument('--volatile', default=str(VOLATILE))
    ap.add_argument('--timeout', type=int, default=1800)
    ap.add_argument('--game-args', default='', help='more game arguments for BOTH sides of every dump run, e.g. "--chapter1-trial=spells" '
                    '(the golden step does not take them: it has its own cases)')
    args = ap.parse_args(argv)

    print('비교하지 않은 것: ' + '; '.join(NOT_COMPARED) + '. "EQUIV IDENTICAL"은 덤프가 담는 필드에 한해서다.')
    vol = load_volatile(args.volatile)
    names = [s.strip() for s in args.primary.split(',') if s.strip()]
    bad = [n for n in names if n not in SKILLS]
    if bad:
        print('unknown primary: %s (frost, ember, arc)' % ','.join(bad), file=sys.stderr)
        return 2
    only = set(args.only.split(','))
    game_args = split_game_args(args.game_args)
    pilot_args = PILOT_ARGS + game_args
    if game_args:
        print('게임 인수(양쪽에 같이): ' + ' '.join(game_args))
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    out = (Path(args.out) if args.out else ROOT / '_local' / 'equiv' / stamp).resolve()  # absolute: Godot changes its working folder to --path
    try:
        out.resolve().relative_to((ROOT / '_local').resolve())
    except ValueError:
        print('--out must be under %s' % (ROOT / '_local'), file=sys.stderr)
        return 2
    if out.exists() and any(out.iterdir()):
        print('--out already holds files; use a new folder', file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    base_rev = git('rev-parse', '--short', args.base)
    dirty = git('status', '--porcelain', '--', '.', ':(exclude)_local').splitlines()
    print('기준 %s(%s) / 작업 폴더 %s (변경 파일 %d개, 새 파일 포함)' % (args.base, base_rev, ROOT, len(dirty)))
    base_dir = out / 'base-tree'
    work_dir = ROOT
    problems = []
    results, golden, names_done = {}, {}, []
    try:
        t = prepare_base(args.base, base_dir, args.own_dumpers, out / 'base-import.log')
        print('기준 폴더 준비 %.0f초(%s)' % (t, base_dir))
        sides = {'base': base_dir, 'work': work_dir}
        tasks = []
        for n in names:
            skill = SKILLS[n]
            ticks = ','.join(str(x) for x in EQ_TICKS if x <= args.until) or str(args.until)
            for side, path in sides.items():
                d = out / ('dump-' + side)
                d.mkdir(exist_ok=True)
                if 'hud' in only or 'scene' in only:
                    tasks.append((side, n, 'hud', 'res://chapter1/tests/hud_dump.gd',
                                  pilot_args + ['--primary=' + skill, '--until=%d' % args.until, '--dump=%s/%s-hud.json' % (str(d).replace('\\', '/'), n), '--scene=%s/%s-scene.json' % (str(d).replace('\\', '/'), n)]))
                if 'eq' in only:
                    tasks.append((side, n, 'eq', 'res://chapter1/tests/equiv_dump.gd',
                                  pilot_args + ['--primary=' + skill, '--eq-until=%d' % args.until, '--eq-ticks=' + ticks, '--eq-out=%s/%s-eq.json' % (str(d).replace('\\', '/'), n), '--eq-full=%s/%s-eqfull.json' % (str(d).replace('\\', '/'), n)]))

        def do(task):
            side, n, kind, script, uargs = task
            code, text, secs = godot(sides[side], script, uargs, out / ('dump-' + side) / ('%s-%s.log' % (n, kind)), args.timeout)
            return task, code, text, secs

        golden_jobs = []
        if not args.skip_golden:
            gdir = out / 'dump-work'
            gdir.mkdir(exist_ok=True)
            for n in names:
                golden_jobs.append(n)

        def do_golden(n):
            skill = SKILLS[n]
            gargs = ['--both', '--case=11:' + skill,
                     '--golden=' + str(base_dir / 'chapter1/tests/golden/core_runtime.json').replace('\\', '/'),
                     '--golden-textless=' + str(base_dir / 'chapter1/tests/golden/core_runtime_textless.json').replace('\\', '/')]
            cmd = [sys.executable, str(GODOT_PY), '--headless', '--path', str(work_dir), '--script', 'res://chapter1/tests/golden_core.gd', '--'] + gargs
            code, text, secs = run(cmd, log=out / 'dump-work' / ('%s-golden.log' % n), timeout=args.timeout)
            return n, code, text, secs

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            futs = [pool.submit(do, t) for t in tasks] + [pool.submit(do_golden, n) for n in golden_jobs]
            for f in concurrent.futures.as_completed(futs):
                r = f.result()
                if len(r) == 4 and isinstance(r[0], tuple):
                    task, code, text, secs = r
                    results[(task[0], task[1], task[2])] = (code, text, secs)
                    print('  %s %s %s: exit %s, %.0f초, 스크립트 오류 %d' % (task[0], task[1], task[2], code, secs, script_errors(text)))
                else:
                    n, code, text, secs = r
                    golden[n] = (code, text, secs)
                    print('  golden %s: exit %s, %.0f초' % (n, code, secs))
    except Exception as e:  # noqa: BLE001
        problems.append(str(e))
    else:
        names_done = names
    finally:
        if not args.keep_base:
            remove_base(base_dir)

    verdict_diff = 0
    summary = {'base': base_rev, 'primaries': names, 'until': args.until, 'problems': problems, 'diffs': {}, 'ignored': {}, 'golden': {}}
    for n in names_done:
        diffs = []
        problems_before = len(problems)
        for kind, fn, dump_key in (('hud', '%s-hud.json', 'hud'), ('scene', '%s-scene.json', 'scene')):
            if kind not in only:
                continue
            pa, pb = out / 'dump-base' / (fn % n), out / 'dump-work' / (fn % n)
            if not pa.is_file() or not pb.is_file():
                problems.append('%s %s dump missing (base %s, work %s)' % (n, kind, pa.is_file(), pb.is_file()))
                continue
            diffs += compare_moments(kind, json.loads(pa.read_text(encoding='utf-8')), json.loads(pb.read_text(encoding='utf-8')), vol, args.strict_hidden)
        if 'eq' in only:
            pa, pb = out / 'dump-base' / ('%s-eq.json' % n), out / 'dump-work' / ('%s-eq.json' % n)
            if not pa.is_file() or not pb.is_file():
                problems.append('%s eq dump missing (base %s, work %s)' % (n, pa.is_file(), pb.is_file()))
            else:
                fa, fb = out / 'dump-base' / ('%s-eqfull.json' % n), out / 'dump-work' / ('%s-eqfull.json' % n)
                da, db = json.loads(pa.read_text(encoding='utf-8')), json.loads(pb.read_text(encoding='utf-8'))
                diffs += compare_eq(da, db, json.loads(fa.read_text(encoding='utf-8')) if fa.is_file() else None, json.loads(fb.read_text(encoding='utf-8')) if fb.is_file() else None, vol)
                print('  [%s] %s' % (n, mm_note(db)))
        for side in ('base', 'work'):
            for kind in ('hud', 'eq'):
                r = results.get((side, n, kind))
                if r and r[0] != 0:
                    problems.append('%s %s %s exited %s' % (side, n, kind, r[0]))
        for kind in ('hud', 'eq'):
            ra, rb = results.get(('base', n, kind)), results.get(('work', n, kind))
            if ra and rb and script_errors(ra[1]) != script_errors(rb[1]):
                diffs.append(('log/%s/%s/스크립트 오류 수' % (n, kind), script_errors(ra[1]), script_errors(rb[1])))
        kept, ignored = apply_volatile(diffs, vol)
        summary['diffs'][n] = len(kept)
        summary['ignored'][n] = ignored
        verdict_diff += len(kept)
        if len(problems) > problems_before:
            print('[%s] 비교하지 못한 덤프가 있다(아래 문제 참고). 지금까지 찾은 차이 %d건' % (n, len(kept)))
        else:
            print('[%s] 차이 %d건%s' % (n, len(kept), (' (흔들리는 필드로 뺀 것 %s)' % ignored) if ignored else ''))
        for path, a, b in kept[:args.max_diffs]:
            print('   %s: %s -> %s' % (path, a, b))
        if len(kept) > args.max_diffs:
            print('   ... %d건 더(--max-diffs)' % (len(kept) - args.max_diffs))
        if not args.skip_golden:
            g = golden.get(n)
            if g is None:
                problems.append('golden %s did not run' % n)
            else:
                lines = [l for l in g[1].splitlines() if l.startswith('GOLDEN_RESULT') or l.startswith('GOLDEN_TEXTLESS_RESULT')]
                ok = g[0] == 0 and len(lines) == 2
                summary['golden'][n] = {'exit': g[0], 'lines': lines}
                print('[%s] 골든(기준 커밋의 골든 파일 대비): %s %s' % (n, 'ok' if ok else 'DIFF/ERROR exit %s' % g[0], ' | '.join(l[:140] for l in lines)))
                if g[0] == 1:
                    verdict_diff += 1
                elif g[0] != 0 or len(lines) != 2:
                    problems.append('golden %s exit %s' % (n, g[0]))
        else:
            print('[%s] 골든: 건너뜀(--skip-golden)' % n)
    (out / 'result.json').write_text(json.dumps(summary, indent=1, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')
    print('원시: %s' % out)
    for p in problems:
        print('문제: ' + p)
    if problems:
        print('EQUIV ERROR')
        return 2
    print('EQUIV IDENTICAL' if verdict_diff == 0 else 'EQUIV DIFFERENT')
    return 0 if verdict_diff == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
