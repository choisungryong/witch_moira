"""Balance lab backend: runs tools/dev/balance_sim.py as a subprocess and reads its --out JSON (stdlib only).

The simulator is a calculation model, not the game. This module never imports it into the server process, never writes
chapter1/data, and keeps every file it writes under _local/balance-lab/. Unknown simulator keys are passed through, not rejected.
"""
import json, math, os, re, subprocess, sys, threading, time, uuid
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT

LAB_DIRNAME = Path('_local') / 'balance-lab'
SIM_REL = Path('tools') / 'dev' / 'balance_sim.py'
PROBE = Path(__file__).resolve().parent / 'balance_lab_probe.py'
SPELLS_GLOB = 'balance_sim_spells_*.json'
REAL_SPELLS = Path('chapter1') / 'data' / 'run_spells.json'
SK = 'chapter1.skill.'

MAX_SEEDS = 30
MAX_RUNS = 1000            # policies x witches x seeds
MAX_SETS = 60
TIMEOUT_S = 150
KEY_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+|\[\d{1,3}\])*$')
STR_VALUE_RE = re.compile(r'^[A-Za-z0-9_.\-]{1,40}$')
NAME_RE = re.compile(r'^[a-z][a-z0-9_]*(?::[A-Za-z0-9_]+)?$')
GEAR_RE = re.compile(r'^(?:\d{1,2}(?:\.\d{1,3})?|[a-z_]{1,12}=\d{1,2}(?:\.\d{1,3})?(?:,[a-z_]{1,12}=\d{1,2}(?:\.\d{1,3})?){0,5})$')
EXP_ID_RE = re.compile(r'^exp-\d{8}-\d{6}-[0-9a-f]{4}$')
RUN_LOCK = threading.Lock()
STORE_LOCK = threading.Lock()
_PROBE_CACHE = {}

DEFAULT_WITCHES = ['ember', 'frost', 'arc']
DEFAULT_PRESETS = ['spec1', 'spec1p', 'current_on', 'current']
PRESET_LABELS = {'spec1': '명세 첫 값(리듬 켬)', 'spec1p': '명세 첫 값 + 포위 압력·우두머리 격앙', 'current_on': '지금 게임 값 + 리듬만 켬', 'current': '지금 게임 값(리듬 꺼짐)'}
WITCH_LABELS = {'ember': '불꽃 마녀', 'frost': '냉기 마녀', 'arc': '번개 마녀'}
CLASS_LABELS = {'synergy': '시너지 맞춘 조합', 'narrow': '하나만 쌓기', 'narrow_ring': '원형만 쌓기', 'random': '아무렇게나', 'spread': '골고루 흩뿌리기', 'worst': '일부러 최악'}
ROLE_LABELS = {'basic': '기본기', 'ring': '원형', 'A': '빌린 주문 A', 'B': '빌린 주문 B'}
BEAT_LABELS = {'gi': '기', 'seung1': '승1', 'seung2': '승2', 'jeon_a': '전A', 'trial': '전B(버티기)', 'boss': '전C(우두머리)'}
LEAF_LABELS = {
    'damage_raw': '피해(원값)', 'cooldown_ticks': '쿨다운(틱)', 'projectiles': '탄 수', 'radius_cm': '폭발 범위(cm)', 'hit_budget': '한 번에 맞히는 수',
    'pierce': '관통 수', 'chain_targets': '연쇄 수', 'branches': '갈래 수', 'ring_radius_cm': '원형 반지름(cm)', 'ring_targets': '원형 대상 수',
    'ring_pulses': '원형 맥동 수', 'weight': '제안 비중', 'vs_strong_bps': '강한 적 상대 피해(1만=100%)', 'per_stack_bps': '쌓임당 터뜨림(1만=100%)',
    'damage_bps': '피해 배율(1만=100%)', 'cooldown_bps': '쿨다운 배율(1만=100%)', 'amount': '한 번에 나오는 수', 'interval_ticks': '나오는 간격(틱)',
    'alive_cap': '동시에 살아 있는 상한', 'max_ticks': '마디 시간 상한(틱)', 'from_bps': '시작 위치(1만=100%)', 'hp_bps': '적 체력 배율(1만=100%)',
    'hold_ticks': '버티는 시간(틱)', 'radius_m': '범위(m)', 'cap_per_axis': '축 상한', 'cap_per_spell': '주문당 상한', 'max': '최대 쌓임',
    'expire_ticks': '사라지는 시간(틱)', 'freeze_at': '얼어붙는 쌓임 수', 'axis_sum': '진화에 필요한 축 합', 'partner_axis_sum': '진화 짝 축 합',
    'partner_detonate_bps': '진화 짝 터뜨림(1만=100%)', 'initial_pack': '처음 무리 수', 'gate_rest_ticks': '문 앞 쉬는 시간(틱)', 'slots': '주문 칸 수',
    'seal_kills': '봉인을 깨는 처치 수', 'pair_open_levels': '짝이 열리는 레벨', 'ring_at_level': '원형 보호 레벨',
}
SKIP_TOP = {'note', 'provenance', 'schema_version', 'balance_status', 'enabled'}
KNOWN_CELL_KEYS = {'win_rate', 'n', 'secs_median', 'deaths', 'stalls', 'det_share_mean', 'evolve_t', 'builds', 'per_beat'}


