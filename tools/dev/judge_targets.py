#!/usr/bin/env python3
"""목표 판정표: tools/dev/targets.json 과 측정 JSON 여러 개를 맞대어 통과·미달·못 잼·미평가를 낸다.

  python tools/dev/judge_targets.py --out-md _local/tools/judge/table.md --out-json _local/tools/judge/table.json \\
      _local/w0/rhythm_9.json _local/builds2/sim-noequip.json _local/balsim/first_spec1p.json
  python tools/dev/judge_targets.py --check-constants --out-md _local/tools/judge/constants.md

원칙
- 이 도구는 측정 결과를 읽기만 한다. Godot를 돌리지 않고, 측정 도구와 목표 파일을 고치지 않는다.
- 목표는 targets.json 에만 있다. 측정 JSON 의 어느 키가 어느 지표인지는 이 파일의 대응표(MAPPERS) 하나에 있다.
- balance_sim 의 값은 "모델"이다. 실측과 한 표에 섞지 않는다.
- 사람 평가(kind=human)는 늘 "미평가"다. 사용자 플레이 기록(_local/playtests/)이 있으면 그 기록을 가리키기만 한다.
- 출력은 _local/ 아래에만 쓴다.
"""
import argparse
import ast
import json
import re
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DEFAULT_TARGETS = HERE / 'targets.json'
HEADER = '자동 조작 기준, 재미 미평가'
PASS, FAIL, NOMEAS, HUMAN, CONFLICT = '통과', '미달', '못 잼', '미평가', '충돌'
BASE_STATE_PREFIX = '기준 상태'
BEAT_LABEL = {'gi': '기', 'seung1': '승1', 'seung2': '승2', 'jeon_a': '전A', 'jeon_b': '전B', 'jeon_c': '전C'}
JEON = ('전A', '전B', '전C')


# ---------------------------------------------------------------- 범위 계산
def in_range(v, r):
    if v is None or r is None:
        return False
    if 'eq' in r:
        e = r['eq']
        if isinstance(e, bool):
            return bool(v) == e
        return abs(float(v) - float(e)) < 1e-9
    if 'min' in r and v < r['min'] - 1e-12:
        return False
    if 'max' in r and v > r['max'] + 1e-12:
        return False
    if 'min_excl' in r and not v > r['min_excl']:
        return False
    if 'max_excl' in r and not v < r['max_excl']:
        return False
    return True


def fv(x):
    if isinstance(x, bool):
        return '예' if x else '아니오'
    if isinstance(x, int):
        return str(x)
    if x is None:
        return '-'
    return format(x, '.4g')


def fmt_range(r, unit=''):
    if r is None:
        return '(수치 범위 없음)'
    if 'eq' in r:
        e = r['eq']
        s = '전 판' if e == 'all' else ('예' if e is True else ('아니오' if e is False else '=' + fv(e)))
        return s
    parts = []
    lo, hi = r.get('min'), r.get('max')
    if lo is not None and hi is not None:
        parts.append('%s~%s' % (fv(lo), fv(hi)))
    elif lo is not None:
        parts.append('≥' + fv(lo))
    elif hi is not None:
        parts.append('≤' + fv(hi))
    if 'min_excl' in r:
        parts.append('>' + fv(r['min_excl']))
    if 'max_excl' in r:
        parts.append('<' + fv(r['max_excl']))
    s = ' '.join(parts)
    return s + (' ' + unit if unit and unit not in ('bool', '판별', '기준', '기록', '질문', '비율', '승률', 'R', 'R(힘÷위협)') else '')


def result(verdict, value='', n=None, detail='', cond=''):
    return {'verdict': verdict, 'value': value, 'n': n, 'detail': detail, 'cond': cond}


def _sample_verdict(k, n, need, pf, value, what):
    """표본이 기준 판 수보다 적을 때: 남은 판이 모두 범위 안이어도 기준에 못 닿으면 미달, 아니면 못 잼."""
    best = (k + (need - n)) / need
    if best < pf - 1e-9:
        return result(FAIL, value, n, '표본 %d<%d이지만, 남은 판이 모두 범위 안이어도 기준(%s)에 못 닿는다' % (n, need, what))
    return result(NOMEAS, value, n, '표본 부족 %d<%d(문서의 "주력 셋 × 시드 11·12·13 이상"). 참고값이다' % (n, need))


def _basis(t):
    pf = t.get('pass_fraction', 1.0)
    return '판의 %.1f%% 이상(문서)' % (100 * pf) if 'pass_fraction' in t else '전 판(도구 기본, 문서에 비율 없음)'


def judge_values(values, t, total_runs=None, miss=0, unit=''):
    """판 단위 값 목록 → 범위 안 비율로 판정. values 에 None 이 있으면 그 판은 잴 수 없었음(제외)."""
    vals = [v for v in values if v is not None]
    n = len(vals) + miss
    need = (t.get('condition') or {}).get('min_runs')
    total = total_runs if total_runs is not None else n
    if n == 0:
        return result(NOMEAS, '-', 0, '그 마디·지표에 닿은 판이 없다')
    k = sum(1 for v in vals if in_range(v, t['range']))
    med = statistics.median(vals) if vals else None
    rng_txt = '%s~%s' % (fv(min(vals)), fv(max(vals))) if vals else '-'
    value = '중앙값 %s (%s) · 범위 안 %d/%d%s' % (fv(med), rng_txt, k, n, ('(입력 %d판 중)' % total) if total != n else '')
    pf = t.get('pass_fraction', 1.0)
    if need and n < need:
        return _sample_verdict(k, n, need, pf, value, _basis(t))
    return result(PASS if k / n >= pf - 1e-9 else FAIL, value, n, '기준: ' + _basis(t))


def judge_flags(flags, t, total_runs=None, label=''):
    flags = [f for f in flags if f is not None]
    n = len(flags)
    if n == 0:
        return result(NOMEAS, '-', 0, '판 없음')
    k = sum(1 for f in flags if f)
    need = (t.get('condition') or {}).get('min_runs')
    value = '%s %d/%d' % (label, k, n)
    pf = t.get('pass_fraction', 1.0)
    if need and n < need:
        return _sample_verdict(k, n, need, pf, value, _basis(t))
    return result(PASS if k / n >= pf - 1e-9 else FAIL, value, n, '기준: ' + _basis(t))


def judge_single(v, t, n=None, label=''):
    if v is None:
        return result(NOMEAS, '-', n, '값이 없다')
    return result(PASS if in_range(v, t['range']) else FAIL, label + fv(v), n)


# ---------------------------------------------------------------- 입력 읽기
def _json_lines(text, prefix):
    out = []
    for line in text.splitlines():
        if line.startswith(prefix + ' '):
            try:
                out.append(json.loads(line[len(prefix) + 1:]))
            except ValueError:
                pass
    return out