class BusyError(Exception):
    pass


class RunError(Exception):
    pass


def lab_dir(root=None):
    return (root or ROOT) / LAB_DIRNAME


def short_id(sid):
    return sid[len(SK):] if sid.startswith(SK) else sid


# ---- options the simulator and data files offer ------------------------------------------------
def spell_files(root=None):
    root = root or ROOT
    files = []
    real = root / REAL_SPELLS
    if real.is_file():
        files.append({'id': 'run_spells', 'path': REAL_SPELLS.as_posix(), 'label': '게임에 들어 있는 주문 데이터(run_spells.json)', 'abs': real})
    for p in sorted((root / 'tools' / 'dev').glob(SPELLS_GLOB)):
        stem = p.stem
        label = {'balance_sim_spells_draft': '명세 초안(draft)', 'balance_sim_spells_lab': '시험 묶음(lab)'}.get(stem, stem.replace('balance_sim_spells_', '시험: '))
        files.append({'id': stem, 'path': p.relative_to(root).as_posix(), 'label': label, 'abs': p})
    return files


def default_spell_id(files):
    ids = [f['id'] for f in files]
    return 'run_spells' if 'run_spells' in ids else ('balance_sim_spells_draft' if 'balance_sim_spells_draft' in ids else (ids[0] if ids else None))


def preset_names(root=None):
    """Preset names scanned from apply_preset in the simulator source (falls back to the known four)."""
    root = root or ROOT
    try:
        src = (root / SIM_REL).read_text(encoding='utf-8')
        start = src.index('def apply_preset')
        end = src.find('\ndef ', start + 10)
        body = src[start:end if end > 0 else None]
        names = []
        for m in re.finditer(r'name\s*(?:==|in|not in)\s*(\([^)]*\)|"[^"]+")', body):
            for n in re.findall(r'"([A-Za-z0-9_]+)"', m.group(1)):
                if n not in names:
                    names.append(n)
        return names or list(DEFAULT_PRESETS)
    except (OSError, ValueError):
        return list(DEFAULT_PRESETS)


def probe(root=None, preset=None, spells_path=None):
    """Ask the simulator (in a subprocess) for its option lists and the config after the preset. Cached per file mtimes."""
    root = root or ROOT
    sim = root / SIM_REL
    stamp = (sim.stat().st_mtime_ns if sim.exists() else 0, (Path(spells_path).stat().st_mtime_ns if spells_path and Path(spells_path).exists() else 0))
    key = (str(root), preset or '', str(spells_path or ''), stamp)
    if key in _PROBE_CACHE:
        return _PROBE_CACHE[key]
    cmd = [sys.executable, '-I', '-X', 'utf8', str(PROBE), str(root), preset or '', str(spells_path or '')]
    try:
        done = subprocess.run(cmd, capture_output=True, timeout=60, cwd=str(root), shell=False)
        text = done.stdout.decode('utf-8', 'replace').strip()
        value = json.loads(text.splitlines()[-1]) if text else None
        if not isinstance(value, dict):
            raise ValueError('empty probe output: ' + done.stderr.decode('utf-8', 'replace')[-300:])
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        value = {'ok': False, 'probe_error': '%s: %s' % (e.__class__.__name__, e)}
    _PROBE_CACHE.clear() if len(_PROBE_CACHE) > 16 else None
    _PROBE_CACHE[key] = value
    return value


def known_options(root=None):
    """Allow-lists for request validation: policies, witches, presets, spell file ids."""
    root = root or ROOT
    info = probe(root)
    files = spell_files(root)
    policies = list(info.get('policies') or [])
    return {'policies': policies, 'witches': list(info.get('witches') or DEFAULT_WITCHES), 'presets': preset_names(root),
            'spell_files': {f['id']: f['abs'] for f in files}, 'probe': info}


# ---- request validation -------------------------------------------------------------------------
def render_value(v):
    """Command-line text for a number / bool / short string. Raises ValueError for anything else."""
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        if isinstance(v, float) and not math.isfinite(v):
            raise ValueError('값이 숫자가 아닙니다')
        if abs(v) > 1e9:
            raise ValueError('값이 너무 큽니다')
        return json.dumps(v)
    if isinstance(v, str):
        if not STR_VALUE_RE.match(v):
            raise ValueError('문자열 값은 영문·숫자·_ . - 만, 40자까지입니다')
        return v
    raise ValueError('값은 숫자나 짧은 문자열이어야 합니다')


def validate_request(payload, known):
    if not isinstance(payload, dict):
        raise ValueError('요청 형식이 맞지 않습니다')
    unknown = set(payload) - {'preset', 'spells', 'sets', 'policies', 'witches', 'seeds', 'gear'}
    if unknown:
        raise ValueError('알 수 없는 항목: ' + ', '.join(sorted(map(str, unknown))[:5]))
    preset = payload.get('preset')
    if preset not in (None, '') and preset not in known['presets']:
        raise ValueError('알 수 없는 프리셋입니다')
    spells = payload.get('spells')
    if spells not in (None, '') and spells not in known['spell_files']:
        raise ValueError('허용된 주문 묶음 파일이 아닙니다')
    sets = payload.get('sets') or []
    if not isinstance(sets, list) or len(sets) > MAX_SETS:
        raise ValueError('바꾼 값은 목록이며 %d개까지입니다' % MAX_SETS)
    norm_sets = []
    seen = set()
    for s in sets:
        if not isinstance(s, dict) or set(s) != {'key', 'value'}:
            raise ValueError('바꾼 값은 {key, value} 꼴이어야 합니다')
        key = s['key']
        if not isinstance(key, str) or len(key) > 120 or not KEY_RE.match(key):
            raise ValueError('값 이름 형식이 맞지 않습니다: %s' % str(key)[:40])
        if key in seen:
            raise ValueError('같은 값을 두 번 바꿀 수 없습니다: ' + key)
        seen.add(key)
        render_value(s['value'])
        norm_sets.append({'key': key, 'value': s['value']})
    policies = payload.get('policies') or []
    if not isinstance(policies, list) or len(policies) > 40:
        raise ValueError('정책 목록이 맞지 않습니다')
    for p in policies:
        if not isinstance(p, str) or not NAME_RE.match(p) or (known['policies'] and p not in known['policies']):
            raise ValueError('알 수 없는 찍는 방식: %s' % str(p)[:40])
    witches = payload.get('witches') or []
    if not isinstance(witches, list) or len(witches) > 6:
        raise ValueError('마녀 목록이 맞지 않습니다')
    for w in witches:
        if not isinstance(w, str) or not NAME_RE.match(w) or w not in known['witches']:
            raise ValueError('알 수 없는 마녀: %s' % str(w)[:40])
    seeds = payload.get('seeds', 10)
    if type(seeds) is not int or not 1 <= seeds <= MAX_SEEDS:
        raise ValueError('판 수(시드)는 1~%d 사이 정수입니다' % MAX_SEEDS)
    n_pol = len(policies) or max(len(known['policies']), 1)
    n_wit = len(witches) or len(DEFAULT_WITCHES)
    if n_pol * n_wit * seeds > MAX_RUNS:
        raise ValueError('한 번에 돌릴 수 있는 판은 %d판까지입니다(지금 %d판)' % (MAX_RUNS, n_pol * n_wit * seeds))
    gear = payload.get('gear')
    if gear not in (None, ''):
        if not isinstance(gear, str) or not GEAR_RE.match(gear):
            raise ValueError('장비 묶음 형식이 맞지 않습니다(예: 1.1 또는 dmg=1.1,hp=1.05)')
    return {'preset': preset or None, 'spells': spells or None, 'sets': norm_sets, 'policies': policies, 'witches': witches, 'seeds': seeds, 'gear': gear or None}


def build_command(req, known, out_path, root=None):
    """Argument array (no shell). The simulator is always the repo's own tools/dev/balance_sim.py."""
    root = root or ROOT
    cmd = [sys.executable, '-X', 'utf8', str(root / SIM_REL)]
    if req['preset']:
        cmd.append('--preset=' + req['preset'])
    if req['spells']:
        cmd.append('--spells=' + str(known['spell_files'][req['spells']]))
    for s in req['sets']:
        cmd.append('--set=%s=%s' % (s['key'], render_value(s['value'])))
    if req['policies']:
        cmd.append('--policies=' + ','.join(req['policies']))
    if req['witches']:
        cmd.append('--witches=' + ','.join(req['witches']))
    cmd.append('--seeds=%d' % req['seeds'])
    if req['gear']:
        cmd.append('--gear=' + req['gear'])
    cmd.append('--out=' + str(out_path))
    return cmd