def load_input(path):
    p = Path(path)
    info = {'path': str(p), 'name': p.name, 'kind': None, 'family': 'real', 'data': None, 'cond': '', 'runs': None, 'error': None}
    try:
        text = p.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as e:
        info['error'] = '읽지 못함: %s' % e
        return info
    data = None
    try:
        data = json.loads(text)
    except ValueError:
        loot = _json_lines(text, 'LOOT_SIM')
        comb = _json_lines(text, 'COMBAT_MEASURE')
        if loot:
            data = loot[-1]
        elif comb:
            data = comb[-1]
            cf = _json_lines(text, 'COMBAT_COUNTERFACTUAL')
            if cf:
                data['counterfactual'] = cf[-1]
    if not isinstance(data, dict):
        info['error'] = 'JSON 도 LOOT_SIM / COMBAT_MEASURE 줄도 아니다'
        return info
    info['data'] = data
    if 'per_run_average' in data:
        info['kind'] = 'loot'
        info['runs'] = data.get('runs')
        info['cond'] = '드랍 시뮬레이션 %s판(코어 아님)' % data.get('runs')
    elif 'rows' in data and 'targets' in data and 'cases' in data:
        info['kind'] = 'combat'
        info['runs'] = len(data['rows'])
        sec_off = any(r.get('secondary_off') for r in data['rows'])
        info['cond'] = '%d판%s%s' % (len(data['rows']), ', 번개 합산' if data.get('arc_combined') else '', ', 보조 끔' if sec_off else '')
    elif 'groups' in data and 'cause_rules' in data:
        info['kind'] = 'builds'
        runs = data.get('runs') or []
        info['runs'] = len(runs)
        info['cond'] = '%d판, 리듬 %s, 장비 %s' % (len(runs), '켬' if data.get('rhythm_on') else '꺼짐', '없음' if data.get('no_equip') else '켬')
    elif 'runs' in data and 'bin_s' in data:
        info['kind'] = 'rhythm'
        runs = data['runs']
        info['runs'] = len(runs)
        on = any(str(r.get('beat_source', '')).startswith('beat_started') for r in runs)
        info['cond'] = '%d판, 리듬 %s' % (len(runs), '켬' if on else '꺼짐')
        info['rhythm_on'] = on
    elif 'results' in data and 'preset' in data:
        info['kind'] = 'model'
        info['family'] = 'model'
        res = data['results']
        ns = sorted({v.get('n') for v in res.values()})
        info['runs'] = sum(v.get('n', 0) for v in res.values())
        info['cond'] = '모델 %s, 칸 %d × %s판(장비·리듬은 JSON에 없음)' % (data.get('preset'), len(res), '/'.join(str(x) for x in ns))
    else:
        info['error'] = '알 수 없는 측정 JSON(키: %s)' % ', '.join(list(data.keys())[:6])
    return info


def load_targets(path):
    doc = json.loads(Path(path).read_text(encoding='utf-8'))
    return doc


def load_playtests(folder):
    recs = []
    d = Path(folder) if folder else None
    if d is None or not d.is_dir():
        return recs
    for p in sorted(d.glob('*.json')):
        try:
            v = json.loads(p.read_text(encoding='utf-8'))
            if isinstance(v, dict) and isinstance(v.get('answers'), dict):
                v['id'] = p.stem
                recs.append(v)
        except (OSError, ValueError):
            continue
    return recs


def norm(s):
    return re.sub(r'\s+', '', str(s or '')).strip('.')


def playtest_pointer(t, recs):
    q = norm(t.get('question') or t['label'])
    hits = []
    for r in recs:
        for a in r['answers'].values():
            if isinstance(a, dict) and a.get('text') and (norm(a['text']) == q or q in norm(a['text']) or norm(a['text']) in q):
                if a.get('score') or a.get('note') or a.get('comment'):
                    hits.append((r.get('played_at', ''), r['id'], a.get('score')))
    if not hits:
        return None
    hits.sort()
    last = hits[-1]
    return '플레이 기록 %d건(최근 %s, 점수 %s) — 도구는 판정하지 않는다' % (len(hits), last[1], last[2] if last[2] else '-')


# ---------------------------------------------------------------- 대응표: 측정 JSON 의 키 → 지표
# 각 함수는 (t, inp) 를 받아 result(...) 를 돌려주거나, 이 입력으로는 잴 수 없으면 None 을 돌려준다.
# t 는 목표(충돌 항목은 후보의 range·pass_fraction 으로 바꾼 사본), inp 는 load_input 의 결과.
def _rhythm_beats(inp, bid):
    lab = BEAT_LABEL[bid]
    out = []
    for r in inp['data']['runs']:
        b = next((x for x in r.get('beats', []) if x.get('label') == lab and x.get('reached', True)), None)
        out.append(b)
    return out


def m_a2(metric):
    def fn(t, inp):
        bid = t['key'].split('.')[1]
        beats = _rhythm_beats(inp, bid)
        vals = [b.get(metric) if b else None for b in beats]
        r = judge_values(vals, t, total_runs=len(beats))
        r['cond'] = inp['cond']
        return r
    return fn


def m_rhythm_hpk(t, inp):
    bid = t['key'].split('.')[-1]
    vals = [b.get('prim_hits_per_kill') if b else None for b in _rhythm_beats(inp, bid)]
    return judge_values(vals, t, total_runs=len(vals))


def m_kill_order(t, inp):
    flags = []
    for r in inp['data']['runs']:
        k = {b.get('label'): b.get('kpm') for b in r.get('beats', []) if b.get('reached', True)}
        seq = [k.get(x) for x in ('기', '승1', '승2', '전A')]
        flags.append(None not in seq and seq[0] < seq[1] < seq[2] < seq[3])
    cross = inp['data'].get('cross', {}).get('kpm_ordered_runs')
    r = judge_flags(flags, t, label='처치 속도 순서가 선 판')
    if cross is not None:
        r['detail'] += ' (measure_rhythm 의 kpm_ordered_runs=%s)' % cross
    return r


def m_rhythm_seconds(t, inp):
    runs = inp['data']['runs']
    vals = [r['secs'] for r in runs if r.get('mode') == 'victory']
    miss = sum(1 for r in runs if r.get('mode') != 'victory')
    return judge_values(vals, t, total_runs=len(runs), miss=miss)


def m_rhythm_defeats(t, inp):
    runs = inp['data']['runs']
    d = sum(1 for r in runs if r.get('mode') == 'defeat')
    need = (t.get('condition') or {}).get('min_runs')
    v = '패배 %d/%d' % (d, len(runs))
    if d > t['range']['max']:
        return result(FAIL, v, len(runs), '패배가 이미 기준을 넘었다')
    if need and len(runs) < need:
        return result(NOMEAS, v, len(runs), '표본 부족 %d<%d. 참고값이다' % (len(runs), need))
    return result(PASS, v, len(runs))


def _grace(inp):
    return [(r['summary'].get('grace_times') or [], r['summary']) for r in inp['data']['runs']]


def m_grace(which):
    def fn(t, inp):
        vals = []
        for times, s in _grace(inp):
            if which == 'first':
                vals.append(times[0] if times else None)
            elif which == 'in60':
                vals.append(sum(1 for x in times if x <= 60))
            elif which == 'gap_median':
                d = [b - a for a, b in zip(times, times[1:])]
                vals.append(statistics.median(d) if d else None)
            elif which == 'gap_max':
                d = [b - a for a, b in zip(times, times[1:])]
                vals.append(max(d) if d else None)
            elif which == 'after_270':
                vals.append(sum(1 for x in times if x > 270))
        return judge_values(vals, t, total_runs=len(vals))
    return fn


def m_hit_peak_in_jeon(t, inp):
    flags = []
    for r in inp['data']['runs']:
        bs = [b for b in r.get('beats', []) if b.get('reached', True)]
        if not bs:
            flags.append(None)
            continue
        a = max(bs, key=lambda b: b.get('hits_pm', 0))['label']
        d = max(bs, key=lambda b: b.get('dmg30', 0))['label']
        flags.append(a in JEON and d in JEON)
    return judge_flags(flags, t, total_runs=len(flags), label='피격·피해 최대가 전 마디인 판')


def m_combat(field, label=None):
    def fn(t, inp):
        rows = inp['data']['rows']
        vals = []
        for r in rows:
            v = r.get(field)
            if field == 'friendly_peak_1s' and inp['data'].get('arc_combined') and str(r.get('primary')).endswith('.arc'):
                v = r.get('combined_peak_1s')
            vals.append(v)
        if field == 'heavy_min_gap_ticks':   # 큰 한 방이 둘 미만이라 간격이 없는 판은 위반이 아니다(measure_combat 과 같은 규칙)
            flags = [(v is None) or in_range(v, t['range']) for v in vals]
            known = [v for v in vals if v is not None]
            r = judge_flags(flags, t, total_runs=len(rows), label='간격 ≥%s틱인 판(최소 간격 중앙값 %s, 간격 없음 %d판)' % (fv(t['range'].get('min')), fv(statistics.median(known)) if known else '-', len(vals) - len(known)))
            return r
        if field == 'cap_fraction':
            vals = [v if v is not None else -1 for v in vals]
        return judge_values(vals, t, total_runs=len(rows))
    return fn