def command_text(req):
    """Human-readable command line for the export file (relative paths)."""
    parts = ['python', 'tools/dev/balance_sim.py']
    if req['preset']:
        parts.append('--preset ' + req['preset'])
    for s in req['sets']:
        parts.append('--set %s=%s' % (s['key'], render_value(s['value'])))
    if req['policies']:
        parts.append('--policies ' + ','.join(req['policies']))
    if req['witches']:
        parts.append('--witches ' + ','.join(req['witches']))
    parts.append('--seeds %d' % req['seeds'])
    if req['gear']:
        parts.append('--gear ' + req['gear'])
    return ' '.join(parts)


# ---- run ----------------------------------------------------------------------------------------
def run(payload, root=None, known=None, runner=None, timeout=TIMEOUT_S):
    """Validate, run the simulator once at a time, return {result, analysis, ...}. `runner(cmd, timeout)` is for tests."""
    root = root or ROOT
    known = known or known_options(root)
    req = validate_request(payload, known)
    if not RUN_LOCK.acquire(blocking=False):
        raise BusyError('다른 실행이 아직 돌고 있습니다. 끝나면 다시 눌러 주세요.')
    try:
        runs_dir = lab_dir(root) / 'runs'
        runs_dir.mkdir(parents=True, exist_ok=True)
        out = runs_dir / ('run-%s.json' % uuid.uuid4().hex[:10])
        cmd = build_command(req, known, out, root)
        started = time.time()
        try:
            if runner:
                code, stdout, stderr = runner(cmd, timeout)
            else:
                done = subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=str(root), shell=False)
                code, stdout, stderr = done.returncode, done.stdout, done.stderr
        except subprocess.TimeoutExpired:
            raise RunError('시간 제한(%d초)을 넘겨 멈췄습니다. 판 수나 정책 수를 줄여 보세요.' % timeout)
        elapsed = time.time() - started
        text = out.with_suffix('.txt')
        try:
            if code != 0 or not out.is_file():
                tail = (stderr or b'').decode('utf-8', 'replace').strip().splitlines()[-4:]
                raise RunError('시뮬레이터가 값을 받아들이지 않았습니다: ' + (' / '.join(tail) or '종료 코드 %s' % code))
            doc = json.loads(out.read_text(encoding='utf-8'))
            report = text.read_text(encoding='utf-8') if text.is_file() else (stdout or b'').decode('utf-8', 'replace')
        finally:
            for p in (out, text):
                try:
                    p.unlink()
                except OSError:
                    pass
        if not isinstance(doc, dict) or not isinstance(doc.get('results'), dict):
            raise RunError('시뮬레이터 결과를 읽지 못했습니다(results가 없음).')
        info = known.get('probe') or {}
        analysis = analyze(doc, {'p7': info.get('p7') or {}, 'p4': info.get('p4') or {}})
        return {'request': req, 'command': command_text(req), 'elapsed_s': round(elapsed, 1), 'analysis': analysis, 'report_text': report,
                'sim_header': {k: v for k, v in doc.items() if k != 'results'}}
    finally:
        RUN_LOCK.release()


# ---- reading the result -------------------------------------------------------------------------
def _mark(v, rng):
    if v is None or not rng:
        return None
    lo, hi = rng
    if lo is not None and v < lo:
        return 'low'
    if hi is not None and v > hi:
        return 'high'
    return 'in'


def _mean(xs):
    xs = [x for x in xs if isinstance(x, (int, float))]
    return sum(xs) / len(xs) if xs else None


def policy_class(name):
    return name.split(':')[0]