def m_combat_seconds(t, inp):
    rows = inp['data']['rows']
    vals = [r['seconds'] for r in rows if not r.get('defeat')]
    return judge_values(vals, t, total_runs=len(rows), miss=sum(1 for r in rows if r.get('defeat')))


def m_combat_share_pre(t, inp):
    rows = inp['data']['rows']
    return judge_values([r.get('hero_share_pre_evo') for r in rows], t, total_runs=len(rows))


def m_combat_threat(t, inp):
    p = t.get('params') or {}
    rows = inp['data']['rows']
    flags = [(r['min_hp_ratio'] < p['min_hp_ratio_below']) or (r['burst60'] >= p['burst60_at_least']) for r in rows]
    return judge_flags(flags, t, total_runs=len(rows), label='위협 기준을 채운 판')


def m_combat_defeats(t, inp):
    rows = inp['data']['rows']
    d = sum(1 for r in rows if r.get('defeat'))
    need = (t.get('condition') or {}).get('min_runs')
    v = '패배 %d/%d' % (d, len(rows))
    if d > t['range']['max']:
        return result(FAIL, v, len(rows), '패배가 이미 기준을 넘었다')
    if need and len(rows) < need:
        return result(NOMEAS, v, len(rows), '표본 부족 %d<%d. 참고값이다' % (len(rows), need))
    return result(PASS, v, len(rows))


def m_combat_counterfactual(t, inp):
    cf = inp['data'].get('counterfactual')
    if not cf:
        return None
    return result(PASS if cf.get('pass') else FAIL, '반사실 통과=%s (판 길이 중앙값 +%.1f%%, 패배 켬 %s / 끔 %s)' % (cf.get('pass'), 100 * cf.get('median_gain', 0), cf.get('defeats_on'), cf.get('defeats_off')), len(cf.get('cases', [])))


def m_loot(field):
    def fn(t, inp):
        v = inp['data']['per_run_average'].get(field)
        return judge_single(v, t, inp['data'].get('runs'), '판당 평균 ')
    return fn


# ---- sim_builds (실제 코어, 정책별)
def _cells(inp, policy):
    return {g['primary']: g for k, g in inp['data']['groups'].items() if g.get('policy') == policy}


def _need_base(t, inp):
    """기준 상태(장비 없음) 목표인데 입력이 장비를 켠 판이면 건너뛴다."""
    st = (t.get('condition') or {}).get('state', '')
    return st.startswith(BASE_STATE_PREFIX) and inp['kind'] == 'builds' and not inp['data'].get('no_equip')


def m_builds_win(policy):
    def fn(t, inp):
        cells = _cells(inp, policy)
        if not cells:
            return None
        parts, ok, n = [], [], 0
        for prim in sorted(cells):
            g = cells[prim]
            parts.append('%s %d%%(n=%d)' % (prim, round(100 * g['win_rate']), g['n']))
            ok.append(in_range(g['win_rate'], t['range']))
            n += g['n']
        r = result(PASS if all(ok) else FAIL, ' / '.join(parts), n, '마녀 칸마다 범위 안이어야 통과. 칸당 판 수는 문서의 10판과 다를 수 있다')
        return r
    return fn


def m_builds_synergy_proxy(t, inp):
    cells = _cells(inp, 'synergy_now')
    note = ''
    if cells:
        note = ' 참고: synergy_now(현재 데이터의 두 시너지) 승률 ' + ' / '.join('%s %d%%' % (k, round(100 * g['win_rate'])) for k, g in sorted(cells.items())) + ' — 판 안 스킬 구성 구현 전의 대용품이라 판정에 쓰지 않는다'
    return result(NOMEAS, '-', None, '실제 코어에는 synergy 정책이 아직 없다.' + note)


def m_builds_stall(t, inp):
    g = inp['data']['groups']
    tot = sum(x.get('timeouts', 0) for x in g.values())
    n = sum(x.get('n', 0) for x in g.values())
    by = {}
    for x in g.values():
        by[x['policy']] = by.get(x['policy'], 0) + x.get('timeouts', 0)
    detail = '정책별: ' + ', '.join('%s %d' % (k, v) for k, v in sorted(by.items()) if v) if tot else ''
    return result(PASS if tot <= t['range']['max'] else FAIL, '600초 제한 판 %d/%d' % (tot, n), n, detail)


def _pool_deaths(inp, policy):
    times, causes = [], {'crowd': 0, 'strong': 0, 'both': 0, 'other': 0}
    for g in _cells(inp, policy).values():
        times += g.get('death_times', [])
        for k, v in g.get('defeat_causes', {}).items():
            causes[k] = causes.get(k, 0) + v
    return times, causes


def m_builds_death_time(policy):
    def fn(t, inp):
        if not _cells(inp, policy):
            return None
        times, _ = _pool_deaths(inp, policy)
        if not times:
            return result(NOMEAS, '진 판 0', 0, '진 판이 없어 진 시각 중앙값이 없다')
        return judge_single(statistics.median(times), t, len(times), '진 시각 중앙값 ')
    return fn


def m_builds_early(policy):
    def fn(t, inp):
        if not _cells(inp, policy):
            return None
        times, _ = _pool_deaths(inp, policy)
        c = sum(1 for x in times if x < 120)
        return result(PASS if c <= t['range']['max'] else FAIL, '2:00 전 패배 %d판(진 판 %d)' % (c, len(times)), len(times))
    return fn


def m_builds_cause(policy, cause):
    def fn(t, inp):
        if not _cells(inp, policy):
            return None
        times, causes = _pool_deaths(inp, policy)
        d = sum(causes.values())
        if d == 0:
            return result(NOMEAS, '진 판 0', 0, '진 판이 없다')
        share = causes.get(cause, 0) / d
        return judge_single(share, t, d, '%s %d/%d = ' % (cause, causes.get(cause, 0), d))
    return fn


# ---- balance_sim (모델)
def _mcells(inp, cls=None, exact=None):
    out = []
    for k, v in inp['data']['results'].items():
        pol, wit = k.split('|')
        if exact is not None and pol != exact:
            continue
        if cls is not None and pol.split(':')[0] != cls:
            continue
        out.append((pol, wit, v))
    return out


def m_model_win(policy):
    def fn(t, inp):
        cells = _mcells(inp, exact=policy)
        if not cells:
            return None
        parts = ['%s %d%%(n=%d)' % (w, round(100 * v['win_rate']), v['n']) for _, w, v in cells]
        ok = [in_range(v['win_rate'], t['range']) for _, _, v in cells]
        return result(PASS if all(ok) else FAIL, ' / '.join(parts), sum(v['n'] for _, _, v in cells), '마녀 칸마다 범위 안이어야 통과')
    return fn


def m_model_synergy_general(t, inp):
    cells = _mcells(inp, exact='synergy')
    if not cells:
        return None
    wins = sum(v['win_rate'] * v['n'] for _, _, v in cells)
    n = sum(v['n'] for _, _, v in cells)
    return judge_single(wins / n, t, n, '%d/%d판 = ' % (round(wins), n))


def _paths_ok(inp, t):
    per = {}
    for pol, wit, v in _mcells(inp, cls='synergy'):
        if ':' in pol:
            per.setdefault(wit, []).append((pol.split(':')[1], in_range(v['win_rate'], {'min': 0.9, 'max': 1.0})))
    return per


def m_model_synergy_paths(t, inp):
    per = _paths_ok(inp, t)
    if not per:
        return None
    parts = ['%s %d/%d길' % (w, sum(1 for _, ok in v if ok), len(v)) for w, v in sorted(per.items())]
    ok = all(sum(1 for _, o in v if o) >= 3 for v in per.values())
    return result(PASS if ok else FAIL, ' / '.join(parts) + ' (승률 0.9 이상인 길)', sum(len(v) for v in per.values()), '"길 셋이 각각 10판 중 9 이상"을 마녀마다 승률 0.9 이상인 길 ≥ 3 으로 읽음(해석)')