def analyze(doc, targets):
    """Turn the simulator's --out JSON into the numbers the screen shows. Unknown keys are kept under `extras`."""
    p7 = targets.get('p7') or {}
    p4 = targets.get('p4') or {}
    results = doc.get('results') or {}
    policies, witches, cells = [], [], {}
    unknown_keys = set()
    for key, v in results.items():
        if not isinstance(v, dict):
            continue
        pol, _, w = key.rpartition('|')
        if pol not in policies:
            policies.append(pol)
        if w not in witches:
            witches.append(w)
        rate = v.get('win_rate')
        deaths = {}
        for d in v.get('deaths') or []:
            if isinstance(d, dict):
                k = (d.get('beat'), d.get('cause'))
                deaths[k] = deaths.get(k, 0) + 1
        evo = v.get('evolve_t')
        extras = {}
        for k, val in v.items():
            if k in KNOWN_CELL_KEYS:
                continue
            unknown_keys.add(k)
            if isinstance(val, (int, float, str, bool)) or val is None:
                extras[k] = val
            elif isinstance(val, dict) and all(isinstance(x, (int, float, str, bool, type(None))) for x in val.values()):
                extras[k] = val
        cell = {'win_rate': rate, 'n': v.get('n'), 'secs_median': v.get('secs_median'), 'stalls': v.get('stalls') or 0,
                'det_share_mean': v.get('det_share_mean'),
                'deaths': [{'beat': b, 'cause': c, 'count': n} for (b, c), n in sorted(deaths.items(), key=lambda kv: -kv[1])],
                'evolved': sum(1 for e in evo if e) if isinstance(evo, list) else None,
                'per_beat': v.get('per_beat') if isinstance(v.get('per_beat'), dict) else {},
                'mark': _mark(rate, p7.get(policy_class(pol))), 'target': p7.get(policy_class(pol)), 'extras': extras}
        cells['%s|%s' % (pol, w)] = cell
    classes = []
    for p in policies:
        c = policy_class(p)
        if c not in classes:
            classes.append(c)
    class_rows = []
    for c in classes:
        per = {}
        for w in witches:
            per[w] = _mean([cells[k]['win_rate'] for k in cells if policy_class(k.rpartition('|')[0]) == c and k.rpartition('|')[2] == w])
        mean = _mean(list(per.values()))
        class_rows.append({'cls': c, 'label': CLASS_LABELS.get(c, c), 'per_witch': per, 'mean': mean, 'target': p7.get(c), 'mark': _mark(mean, p7.get(c))})
    # ordering verdict (same rule as the simulator: synergy(avg) > narrow >= random >= spread >= worst, first step strict)
    order = [('synergy', '시너지 맞춘 조합'), ('narrow', '하나만 쌓기'), ('random', '아무렇게나'), ('spread', '골고루 흩뿌리기'), ('worst', '일부러 최악')]
    vw = []
    for w in witches:
        by = {r['cls']: r['per_witch'].get(w) for r in class_rows}
        seq = [{'cls': c, 'label': lab, 'value': by[c]} for c, lab in order if by.get(c) is not None]
        broken = None
        for i in range(len(seq) - 1):
            a, b = seq[i], seq[i + 1]
            if a['value'] < b['value'] or (i == 0 and not a['value'] > b['value']):
                broken = '%s(%d%%)가 %s(%d%%)보다 %s' % (a['label'], round(a['value'] * 100), b['label'], round(b['value'] * 100), '낮음' if a['value'] < b['value'] else '높지 않음')
                break
        syn = [cells[k]['win_rate'] for k in cells if policy_class(k.rpartition('|')[0]) == 'synergy' and k.rpartition('|')[2] == w and cells[k]['win_rate'] is not None]
        gap = (by['synergy'] - by['narrow']) * 100 if by.get('synergy') is not None and by.get('narrow') is not None else None
        paths = [(k.rpartition('|')[0], cells[k]) for k in cells if ':' in k.rpartition('|')[0] and policy_class(k.rpartition('|')[0]) == 'synergy' and k.rpartition('|')[2] == w]
        rates = [c['win_rate'] for _, c in paths if c['win_rate'] is not None]
        secs = [c['secs_median'] for _, c in paths if c['secs_median']]
        vw.append({'witch': w, 'label': WITCH_LABELS.get(w, w), 'ok': broken is None and len(seq) >= 2, 'judged': len(seq) >= 2, 'seq': seq, 'broken': broken,
                   'gap_pp': gap, 'gap_ok': (gap >= 50) if gap is not None else None, 'syn_min': min(syn) if syn else None,
                   'path_spread_pp': (max(rates) - min(rates)) * 100 if len(rates) > 1 else None,
                   'path_secs_spread_pct': (max(secs) - min(secs)) / max(secs) * 100 if len(secs) > 1 else None})
    judged = [x for x in vw if x['judged']]
    ok = bool(judged) and all(x['ok'] for x in judged)
    if not judged:
        headline = '서열을 판정할 수 없음 — 시너지·하나만 쌓기 같은 정책이 결과에 함께 들어 있어야 합니다'
    elif ok:
        chain = judged[0]['seq']
        text = chain[0]['label'] + ''.join((' > ' if i == 0 else ' ≥ ') + c['label'] for i, c in enumerate(chain[1:]))
        headline = '서열 성립 — %s (마녀 %d명 모두)' % (text, len(judged))
    else:
        bad = [x for x in judged if not x['ok']]
        headline = '서열이 서지 않음 — ' + ' / '.join('%s: %s' % (x['label'], x['broken']) for x in bad[:3])
    # power ÷ threat per beat
    beats = []
    for c in cells.values():
        for b in c['per_beat']:
            if b not in beats:
                beats.append(b)
    r_rows = []
    for cl in classes:
        row = {'cls': cl, 'label': CLASS_LABELS.get(cl, cl), 'beats': {}}
        for b in beats:
            vals = [c['per_beat'].get(b, {}).get('R') for k, c in cells.items() if policy_class(k.rpartition('|')[0]) == cl and isinstance(c['per_beat'].get(b), dict)]
            v = _mean(vals)
            tgt_tbl = p4.get(b) or {}
            tgt = tgt_tbl.get(cl) if cl in tgt_tbl else (tgt_tbl.get('narrow') if cl == 'narrow_ring' else None)
            row['beats'][b] = {'value': v, 'target': tgt, 'mark': _mark(v, tgt)}
        r_rows.append(row)
    # where runs ended
    death_total = {}
    n_runs = stalls = 0
    for c in cells.values():
        n_runs += c['n'] or 0
        stalls += c['stalls'] or 0
        for d in c['deaths']:
            k = (d['beat'], d['cause'])
            death_total[k] = death_total.get(k, 0) + d['count']
    deaths = [{'beat': b, 'cause': ca, 'count': n} for (b, ca), n in sorted(death_total.items(), key=lambda kv: -kv[1])[:12]]
    in_target = sum(1 for c in cells.values() if c['mark'] == 'in')
    judged_cells = sum(1 for c in cells.values() if c['mark'] is not None)
    return {'policies': policies, 'witches': witches, 'classes': classes, 'cells': cells, 'class_rows': class_rows,
            'verdict': {'ok': ok, 'headline': headline, 'witches': vw}, 'r_rows': r_rows, 'beats': beats, 'deaths': deaths,
            'stalls': stalls, 'runs': n_runs, 'in_target': in_target, 'judged_cells': judged_cells,
            'unknown_cell_keys': sorted(unknown_keys), 'unknown_top_keys': sorted(set(doc) - {'preset', 'mode', 'set', 'results'})}