def m_model_synergy_lanes(t, inp):
    per = _paths_ok(inp, t)
    if not per:
        return None
    parts, ok = [], True
    for w, v in sorted(per.items()):
        good = [p for p, o in v if o]
        noring = [p for p in good if 'ring' not in p]
        parts.append('%s %d길(원형 없는 짝 %d)' % (w, len(good), len(noring)))
        ok = ok and len(good) >= t['range']['min'] and len(noring) >= 1
    return result(PASS if ok else FAIL, ' / '.join(parts), sum(len(v) for v in per.values()), '승률 0.9 이상인 길 ≥ 3 이고 원형 없는 짝 ≥ 1. 문서의 "최소 2"는 해석이 갈려 쓰지 않았다')


def _wr(inp, pol):
    return {w: v['win_rate'] for p, w, v in _mcells(inp, exact=pol)}


def m_model_order(t, inp):
    seqs = [_wr(inp, p) for p in ('synergy', 'narrow', 'random', 'spread', 'worst')]
    if any(not s for s in seqs):
        return None
    parts, ok = [], True
    for w in sorted(seqs[0]):
        a, b, c, d, e = [s.get(w) for s in seqs]
        good = a > b and b >= c and c > d and d > e
        ok = ok and good
        parts.append('%s %s' % (w, ' > '.join('%d%%' % round(100 * x) for x in (a, b, c, d, e)) + ('' if good else ' (깨짐)')))
    return result(PASS if ok else FAIL, ' / '.join(parts), None, 'synergy > narrow ≥ random > spread > worst')


def m_model_gap(t, inp):
    s, nr = _wr(inp, 'synergy'), _wr(inp, 'narrow')
    if not s or not nr:
        return None
    gaps = {w: 100 * (s[w] - nr[w]) for w in s if w in nr}
    ok = all(in_range(g, t['range']) for g in gaps.values())
    return result(PASS if ok else FAIL, ' / '.join('%s %+.0f%%p' % (w, g) for w, g in sorted(gaps.items())), len(gaps))


def m_model_stall(t, inp):
    cells = _mcells(inp)
    n = sum(v['n'] for _, _, v in cells)
    tot = sum(v.get('stalls', 0) for _, _, v in cells)
    return result(PASS if tot <= t['range']['max'] else FAIL, '정체 %d/%d판' % (tot, n), n)


def m_model_r(t, inp):
    _, bid, pol = t['key'].split('.')
    lab = BEAT_LABEL[bid]
    vals = []
    for _, _, v in _mcells(inp, cls=pol):
        if pol == 'narrow' and False:
            continue
        r = (v.get('per_beat') or {}).get(lab, {}).get('R')
        if r is not None:
            vals.append(r)
    if not vals:
        return None
    return judge_single(sum(vals) / len(vals), t, len(vals), '칸 R 평균 ')


def m_model_deaths(policy):
    def pool(inp):
        d = []
        for _, _, v in _mcells(inp, exact=policy):
            d += v.get('deaths', [])
        return d
    return pool


def m_model_death_time(policy):
    def fn(t, inp):
        if not _mcells(inp, exact=policy):
            return None
        d = m_model_deaths(policy)(inp)
        if not d:
            return result(NOMEAS, '진 판 0', 0, '진 판이 없다')
        return judge_single(statistics.median([x['secs'] for x in d]), t, len(d), '진 시각 중앙값 ')
    return fn


def m_model_early(policy):
    def fn(t, inp):
        if not _mcells(inp, exact=policy):
            return None
        d = m_model_deaths(policy)(inp)
        c = sum(1 for x in d if x['secs'] < 120)
        return result(PASS if c <= t['range']['max'] else FAIL, '2:00 전 패배 %d판(진 판 %d)' % (c, len(d)), len(d))
    return fn


def m_model_cause(policy, cause):
    def fn(t, inp):
        if not _mcells(inp, exact=policy):
            return None
        d = m_model_deaths(policy)(inp)
        if not d:
            return result(NOMEAS, '진 판 0', 0, '진 판이 없다')
        c = sum(1 for x in d if x['cause'] == cause)
        return judge_single(c / len(d), t, len(d), '%s %d/%d = ' % (cause, c, len(d)))
    return fn


# kind -> 함수. 키는 목표 키 또는 접두("a2.*.alive_avg" 는 아래 루프에서 펼친다)
MAPPERS = {}


def reg(key, kind, fn):
    MAPPERS.setdefault(key, {})[kind] = fn


for _b in BEAT_LABEL:
    for _m in ('alive_avg', 'alive_max', 'kpm', 'hits_pm', 'dmg30'):
        reg('a2.%s.%s' % (_b, _m), 'rhythm', m_a2(_m))
for _b in ('gi', 'seung1', 'seung2', 'jeon_a'):
    reg('g1.hits_per_kill.%s' % _b, 'rhythm', m_rhythm_hpk)
reg('g1.kill_order', 'rhythm', m_kill_order)
reg('g1.hit_peak_in_jeon', 'rhythm', m_hit_peak_in_jeon)
for _g in ('first', 'in60', 'gap_median', 'gap_max', 'after_270'):
    reg('g1.grace.' + _g, 'rhythm', m_grace(_g))
reg('q2.seconds', 'rhythm', m_rhythm_seconds)
reg('q2.defeats', 'rhythm', m_rhythm_defeats)

reg('q2.seconds', 'combat', m_combat_seconds)
reg('q2.friendly_peak_1s', 'combat', m_combat('friendly_peak_1s'))
reg('q2.hero_share_pre', 'combat', m_combat_share_pre)
reg('q2.hero_share_post', 'combat', m_combat('hero_share_post_evo'))
reg('q2.primary_hit_share', 'combat', m_combat('primary_hit_share'))
reg('q2.secondary_contribution', 'combat', m_combat('secondary_contribution'))
reg('q2.secondary_counterfactual', 'combat', m_combat_counterfactual)
reg('q2.attacks_per_min', 'combat', m_combat('attacks_per_min'))
reg('q2.threat', 'combat', m_combat_threat)
reg('q2.defeats', 'combat', m_combat_defeats)
reg('q2.heavy_gap', 'combat', m_combat('heavy_min_gap_ticks'))
reg('q2.cap_fraction', 'combat', m_combat('cap_fraction'))

for _k, _f in (('q4.rare', 'rare'), ('q4.jewelry', 'jewelry'), ('q4.legendary', 'legendary'), ('q4.unique', 'unique')):
    reg(_k, 'loot', m_loot(_f))

for _p, _k in (('narrow', 'narrow'), ('random', 'random'), ('spread', 'spread'), ('worst', 'worst')):
    reg('p7.win.' + _k, 'builds', m_builds_win(_p))
    reg('p7.win.' + _k, 'model', m_model_win(_p))
reg('p7.win.narrow_ring', 'model', m_model_win('narrow_ring'))
reg('p7.win.synergy', 'builds', m_builds_synergy_proxy)
reg('p7.win.synergy_path', 'builds', m_builds_synergy_proxy)
reg('p7.win.synergy', 'model', m_model_synergy_general)
reg('p7.win.synergy_path', 'model', m_model_synergy_paths)
reg('p7.synergy_lanes', 'model', m_model_synergy_lanes)
reg('p7.order', 'model', m_model_order)
reg('p7.synergy_minus_narrow', 'model', m_model_gap)
reg('p7.stall', 'builds', m_builds_stall)
reg('p7.stall', 'model', m_model_stall)
reg('p7.narrow.death_time', 'builds', m_builds_death_time('narrow'))
reg('p7.narrow.death_time', 'model', m_model_death_time('narrow'))
reg('p7.narrow.cause_crowd', 'builds', m_builds_cause('narrow', 'crowd'))
reg('p7.narrow.cause_crowd', 'model', m_model_cause('narrow', '깔림'))
reg('p7.narrow_ring.cause_strong', 'model', m_model_cause('narrow_ring', '강한 적에 막힘'))
reg('p7.spread.death_time', 'builds', m_builds_death_time('spread'))
reg('p7.spread.death_time', 'model', m_model_death_time('spread'))
reg('p7.spread.early', 'builds', m_builds_early('spread'))
reg('p7.spread.early', 'model', m_model_early('spread'))
reg('p7.worst.early', 'builds', m_builds_early('worst'))
reg('p7.worst.early', 'model', m_model_early('worst'))
for _b in ('gi', 'seung1', 'seung2', 'jeon_a', 'jeon_b'):
    for _p in ('synergy', 'narrow', 'random', 'spread', 'worst'):
        reg('p4.%s.%s' % (_b, _p), 'model', m_model_r)

# 못 잼일 때 "그것을 재려면 필요한 것". 앞의 접두가 먼저 맞는다.
NEEDS = [
    ('q1.regression', '`run_all.py --json` 결과를 이 도구가 읽는 대응이 없다(회귀 결과 JSON 연결 필요)'),
    ('q1.script_errors', '`run_dev.py` 실행 로그에서 스크립트 오류를 세는 입력이 없다'),
    ('q1.perf', '프레임 측정기(1920×1080 실행 빌드, 3회) 출력 JSON 대응이 없다(TOOLS-REVIEW T4 후보)'),
    ('q1.save', '프로필 검사 결과 대응이 없다'),
    ('q1.determinism', '골든 비교 결과 대응이 없다'),
    ('q2.hero_height', '화면 캡처에서 주인공 높이를 재는 도구 출력(TOOLS-REVIEW T2 후보)'),
    ('q2.core_tick_p95', '이전 기준값 파일이 필요하다(measure_combat 의 step_usec_p50_p95_p99 를 두 시점 비교)'),
    ('q2.secondary_counterfactual', '`measure_combat.gd --secondary-off` 로 반사실을 켠 출력이 필요하다'),
    ('q2.', '`measure_combat.gd --out=` 출력(COMBAT_MEASURE JSON) 또는 그 stdout 파일'),
    ('q3.', '화면 배치 자동 점검 도구가 없다(TOOLS-REVIEW T3 후보)'),
    ('q4.wear_slots', '`report_run_loot.gd` 출력 대응이 없다(착용 칸 수 집계)'),
    ('q4.', '`sim_loot.gd` 의 LOOT_SIM 줄을 담은 파일(이 도구는 --out 이 없는 그 출력을 텍스트로도 읽는다)'),
    ('a2.', '`measure_rhythm.gd --out=` 출력이 필요하다'),
    ('g1.grace.evolve', '주력 진화 시각이 measure_rhythm JSON 에 없다(`measure_combat.gd --xp-curve` 의 evolve_tick 대응 필요)'),
    ('g1.wave_trough', 'measure_rhythm 이 파도 주기별 골 끝의 살아 있는 적 수를 내지 않는다(wave_crests 개수만 있음)'),
    ('g1.drop_event', '`report_run_loot.gd` 의 출처 집계(item_drop.source) 대응이 없다'),
    ('g1.chest', '`measure_rhythm.gd --pilot-extras`(상자·사당을 놓는 측정) 가 아직 없다'),
    ('g1.shrine', '`measure_rhythm.gd --pilot-extras` 가 아직 없다'),
    ('g1.reaction_share', '반응 집계(`hit.reaction`)가 measure_combat 에 아직 없다(D12 F2)'),
    ('g1.ultimate_count', '궁극기가 아직 없다(D12 K장). measure_rhythm 에 궁극기 집계 필요'),
    ('g1.reward_gap', '반응·궁극기·드러남 시각이 JSON 에 없다. 지금 JSON 에는 은총 시각만 있다'),
    ('g1.guard_places', 'C6 의 목표 수치를 이번에 옮기지 않았다. 그 뒤 `measure_rhythm.gd --pilot-extras` 필요'),
    ('g1.perf_alive_p90', '목표 수치가 없는 기록 항목이다'),
    ('g1.', '`measure_rhythm.gd --out=` 출력이 필요하다'),
    ('p4.single', '`sim_power.gd`(짧은 시험장, D12 P3·J1) 가 아직 없다. balance_sim JSON 에는 단일 R 이 없다(텍스트 보고서에만 있다)'),
    ('p4.step_max', '`threat_curve.gd`(D12 P9) 가 아직 없다'),
    ('p4.synergy_cap_jeon', '`sim_power.gd` 가 아직 없다(표의 전 A·전 B 상한과 겹친다)'),
    ('p4.det_share', '터뜨림·반응 몫을 "승 2 이후"로 자른 출력이 없다(balance_sim 의 det_share_mean 은 판 전체 평균이라 정의가 다르다)'),
    ('p4.', '`sim_power.gd`(실측 힘÷위협)가 아직 없다. 지금은 balance_sim 모델 값만 있다'),
    ('p7.win', '`sim_builds.gd --no-equip --runs=10` 출력 중 해당 정책 칸이 없다(실제 코어에는 synergy·narrow_ring 정책이 아직 없다)'),
    ('p7.order', 'synergy 정책이 실제 코어에 없다(판 안 스킬 구성 D12 B0 구현 뒤)'),
    ('p7.synergy_minus_narrow', 'synergy 정책이 실제 코어에 없다'),
    ('p7.random.death_time', '문서가 마디 이름("승 2 끝~전 A")으로 적어 수치 판정 규칙이 정해지지 않았다'),
    ('p7.synergy.hp_end', 'JSON 에 우두머리 처치 때 남은 생명이 승리 판 평균(hp_end_mean_wins)으로만 있고 중앙값이 없다. synergy 정책도 없다'),
    ('p7.lane_time_gap', 'synergy:<짝> 정책이 실제 코어에 없다. 모델 JSON 의 secs_median 은 승리 판만의 값이 아니다'),
    ('p7.evolve_reach', '진화 카드 시각(레벨 8 안)을 정책별로 내는 출력이 없다'),
    ('p7.readable', '압력(pressure) 이벤트와 죽기 전 경고 기록이 아직 없다(D12 P8 코어 구현 뒤)'),
    ('p7.narrow_ring', 'narrow_ring 정책이 실제 코어에 없다'),
    ('p7.', '`sim_builds.gd --no-equip` 출력 또는 balance_sim 출력이 필요하다'),
    ('p10.', '장비 고정 묶음(`--gear-kit=`)과 `sim_power.gd` 가 아직 없다(sim_builds 의 장비 켠 판은 고정 묶음이 아님)'),
    ('prog.', '`sim_progression.gd --out=` 출력 대응이 이 도구에 아직 없다'),
]


def need_text(t):
    for pref, txt in NEEDS:
        if t['key'].startswith(pref):
            return txt
    return t.get('doc_tool') or '이 도구의 대응표에 없다'


# ---------------------------------------------------------------- 판정 실행
SELF_RANGE = ('q2.threat', 'q2.secondary_counterfactual', 'p7.order')   # 범위가 아니라 규칙으로 판정하는 목표


def eval_target(t, inp):
    """(t, 입력) → result 또는 None. 충돌 항목은 후보별로 판정해 합친다."""
    fn = MAPPERS.get(t['key'], {}).get(inp['kind'])
    if fn is None:
        return None
    if _need_base(t, inp):
        return 'SKIP:조건 불일치(장비 켬 ↔ 목표는 기준 상태: 장비 없음)'
    c = t.get('conflict')
    if not c:
        if t.get('range') is None and t['key'] not in SELF_RANGE:
            return result(NOMEAS, '-', None, '목표에 판정할 수치 범위가 없다')
        r = fn(t, inp)
        if r is not None:
            r['cond'] = inp['cond']
        return r
    subs = []
    for cand in c['candidates']:
        tc = dict(t, range=cand.get('range'), pass_fraction=cand.get('pass_fraction', 1.0))
        if cand.get('range') is None:
            subs.append((cand, result(NOMEAS, '-', None, '후보에 수치 범위가 없다')))
            continue
        r = fn(tc, inp)
        if r is None:
            return None
        subs.append((cand, r))
    judged = [r for cand, r in subs if cand.get('range')]   # 수치 범위가 없는 후보는 판정에서 뺀다(상세에는 적는다)
    verdicts = {r['verdict'] for r in judged}
    verdict = (next(iter(verdicts)) if len(verdicts) == 1 else CONFLICT) if judged else NOMEAS
    first = judged[0] if judged else subs[0][1]
    detail = '후보별: ' + ' / '.join('%s %s %s' % (cand['id'], fmt_range(cand.get('range'), t.get('unit', '')) if cand.get('range') else '범위 없음', r['verdict']) for cand, r in subs)
    return result(verdict, first['value'], first['n'], detail, inp['cond'])