# ---- meta (what the screen can edit) ------------------------------------------------------------
def _label(name):
    return LEAF_LABELS.get(name, name)


def _leaves(value, path, out, depth=0):
    """Numeric leaves as (path, value, editable). Keys with dots are shown read-only (the simulator's path syntax splits on dots)."""
    if depth > 8 or len(out) > 800:
        return
    if isinstance(value, bool):
        return
    if isinstance(value, (int, float)):
        out.append((path, value))
    elif isinstance(value, dict):
        for k, v in value.items():
            seg = str(k)
            _leaves(v, path + [('k', seg)], out, depth + 1)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            _leaves(v, path + [('i', i)], out, depth + 1)


def _path_text(parts):
    s = ''
    for kind, v in parts:
        s += ('[%d]' % v) if kind == 'i' else (('.' if s else '') + v)
    return s


def _rows(doc):
    leaves = []
    _leaves(doc, [], leaves)
    rows = []
    for parts, val in leaves:
        ok = all(kind == 'i' or re.fullmatch(r'[A-Za-z0-9_]+', v) for kind, v in parts)
        text = _path_text(parts)
        last = next((v for kind, v in reversed(parts) if kind == 'k'), '')
        idx = '[%d]' % parts[-1][1] if parts and parts[-1][0] == 'i' else ''
        rows.append({'key': None, 'path': text, 'label': _label(last) + (' ' + idx if idx else ''), 'name': last, 'value': val, 'editable': ok})
    return rows


def _keyed(prefix, rows):
    return [dict(r, key=(prefix + r['path']) if r['editable'] else None) for r in rows]


def spells_tree(cfg_spells):
    groups = []
    for sid, d in (cfg_spells.get('spells') or {}).items():
        if not isinstance(d, dict):
            continue
        groups.append({'id': sid, 'short': short_id(sid), 'role': d.get('role'), 'element': d.get('element'), 'rows': _keyed('spells.%s.' % short_id(sid), _rows(d))})
    common = {k: v for k, v in cfg_spells.items() if k != 'spells' and k not in SKIP_TOP}
    return groups, _keyed('spells.', _rows(common))


def rhythm_tree(rhythm, seal_kills):
    groups = []
    scalars = {k: v for k, v in rhythm.items() if isinstance(v, (int, float)) and not isinstance(v, bool)}
    if scalars:
        groups.append({'id': 'rhythm', 'title': '리듬 공통', 'rows': _keyed('rhythm.', _rows(scalars))})
    for i, b in enumerate(rhythm.get('beats') or []):
        bid = b.get('id', str(i))
        groups.append({'id': 'beat-' + str(bid), 'title': '%s 마디(%s)' % (BEAT_LABELS.get(bid, bid), bid),
                       'rows': [r for r in _keyed('rhythm.beats[%d].' % i, _rows({k: v for k, v in b.items() if k != 'id'})) if r['editable']]})
    for name, v in rhythm.items():
        if name == 'beats' or not isinstance(v, dict):
            continue
        groups.append({'id': 'r-' + name, 'title': BEAT_LABELS.get(name, name), 'rows': [r for r in _keyed('rhythm.%s.' % name, _rows(v)) if r['editable']]})
    if isinstance(seal_kills, list):
        groups.insert(0, {'id': 'seal', 'title': '구역 봉인', 'rows': [
            {'key': 'seal_kills[%d]' % i, 'path': 'seal_kills[%d]' % i, 'label': '봉인을 깨는 처치 수 (%d구역)' % (i + 1), 'name': 'seal_kills', 'value': v, 'editable': True}
            for i, v in enumerate(seal_kills) if isinstance(v, (int, float)) and not isinstance(v, bool)]})
    return groups


def calibration_summary(info, root=None):
    root = root or ROOT
    params = (info.get('config') or {}).get('calib') or {}
    counts = {}
    rows = []
    for k, v in params.items():
        counts[v.get('source') or '?'] = counts.get(v.get('source') or '?', 0) + 1
        rows.append({'key': 'calib.' + k, 'name': k, 'value': (info['config'].get('calib_current') or {}).get(k, v.get('value')), 'source': v.get('source'), 'note': v.get('note')})
    lines = []
    for base in [root] + list(root.parents)[:4]:
        f = base / '_local' / 'balsim' / 'calibrate.txt'
        if f.is_file():
            for ln in f.read_text(encoding='utf-8', errors='replace').splitlines():
                if 'Spearman' in ln or ln.startswith('전체') or '오차 30% 넘는' in ln:
                    lines.append(ln.strip()[:240])
            break
    return {'params': rows, 'source_counts': counts, 'report_lines': lines[:6]}


def meta(root=None, spells_id=None, preset=None):
    root = root or ROOT
    files = spell_files(root)
    chosen = spells_id if spells_id in {f['id'] for f in files} else default_spell_id(files)
    chosen_path = next((f['abs'] for f in files if f['id'] == chosen), None)
    presets = [p for p in preset_names(root)]
    chosen_preset = preset if preset in presets else ('spec1p' if 'spec1p' in presets else (presets[0] if presets else None))
    info = probe(root, chosen_preset, chosen_path)
    warnings = []
    if not info.get('ok'):
        warnings.append('시뮬레이터에 값을 물어보지 못했습니다: ' + str(info.get('probe_error', ''))[:200])
    if info.get('config_error'):
        warnings.append('설정을 읽지 못했습니다: ' + str(info['config_error'])[:200])
    cfg = info.get('config') or {}
    spells, common = (spells_tree(cfg['spells']) if cfg.get('spells') else ([], []))
    p7 = info.get('p7') or {}
    policies = info.get('policies') or []
    return {
        'banner': {'text': '모델의 답이며 게임의 답이 아니다.', 'trust': '믿어도 되는 것: 정책 사이의 서열, 값을 바꿨을 때의 방향', 'distrust': '안 되는 것: 정확한 승률, 초 단위 시각'},
        'spell_files': [{k: v for k, v in f.items() if k != 'abs'} for f in files], 'spells_id': chosen,
        'presets': [{'id': p, 'label': PRESET_LABELS.get(p, p)} for p in presets], 'preset': chosen_preset,
        'policies': [{'id': p, 'class': policy_class(p), 'label': policy_label(p)} for p in policies],
        'classes': [{'id': c, 'label': CLASS_LABELS.get(c, c), 'target': p7.get(c)} for c in dict.fromkeys(policy_class(p) for p in policies)],
        'witches': [{'id': w, 'label': WITCH_LABELS.get(w, w)} for w in (info.get('witches') or DEFAULT_WITCHES)],
        'spells': spells, 'spell_common': common, 'rhythm': rhythm_tree(cfg.get('rhythm') or {}, cfg.get('seal_kills')) if cfg else [],
        'calibration': calibration_summary(info, root), 'limits': {'seeds': MAX_SEEDS, 'runs': MAX_RUNS, 'timeout_s': TIMEOUT_S},
        'sim_present': (root / SIM_REL).is_file(), 'warnings': warnings,
        'gear_note': '장비 묶음: 숫자 하나(예 1.1 = 피해 ×1.1, 최대 생명 ×1.05) 또는 dmg=1.1,hp=1.05',
    }


def policy_label(p):
    cls, _, rest = p.partition(':')
    base = CLASS_LABELS.get(cls, cls)
    return base if not rest else '%s: %s' % (base, ' + '.join(ROLE_LABELS.get(x, x) for x in rest.split('_')))


# ---- experiments --------------------------------------------------------------------------------
def _atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    with temp.open('w', encoding='utf-8', newline='\n') as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def _exp_path(root, exp_id):
    if not isinstance(exp_id, str) or not EXP_ID_RE.match(exp_id):
        raise ValueError('실험 번호 형식이 맞지 않습니다')
    base = (lab_dir(root) / 'experiments').resolve()
    p = (base / (exp_id + '.json')).resolve()
    if not p.is_relative_to(base):
        raise ValueError('경로가 맞지 않습니다')
    return p