def target_text(t):
    c = t.get('conflict')
    if c:
        return ' | '.join('%s: %s' % (cd['id'], fmt_range(cd.get('range'), t.get('unit', '')) if cd.get('range') else '범위 없음') for cd in c['candidates'])
    if t['key'] == 'q2.threat':
        p = t['params']
        return '최저 생명 비 <%s 또는 60초 창 ≥%s' % (fv(p['min_hp_ratio_below']), fv(p['burst60_at_least']))
    s = fmt_range(t.get('range'), t.get('unit', ''))
    pf = t.get('pass_fraction')
    if pf is not None and pf < 1 and t.get('range') is not None and t['range'].get('eq') != 'all' and t.get('unit', '') in ('초', '번', '마리', '마리/분', '회/분', '명중/처치', '개/판', 'R(힘÷위협)', '비율', '판', '개', '틱'):
        s += ' (판의 %.0f%% 이상)' % (100 * pf)
    elif pf is not None and pf < 1 and t['range'] is not None and t['range'].get('eq') == 'all':
        s += ' (판의 %.0f%% 이상)' % (100 * pf)
    return s


def source_text(t):
    s = t['source']
    out = '%s %s' % (Path(s['doc']).name.split('-')[0] if 'specs' in s['doc'] else Path(s['doc']).name.replace('.ko.md', ''), s['section'])
    for e in t.get('extra_sources', []) or []:
        out += ' · ' + '%s %s' % (Path(e['doc']).name.split('-')[0] if 'specs' in e['doc'] else Path(e['doc']).name.replace('.ko.md', ''), e['section'])
    return out + (' [충돌]' if t.get('conflict') else '')


def run_judge(targets_doc, inputs, playtests):
    rows, skipped = [], []
    inps = [i for i in inputs if i['kind']]
    for i in inputs:
        if not i['kind']:
            skipped.append({'input': i['name'], 'reason': i['error'] or '대응 없음', 'count': None})
    skip_count = {}
    for t in targets_doc['targets']:
        base = {'key': t['key'], 'group': t['group'], 'label': t['label'], 'kind': t['kind'], 'status': t['status'],
                'target': target_text(t), 'source': source_text(t), 'conflict': bool(t.get('conflict')), 'unit': t.get('unit', ''),
                'family': 'real', 'input': None, 'cond': '', 'value': '', 'n': None, 'verdict': None, 'detail': ''}
        if t['kind'] == 'human':
            r = dict(base, verdict=HUMAN, value='-', detail='사용자 플레이로만 채운다')
            ptr = playtest_pointer(t, playtests)
            if ptr:
                r['detail'] = ptr
            rows.append(r)
            continue
        got = []
        for i in inps:
            res = eval_target(t, i)
            if isinstance(res, str) and res.startswith('SKIP:'):
                skip_count.setdefault((i['name'], res[5:]), 0)
                skip_count[(i['name'], res[5:])] += 1
                continue
            if res is None:
                continue
            got.append(dict(base, family=i['family'], input=i['name'], cond=res['cond'] or i['cond'], value=res['value'], n=res['n'], verdict=res['verdict'], detail=res['detail']))
        if not any(g['family'] == 'real' for g in got):
            got.append(dict(base, verdict=NOMEAS, value='-', detail='재려면: ' + need_text(t)))
        rows += got
    for (name, why), c in sorted(skip_count.items()):
        skipped.append({'input': name, 'reason': why, 'count': c})
    return rows, skipped


def summarize(rows):
    def cnt(fam):
        d = {PASS: 0, FAIL: 0, NOMEAS: 0, HUMAN: 0, CONFLICT: 0}
        for r in rows:
            if r['family'] == fam:
                d[r['verdict']] += 1
        return d
    return {'real': cnt('real'), 'model': cnt('model')}