def save_experiment(payload, root=None, known=None):
    root = root or ROOT
    known = known or known_options(root)
    if not isinstance(payload, dict) or set(payload) - {'name', 'memo', 'settings', 'summary'}:
        raise ValueError('이름, 설정, 결과 요약, 메모만 저장합니다')
    name = payload.get('name')
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 60 or any(ord(c) < 32 for c in name):
        raise ValueError('실험 이름은 1~60자입니다')
    memo = payload.get('memo', '')
    if not isinstance(memo, str) or len(memo) > 4000:
        raise ValueError('메모는 4000자까지입니다')
    settings = validate_request(payload.get('settings') or {}, known)
    summary = payload.get('summary')
    if summary is not None:
        if not isinstance(summary, dict) or len(json.dumps(summary, ensure_ascii=False)) > 20000:
            raise ValueError('결과 요약이 너무 크거나 형식이 맞지 않습니다')
    now = time.localtime()
    exp_id = 'exp-%s-%s' % (time.strftime('%Y%m%d-%H%M%S', now), uuid.uuid4().hex[:4])
    record = {'id': exp_id, 'name': name.strip(), 'memo': memo, 'saved_at': time.strftime('%Y-%m-%d %H:%M:%S', now), 'settings': settings, 'summary': summary,
              'note': '모델 실험 기록입니다. 게임 데이터(chapter1/data)는 바뀌지 않았습니다.'}
    with STORE_LOCK:
        _atomic_write(_exp_path(root, exp_id), json.dumps(record, ensure_ascii=False, indent=1) + '\n')
    return record


def list_experiments(root=None, limit=200):
    root = root or ROOT
    base = lab_dir(root) / 'experiments'
    out, warnings = [], []
    if base.is_dir():
        for p in sorted(base.glob('exp-*.json'), reverse=True)[:limit]:
            try:
                v = json.loads(p.read_text(encoding='utf-8'))
                if isinstance(v, dict) and EXP_ID_RE.match(str(v.get('id', ''))):
                    out.append(v)
            except (OSError, ValueError):
                warnings.append('읽지 못한 실험 파일: ' + p.name)
    return {'experiments': out, 'warnings': warnings, 'dir': LAB_DIRNAME.as_posix() + '/experiments'}


def export_sets(payload, root=None, known=None):
    """Write a --set bundle JSON under _local/balance-lab/exports/ and return it. Never touches chapter1/data."""
    root = root or ROOT
    known = known or known_options(root)
    if not isinstance(payload, dict):
        raise ValueError('요청 형식이 맞지 않습니다')
    if 'id' in payload:
        p = _exp_path(root, payload['id'])
        if not p.is_file():
            raise ValueError('그 실험을 찾지 못했습니다')
        rec = json.loads(p.read_text(encoding='utf-8'))
        name, settings, memo, stem = rec.get('name', ''), rec.get('settings') or {}, rec.get('memo', ''), payload['id']
    else:
        name, settings, memo = str(payload.get('name') or '이름 없는 실험')[:60], payload.get('settings') or {}, str(payload.get('memo') or '')[:4000]
        stem = 'sets-%s-%s' % (time.strftime('%Y%m%d-%H%M%S'), uuid.uuid4().hex[:4])
    req = validate_request(settings, known)
    files = {f['id']: f for f in spell_files(root)}
    bundle = {'kind': 'balance-lab-sets', 'name': name, 'memo': memo, 'preset': req['preset'], 'spells_file': files[req['spells']]['path'] if req['spells'] in files else None,
              'witches': req['witches'], 'policies': req['policies'], 'seeds': req['seeds'], 'gear': req['gear'], 'sets': req['sets'],
              'set_args': ['%s=%s' % (s['key'], render_value(s['value'])) for s in req['sets']], 'command': command_text(req),
              'note': '모델 실험에서 바꾼 값입니다. 게임 데이터는 바뀌지 않았습니다. 데이터에 반영하려면 따로 배정하세요(spells.* 값은 주문 데이터, 나머지는 combat_tuning.json의 키).'}
    out_dir = (lab_dir(root) / 'exports').resolve()
    target = (out_dir / (stem + '.sets.json')).resolve()
    if not target.is_relative_to(out_dir):
        raise ValueError('경로가 맞지 않습니다')
    with STORE_LOCK:
        _atomic_write(target, json.dumps(bundle, ensure_ascii=False, indent=1) + '\n')
    return {'path': (LAB_DIRNAME / 'exports' / (stem + '.sets.json')).as_posix(), 'bundle': bundle}