# ---------------------------------------------------------------- 출력
def md_escape(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def render_md(doc, inputs, rows, skipped):
    L = []
    A = L.append
    A('# 목표 판정표')
    A('')
    A('> **%s.** 봇 결과는 안정성·밸런스 참고이며 재미의 증거가 아니다. "모델"은 계산 모델이고 실제 코어의 값이 아니다. 사람 평가 항목은 사용자 플레이 전까지 모두 미평가다.' % HEADER)
    A('')
    A('목표 파일: `%s`(%d개). 판정: 통과 / 미달 / 못 잼 / 미평가. [충돌] 표시는 문서끼리 목표가 달라 후보별로 판정한 항목(충돌 = 후보의 판정이 갈림).' % (doc.get('path_shown', 'tools/dev/targets.json'), len(doc['targets'])))
    A('')
    A('## 입력')
    A('')
    A('| 파일 | 종류 | 조건 | 판 수 |')
    A('|---|---|---|---|')
    for i in inputs:
        A('| %s | %s | %s | %s |' % (md_escape(i['name']), {'rhythm': 'measure_rhythm', 'builds': 'sim_builds', 'loot': 'sim_loot', 'combat': 'measure_combat', 'model': '모델(balance_sim)'}.get(i['kind'], '읽지 못함'), md_escape(i['cond'] or i['error'] or ''), i['runs'] if i['runs'] is not None else '-'))
    A('')
    s = summarize(rows)
    A('## 요약')
    A('')
    A('| 구분 | 통과 | 미달 | 못 잼 | 미평가 | 충돌 |')
    A('|---|---|---|---|---|---|')
    for fam, nm in (('real', '실측(자동 조작 한 판·시뮬레이션)'), ('model', '모델(balance_sim)')):
        d = s[fam]
        A('| %s | %d | %d | %d | %d | %d |' % (nm, d[PASS], d[FAIL], d[NOMEAS], d[HUMAN], d[CONFLICT]))
    A('')
    A('행 수 기준이다(한 지표가 입력 둘에 걸리면 두 행). "못 잼"은 이 입력으로 지표를 잴 수 없거나 표본이 기준 판 수보다 적다는 뜻이다.')
    A('')
    if skipped:
        A('### 건너뛴 입력·행')
        A('')
        for k in skipped:
            A('- %s: %s%s' % (k['input'], k['reason'], (' (%d개 목표)' % k['count']) if k.get('count') else ''))
        A('')

    def table(sel, title):
        A('## ' + title)
        A('')
        cur = None
        for r in sel:
            if r['group'] != cur:
                cur = r['group']
                A('')
                A('### ' + cur)
                A('')
                A('| 지표 | 목표 | 현재 값 | 판 수 | 조건 | 출처 | 판정 |')
                A('|---|---|---|---|---|---|---|')
            det = r['detail']
            val = r['value'] or '-'
            if r['input']:
                val = '%s [%s]' % (val, r['input'])
            if det:
                val += ' — ' + det
            A('| %s | %s | %s | %s | %s | %s | **%s** |' % (md_escape(r['label']), md_escape(r['target']), md_escape(val), r['n'] if r['n'] is not None else '-', md_escape(r['cond'] or ''), md_escape(r['source']), r['verdict']))
        A('')

    real = [r for r in rows if r['family'] == 'real' and r['kind'] == 'auto']
    table(real, '실측(자동)')
    model = [r for r in rows if r['family'] == 'model']
    if model:
        table(model, '모델(balance_sim) — 실측과 섞지 않는다')
    human = [r for r in rows if r['kind'] == 'human']
    A('## 사람 평가(전부 미평가)')
    A('')
    A('| 질문·항목 | 출처 | 판정 | 기록 |')
    A('|---|---|---|---|')
    for r in human:
        A('| %s | %s | **%s** | %s |' % (md_escape(r['label']), md_escape(r['source']), r['verdict'], md_escape(r['detail'])))
    A('')
    return '\n'.join(L) + '\n'


# ---------------------------------------------------------------- 상수 어긋남(--check-constants)
def _num(s):
    s = s.strip()
    return float(s)


def gd_block(text, name, open_ch, close_ch):
    m = re.search(r'const\s+%s\s*(?::=|=)\s*' % re.escape(name), text)
    if not m:
        return None
    i = text.index(open_ch, m.end())
    depth = 0
    for j in range(i, len(text)):
        if text[j] == open_ch:
            depth += 1
        elif text[j] == close_ch:
            depth -= 1
            if depth == 0:
                return text[i:j + 1], text.count('\n', 0, i) + 1
    return None


VAL = r'(\[[^\]]*\]|"[^"]*"|null|-?[\d.]+(?:e[+-]?\d+)?)'


def parse_gd_value(s):
    s = s.strip()
    if s == 'null':
        return None
    if s.startswith('['):
        return [None if x.strip() == 'null' else _num(x) for x in s[1:-1].split(',') if x.strip()]
    if s.startswith('"'):
        return s.strip('"')
    return _num(s)


def gd_dict(text, name):
    b = gd_block(text, name, '{', '}')
    if not b:
        return None, None
    body, line = b
    return {k: parse_gd_value(v) for k, v in re.findall(r'"(\w+)"\s*:\s*' + VAL, body)}, line


def gd_scalar(text, name):
    m = re.search(r'const\s+%s\s*(?::\s*\w+\s*)?:?=\s*(-?[\d.]+)' % re.escape(name), text)
    return (float(m.group(1)), text.count('\n', 0, m.start()) + 1) if m else (None, None)


def gd_beats(text):
    b = gd_block(text, 'BEATS', '[', ']')
    if not b:
        return None, None
    body, line = b
    out = {}
    for ent in re.findall(r'\{[^{}]*\}', body):
        d = {k: parse_gd_value(v) for k, v in re.findall(r'"(\w+)"\s*:\s*' + VAL, ent)}
        if 'name' in d:
            out[d['name']] = d
    return out, line


def py_consts(path, names):
    tree = ast.parse(path.read_text(encoding='utf-8'))
    out = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id in names:
            out[node.targets[0].id] = (ast.literal_eval(node.value), node.lineno)
    return out


def pair(r):
    """목표 range → (하한, 상한). min_excl/max_excl 은 그 값으로 취급하고 표시에 구분."""
    if r is None:
        return (None, None)
    if 'eq' in r:
        return (r['eq'], r['eq'])
    return (r.get('min', r.get('min_excl')), r.get('max', r.get('max_excl')))


def same(a, b):
    if a is None or b is None:
        return a is None and b is None
    return abs(float(a) - float(b)) < 1e-9


def check_constants(targets_doc, root):
    T = {t['key']: t for t in targets_doc['targets']}
    rows = []

    def add(where, line, name, const_val, key, want, note=''):
        t = T.get(key)
        if t is None:
            rows.append({'where': where, 'line': line, 'name': name, 'value': const_val, 'target_key': key, 'target': '(목표 파일에 없음)', 'status': '목표 없음', 'note': note})
            return
        if t.get('conflict'):
            cands = t['conflict']['candidates']
            match = [c['id'] for c in cands if c.get('range') and pair(c['range']) == tuple(const_val if isinstance(const_val, list) else [const_val])]
            if want == 'pair':
                match = [c['id'] for c in cands if c.get('range') and same(pair(c['range'])[0], const_val[0]) and same(pair(c['range'])[1], const_val[1])]
            rows.append({'where': where, 'line': line, 'name': name, 'value': const_val, 'target_key': key,
                         'target': ' | '.join('%s %s' % (c['id'], fmt_range(c.get('range')) if c.get('range') else '범위 없음') for c in cands),
                         'status': ('충돌 항목: 후보 %s 와 일치(다른 후보와는 다름)' % ','.join(match)) if match else '충돌 항목: 어느 후보와도 다름', 'note': note})
            return
        lo, hi = pair(t['range'])
        if want == 'pair':
            zero_low = t.get('unit') in ('승률', '비율') and lo is None and same(const_val[0], 0)   # 승률의 하한 0 은 하한 없음과 같다
            ok = (same(lo, const_val[0]) or zero_low) and same(hi, const_val[1])
        elif want == 'min':
            ok = same(lo, const_val)
        elif want == 'max':
            ok = same(hi, const_val)
        else:
            ok = False
        rows.append({'where': where, 'line': line, 'name': name, 'value': const_val, 'target_key': key,
                     'target': fmt_range(t['range']) if t['range'] else '(범위 없음)', 'status': '일치' if ok else '다름', 'note': note})

    # measure_combat.gd
    p = root / 'chapter1/tests/measure_combat.gd'
    if p.exists():
        txt = p.read_text(encoding='utf-8')
        d, ln = gd_dict(txt, 'TARGETS')
        w = 'chapter1/tests/measure_combat.gd'
        for name, key, want in (('friendly_peak_1s', 'q2.friendly_peak_1s', 'min'), ('primary_hit_share', 'q2.primary_hit_share', 'min'), ('attacks_per_min', 'q2.attacks_per_min', 'min'),
                                ('cap_fraction', 'q2.cap_fraction', 'min'), ('seconds', 'q2.seconds', 'pair'), ('hero_share_pre_evo', 'q2.hero_share_pre', 'min'),
                                ('hero_share_post_evo', 'q2.hero_share_post', 'min'), ('secondary_contribution', 'q2.secondary_contribution', 'pair')):
            if name in d:
                add(w, ln, 'TARGETS.' + name, d[name], key, want)
        th = T['q2.threat']['params']
        for name, pk in (('min_hp_ratio', 'min_hp_ratio_below'), ('burst60', 'burst60_at_least')):
            ok = same(d.get(name), th[pk])
            rows.append({'where': w, 'line': ln, 'name': 'TARGETS.' + name, 'value': d.get(name), 'target_key': 'q2.threat', 'target': fv(th[pk]), 'status': '일치' if ok else '다름', 'note': ''})
        v, l2 = gd_scalar(txt, 'DEFAULT_HEAVY_GAP')
        add(w, l2, 'DEFAULT_HEAVY_GAP', v, 'q2.heavy_gap', 'min')
        v, l2 = gd_scalar(txt, 'COUNTERFACTUAL_GAIN')
        rows.append({'where': w, 'line': l2, 'name': 'COUNTERFACTUAL_GAIN', 'value': v, 'target_key': 'q2.secondary_counterfactual', 'target': '(문서에 수치 없음: "보조를 끈 반사실에서 통과")', 'status': '목표 없음', 'note': '박힌 상수가 판정 기준을 정한다. 문서에 근거가 없다'})
    # sim_loot.gd
    p = root / 'chapter1/tests/sim_loot.gd'
    if p.exists():
        d, ln = gd_dict(p.read_text(encoding='utf-8'), 'TARGETS')
        for name in ('rare', 'jewelry', 'legendary', 'unique'):
            if name in d:
                add('chapter1/tests/sim_loot.gd', ln, 'TARGETS.' + name, d[name], 'q4.' + name, 'pair')
    # sim_progression.gd
    p = root / 'chapter1/tests/sim_progression.gd'
    if p.exists():
        txt = p.read_text(encoding='utf-8')
        w = 'chapter1/tests/sim_progression.gd'
        d, ln = gd_dict(txt, 'TARGET_RUNS_TO_LEVEL')
        for lv in ('6', '12', '20'):
            if lv in d:
                add(w, ln, 'TARGET_RUNS_TO_LEVEL.' + lv, d[lv], 'prog.runs_to_lv' + lv, 'pair')
        b = gd_block(txt, 'TARGET_BRANCH_RUNS', '[', ']')
        if b:
            add(w, b[1], 'TARGET_BRANCH_RUNS', parse_gd_value(b[0]), 'prog.branch_complete', 'pair')
        for name, key, want, val_fn in (('D7_GAP_MAX', 'prog.d7_gap', 'max', None), ('D7_FIELD_PER_MIN', 'prog.d7_field', 'min', None), ('D7_ARC_SECONDARY_FLOOR', 'prog.d7_arc_secondary', 'min', None)):
            v, l2 = gd_scalar(txt, name)
            add(w, l2, name, v, key, want)
        v, l2 = gd_scalar(txt, 'D7_WITCH_SPREAD')
        add(w, l2, 'D7_WITCH_SPREAD', v, 'prog.d7_witch_spread', 'max')
    # balance_sim.py
    p = root / 'tools/dev/balance_sim.py'
    if p.exists():
        c = py_consts(p, {'P7_WIN', 'P4_R'})
        w = 'tools/dev/balance_sim.py'
        if 'P7_WIN' in c:
            val, ln = c['P7_WIN']
            m = {'narrow': 'p7.win.narrow', 'narrow_ring': 'p7.win.narrow_ring', 'random': 'p7.win.random', 'spread': 'p7.win.spread', 'worst': 'p7.win.worst'}
            for pol, key in m.items():
                if pol in val:
                    add(w, ln, 'P7_WIN.' + pol, list(val[pol]), key, 'pair')
            if 'synergy' in val:
                add(w, ln, 'P7_WIN.synergy (synergy:<짝> 길)', list(val['synergy']), 'p7.win.synergy_path', 'pair')
                add(w, ln, 'P7_WIN.synergy (synergy 일반형에도 같은 값 적용)', list(val['synergy']), 'p7.win.synergy', 'pair', '문서의 일반형 기준은 30판 중 28 이상(≈0.933)')
        if 'P4_R' in c:
            val, ln = c['P4_R']
            bm = {'기': 'gi', '승1': 'seung1', '승2': 'seung2', '전A': 'jeon_a', '전B': 'jeon_b'}
            for beat, pols in val.items():
                for pol, rg in pols.items():
                    add(w, ln, 'P4_R.%s.%s' % (beat, pol), list(rg), 'p4.%s.%s' % (bm[beat], pol), 'pair')
    # measure_rhythm.gd
    p = root / 'chapter1/tests/measure_rhythm.gd'
    if p.exists():
        beats, ln = gd_beats(p.read_text(encoding='utf-8'))
        w = 'chapter1/tests/measure_rhythm.gd'
        bm = {'기': 'gi', '승1': 'seung1', '승2': 'seung2', '전A': 'jeon_a', '전B': 'jeon_b', '전C': 'jeon_c'}
        for nm, d in (beats or {}).items():
            bid = bm.get(nm)
            for metric in ('alive_avg', 'alive_max', 'kpm', 'hits_pm', 'dmg30'):
                key = 'a2.%s.%s' % (bid, metric)
                v = d.get(metric)
                if v is None:
                    rows.append({'where': w, 'line': ln, 'name': 'BEATS.%s.%s' % (nm, metric), 'value': None, 'target_key': key,
                                 'target': fmt_range(T[key]['range']) if key in T else '(목표 없음)', 'status': '일치' if key not in T else '다름', 'note': '상수 null = 목표 없음'})
                    continue
                add(w, ln, 'BEATS.%s.%s' % (nm, metric), v, key, 'pair' if isinstance(v, list) else 'max')
    return rows


def render_constants_md(rows):
    L = []
    diff = [r for r in rows if r['status'] != '일치']
    L.append('# 박힌 상수와 목표 파일의 어긋남')
    L.append('')
    L.append('> %s. 이 도구는 상수를 고치지 않는다(상수를 바꾸면 무엇이 통과인지가 바뀐다 — 수치 단계에서 결정 기록과 함께).' % HEADER)
    L.append('')
    L.append('비교 %d건, 일치 %d건, 다른 것·결정이 필요한 것 %d건.' % (len(rows), len(rows) - len(diff), len(diff)))
    L.append('')
    L.append('## 일치하지 않는 것')
    L.append('')
    L.append('| 파일:행 | 상수 | 박힌 값 | 목표 파일 값 | 판정 | 비고 |')
    L.append('|---|---|---|---|---|---|')
    for r in diff:
        L.append('| %s:%s | %s | %s | %s (%s) | %s | %s |' % (r['where'], r['line'], md_escape(r['name']), md_escape(r['value']), md_escape(r['target']), r['target_key'], r['status'], md_escape(r['note'])))
    L.append('')
    L.append('## 일치한 것(개수)')
    L.append('')
    by = {}
    for r in rows:
        if r['status'] == '일치':
            by[r['where']] = by.get(r['where'], 0) + 1
    for k, v in sorted(by.items()):
        L.append('- %s: %d건' % (k, v))
    L.append('')
    return '\n'.join(L) + '\n'


# ---------------------------------------------------------------- CLI
def safe_out(path):
    p = Path(path).resolve()
    if '_local' not in p.parts:
        raise SystemExit('출력은 _local/ 아래에만 쓴다: %s' % path)
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description='목표 판정표(%s)' % HEADER)
    ap.add_argument('inputs', nargs='*', help='측정 JSON(measure_rhythm·sim_builds·measure_combat·balance_sim --out) 또는 LOOT_SIM/COMBAT_MEASURE 줄이 든 텍스트')
    ap.add_argument('--targets', default=str(DEFAULT_TARGETS))
    ap.add_argument('--root', default=str(ROOT), help='상수 검사의 저장소 루트와 playtests 기본 위치')
    ap.add_argument('--playtests', default=None, help='사용자 플레이 기록 폴더(기본: <root>/_local/playtests)')
    ap.add_argument('--check-constants', action='store_true')
    ap.add_argument('--out-md')
    ap.add_argument('--out-json')
    a = ap.parse_args(argv)
    doc = load_targets(a.targets)
    doc['path_shown'] = Path(a.targets).name if Path(a.targets).resolve() == DEFAULT_TARGETS.resolve() else a.targets
    if doc['path_shown'] == 'targets.json':
        doc['path_shown'] = 'tools/dev/targets.json'
    root = Path(a.root)
    outs = []
    if a.check_constants:
        rows = check_constants(doc, root)
        md = render_constants_md(rows)
        outs.append((a.out_md, md))
        if a.out_json:
            safe_out(a.out_json).write_text(json.dumps({'header': HEADER, 'rows': rows}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8', newline='\n')
        if not a.inputs:
            for dest, text in outs:
                if dest:
                    safe_out(dest).write_text(text, encoding='utf-8', newline='\n')
            sys.stdout.reconfigure(encoding='utf-8')
            print(md)
            return 0
    inputs = [load_input(p) for p in a.inputs]
    rec = load_playtests(a.playtests if a.playtests else root / '_local' / 'playtests')
    rows, skipped = run_judge(doc, inputs, rec)
    md = render_md(doc, inputs, rows, skipped)
    if a.out_md:
        safe_out(a.out_md).write_text(md, encoding='utf-8', newline='\n')
    if a.out_json:
        payload = {'header': HEADER, 'summary': summarize(rows),
                   'inputs': [{k: i[k] for k in ('name', 'path', 'kind', 'family', 'cond', 'runs', 'error')} for i in inputs],
                   'skipped': skipped, 'rows': rows}
        safe_out(a.out_json).write_text(json.dumps(payload, ensure_ascii=False, indent=1) + '\n', encoding='utf-8', newline='\n')
    sys.stdout.reconfigure(encoding='utf-8')
    print(md)
    return 0


if __name__ == '__main__':
    sys.exit(main())
