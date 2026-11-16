"""Read-only catalog of the working tree (stdlib only). Never writes, never runs the game.

Everything shown is read from the repository's current files. "Used by the game" is only
what a static scan of res:// references from chapter1/ChapterOne.tscn can see.
"""
import json, re, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRY = 'chapter1/ChapterOne.tscn'
UNIT = 256  # chapter1/core/combat_core.gd: const UNIT := 256 (raw life/damage per displayed point)
TICKS = 60

CATEGORIES = [
    ('run', '한 판의 기술과 은총'), ('perm', '영구 성장'), ('combat', '전투 수치'), ('gear', '장비'),
    ('world', '구역과 의식'), ('characters', '주인공 원화'), ('models', '3D 모델'),
    ('images', '그림·아이콘'), ('sounds', '소리'), ('code', '코드 구성'),
    ('agents', '에이전트'), ('docs', '문서'), ('quality', '품질 목표'),
]
USAGE_LABELS = {
    'direct': '코드가 파일을 직접 가리킴',
    'composed': '코드가 폴더와 이름을 조합해 읽음',
    'folder': '읽는 폴더 안에 있으나 이름 확인 못 함',
    'none': '실행 경로에서 참조를 찾지 못함',
}


# ------------------------------------------------------------------ file helpers
def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def read_json(rel):
    return json.loads(read(rel))


def line_of(text, needle):
    i = text.find(needle)
    return text.count('\n', 0, i) + 1 if i >= 0 else None


# ------------------------------------------------------------------ GDScript literal parser (no eval)
def gd_const(text, name):
    """Parse `const NAME := <literal>` (arrays, dicts, strings, numbers, Vector2). Raises ValueError."""
    m = re.search(r'^const\s+' + re.escape(name) + r'\s*(?::=|=|:\s*\w+\s*=)\s*', text, re.M)
    if not m:
        raise ValueError('Missing constant ' + name)
    p = _Lit(text, m.end())
    value = p.value()
    return value


class _Lit:
    def __init__(self, s, i):
        self.s, self.i = s, i

    def ws(self):
        s = self.s
        while self.i < len(s) and (s[self.i] in ' \t\r\n' or s[self.i] == '#'):
            if s[self.i] == '#':
                while self.i < len(s) and s[self.i] != '\n':
                    self.i += 1
            else:
                self.i += 1

    def value(self):
        self.ws()
        s, c = self.s, self.s[self.i]
        if c == '[':
            self.i += 1
            out = []
            while True:
                self.ws()
                if s[self.i] == ']':
                    self.i += 1
                    return out
                out.append(self.value())
                self.ws()
                if s[self.i] == ',':
                    self.i += 1
        if c == '{':
            self.i += 1
            out = {}
            while True:
                self.ws()
                if s[self.i] == '}':
                    self.i += 1
                    return out
                k = self.value()
                self.ws()
                if s[self.i] != ':':
                    raise ValueError('Bad dictionary literal')
                self.i += 1
                out[k] = self.value()
                self.ws()
                if s[self.i] == ',':
                    self.i += 1
        if c == '"':
            m = re.compile(r'"((?:[^"\\]|\\.)*)"').match(s, self.i)
            if not m:
                raise ValueError('Bad string literal')
            self.i = m.end()
            return m.group(1)
        m = re.compile(r'-?\d+(?:\.\d+)?').match(s, self.i)
        if m:
            self.i = m.end()
            return float(m.group()) if '.' in m.group() else int(m.group())
        m = re.compile(r'Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)').match(s, self.i)
        if m:
            self.i = m.end()
            return {'x': float(m.group(1)), 'y': float(m.group(2))}
        for word, val in (('true', True), ('false', False), ('null', None)):
            if s.startswith(word, self.i):
                self.i += len(word)
                return val
        raise ValueError('Unsupported literal at: ' + s[self.i:self.i + 20])


# ------------------------------------------------------------------ number formatting
def hundredths(v):
    # port of chapter1/core/skill_tree.gd _hundredths
    sign = '-' if v < 0 else ''
    v = abs(int(v))
    whole, frac = v // 100, v % 100
    if frac == 0:
        return sign + str(whole)
    if frac % 10 == 0:
        return '%s%d.%d' % (sign, whole, frac // 10)
    return '%s%d.%02d' % (sign, whole, frac)


def num(v):
    if isinstance(v, float) and v == int(v):
        v = int(v)
    return str(v)


def describe_block(block):
    """Port of chapter1/core/skill_tree.gd describe_block (same wording and order)."""
    lines = []
    skill = block.get('skill', {})
    add = skill.get('add', {})
    if add.get('pierce', 0):
        lines.append('관통 +%d' % add['pierce'])
    if add.get('projectiles', 0):
        lines.append('창 +%d발' % add['projectiles'])
    if add.get('shatter_count', 0):
        lines.append('파편 +%d' % add['shatter_count'])
    if add.get('slow_bps', 0):
        lines.append('감속 +%s%%p' % hundredths(add['slow_bps']))
    if add.get('radius_cm', 0):
        lines.append('반경 +%s m' % hundredths(add['radius_cm']))
    mul = skill.get('mul_bps', {})
    if 'damage_raw' in mul and mul['damage_raw'] != 10000:
        lines.append('피해 +%s%%' % hundredths(mul['damage_raw'] - 10000))
    if 'cooldown_bps' in skill and skill['cooldown_bps'] != 10000:
        lines.append('시전 간격 −%s%%' % hundredths(10000 - skill['cooldown_bps']))
    if 'freeze_stacks' in skill.get('at_most', {}):
        lines.append('%d번 맞으면 빙결' % skill['at_most']['freeze_stacks'])
    if 'shatter_count' in skill.get('at_least', {}):
        lines.append('파쇄 파편 최소 %d' % skill['at_least']['shatter_count'])
    hero = block.get('hero', {})
    if hero.get('max_hp', 0):
        lines.append('최대 생명 +%d' % hero['max_hp'])
    if hero.get('damage_reduction_bps', 0):
        lines.append('받는 피해 −%s%%' % hundredths(hero['damage_reduction_bps']))
    if hero.get('potion_start', 0):
        lines.append('시작 회복약 +%d' % hero['potion_start'])
    rules = block.get('rules', {})
    if rules.get('elite_damage_bps', 0):
        lines.append('수호자·우두머리 피해 +%s%%' % hundredths(rules['elite_damage_bps']))
    if rules.get('shatter_radius_cm', 0):
        lines.append('파쇄 반경 +%s m' % hundredths(rules['shatter_radius_cm']))
    if 'frost_field' in rules:
        f = rules['frost_field']
        lines.append('서리 지대: 반경 %s m · %s초 · 감속 %s%%' % (
            hundredths(f['radius_cm']), hundredths(f['duration_ticks'] * 100 // 60), hundredths(f['slow_bps'])))
    fa = rules.get('frost_field_add', {})
    if fa.get('radius_cm', 0):
        lines.append('지대 반경 +%s m' % hundredths(fa['radius_cm']))
    if fa.get('max_fields', 0):
        lines.append('지대 동시 +%d개' % fa['max_fields'])
    if fa.get('pulse_damage_bps', 0):
        lines.append('지대 피해: 창 피해의 %s%%' % hundredths(fa['pulse_damage_bps']))
    if fa.get('slow_bps_at_least', 0):
        lines.append('지대 감속 %s%%' % hundredths(fa['slow_bps_at_least']))
    if rules.get('grace_rerolls', 0):
        lines.append('은총 다시 빌기 %d회' % rules['grace_rerolls'])
    if 'start_rank' in rules:
        lines.append('서리창 랭크 %d으로 시작' % rules['start_rank'])
    if rules.get('evolve_without_passive', False):
        lines.append('결정 은총 없이 진화')
    return lines


STAT_LABELS = {
    'damage_bps': '피해', 'cooldown_bps': '시전 간격 단축', 'max_hp_raw': '최대 생명',
    'damage_reduction_bps': '받는 피해 감소', 'pickup_radius_cm': '줍기 반경', 'projectiles': '발사체',
    'pierce': '관통', 'chain_targets': '연쇄', 'shatter_count': '파쇄 파편', 'radius_cm': '범위',
    'slow_bps': '감속', 'fire_damage_bps': '불꽃 피해', 'fire_burst': '화염 처치 폭발',
    'frost_threshold': '빙결 문턱 감소', 'arc_branches': '번개 분기', 'arc_damage_bps': '번개 피해',
    'move_speed_bps': '이동 속도', 'dash_cooldown_bps': '돌진 재사용 단축', 'soul_gain_bps': '영혼 획득',
}


def stat_text(stat, v):
    label = STAT_LABELS.get(stat, stat)
    sign = '+' if v > 0 else ''
    if stat.endswith('_bps'):
        return '%s %s%s%%' % (label, sign, hundredths(v))
    if stat.endswith('_cm'):
        return '%s %s%s m' % (label, sign, hundredths(v))
    if stat == 'max_hp_raw':
        return '%s %s%s' % (label, sign, num(round(v / UNIT, 2)))
    return '%s %s%s' % (label, sign, v)


def stats_text(stats):
    return ' · '.join(stat_text(k, v) for k, v in stats.items())


def pct_bps(v):
    return hundredths(v) + '%'


# ------------------------------------------------------------------ entity builders
class Catalog:
    def __init__(self):
        self.entities, self.warnings, self.ids = [], [], set()
        self.allowed = set()

    def add(self, id_, category, type_, name, summary='', sections=None, source=None, previews=None,
            usage=None, usage_notes=None, links=None):
        if id_ in self.ids:
            n = 2
            while '%s#%d' % (id_, n) in self.ids:
                n += 1
            id_ = '%s#%d' % (id_, n)
        self.ids.add(id_)
        row = {'id': id_, 'category': category, 'type': type_, 'name': name, 'summary': summary,
               'sections': sections or [], 'source': source, 'previews': previews or [],
               'links': links or []}
        if usage:
            row['usage'] = usage
            row['usage_notes'] = usage_notes or []
        for p in ([source['path']] if source else []) + [x['path'] for x in row['previews']] + [x['path'] for x in row['links']]:
            self.allowed.add(p)
        self.entities.append(row)
        return row


def pairs(title, rows):
    return {'title': title, 'kind': 'pairs', 'rows': [[str(a), str(b)] for a, b in rows]}


def table(title, columns, rows):
    return {'title': title, 'kind': 'table', 'columns': [str(c) for c in columns],
            'rows': [[str(c) for c in r] for r in rows]}


def lines(title, items):
    return {'title': title, 'kind': 'lines', 'items': [str(i) for i in items]}


def src(path, text=None, needle=None):
    s = {'path': path}
    if text is not None and needle:
        n = line_of(text, needle)
        if n:
            s['line'] = n
    return s


# ------------------------------------------------------------------ run growth
GROWTH_ROWS = [
    ('damage_raw', '피해', lambda v: num(round(v / UNIT, 2))),
    ('cooldown_ticks', '시전 간격(초)', lambda v: num(round(v / TICKS, 2))),
    ('projectiles', '발사체', str), ('chain_targets', '연쇄 대상', str), ('branches', '분기', str),
    ('pierce', '관통', str), ('radius_cm', '반경(m)', lambda v: num(v / 100)),
    ('slow_bps', '감속(%)', lambda v: hundredths(v)), ('freeze_stacks', '빙결까지 맞는 횟수', str),
    ('shatter_count', '파쇄 파편', str), ('death_burst', '처치 폭발', str),
    ('proc_depth', '연쇄 발동 단계', str), ('hit_budget', '한 번에 맞힐 수 있는 수', str),
]


def growth_entities(c):
    p37, p36 = 'chapter1/data/growth_quality37.json', 'chapter1/data/growth_quality36.json'
    g = read_json(p37)
    g36 = read_json(p36)
    t37 = read(p37)
    refs = {}
    for path in (ROOT / 'chapter1').rglob('*.gd'):
        txt = path.read_text(encoding='utf-8', errors='replace')
        for ver in ('growth_quality36', 'growth_quality37'):
            if ver + '.json' in txt:
                refs.setdefault(ver, []).append(path.relative_to(ROOT).as_posix())
    passives = {x['id']: x for x in g['passives']}
    for s in g['skills']:
        cols = ['단계'] + ['랭크 %d' % (i + 1) for i in range(len(s['ranks']))] + ['진화: ' + s['evolution_name']]
        stages = s['ranks'] + [s['evolution']]
        rows = []
        for key, label, fmt in GROWTH_ROWS:
            vals = [st.get(key, 0) for st in stages]
            if key in ('damage_raw', 'cooldown_ticks') or any(vals):
                rows.append([label] + [fmt(v) for v in vals])
        pas = passives.get(s['passive_id'], {})
        c.add('run:skill:' + s['id'], 'run', '기술', s['name'],
              '랭크 %d단계 + 진화(%s). 짝이 되는 패시브: %s' % (len(s['ranks']), s['evolution_name'], pas.get('name', '?')),
              [table('랭크별 효과(수치는 데이터 기준)', cols, [[r[0]] + r[1:] for r in rows]),
               pairs('기본 정보', [('식별자', s['id']), ('뽑힐 가중치', s['weight']), ('진화 이름', s['evolution_name']),
                                  ('짝 패시브', '%s (%s)' % (pas.get('name', '?'), s['passive_id']))])],
              src(p37, t37, '"%s"' % s['id']))
    for pas in g['passives']:
        owner = next((s for s in g['skills'] if s['passive_id'] == pas['id']), None)
        c.add('run:passive:' + pas['id'], 'run', '패시브(은총)', pas['name'],
              '짝 기술: %s' % (owner['name'] if owner else '없음'),
              [pairs('정보', [('식별자', pas['id']), ('뽑힐 가중치', pas['weight']),
                              ('짝 기술', owner['name'] if owner else '없음')]),
               lines('참고', ['이 데이터 파일에는 패시브의 효과 문장이 없습니다. 효과는 코드(run_growth_quality37.gd)에서 처리됩니다.'])],
              src(p37, t37, '"%s"' % pas['id']))
    xp = g['xp_thresholds']
    c.add('run:xp', 'run', '규칙', '한 판의 레벨 곡선(은총 데이터)',
          '레벨 %d까지, 동시에 기술 %d개 · 패시브 %d개' % (len(xp), g['max_active_skills'], g['max_passives']),
          [table('레벨별 필요 경험치', ['레벨', '누적 경험치', '직전 대비'],
                 [[i + 1, v, v - (xp[i - 1] if i else 0)] for i, v in enumerate(xp)]),
           pairs('한도', [('동시에 가질 기술', g['max_active_skills']), ('동시에 가질 패시브', g['max_passives'])]),
           lines('참고', ['전투 수치 파일(combat_tuning.json)에도 한 판의 경험치 곡선이 있습니다. 그쪽은 「전투 수치」에서 보세요. 어느 쪽이 실제 레벨업에 쓰이는지는 코드에서 확인해야 합니다.'])],
          src(p37, t37, '"xp_thresholds"'))
    diffs = []

    def walk(a, b, path=''):
        if type(a) != type(b):
            diffs.append((path, a, b))
        elif isinstance(a, dict):
            for k in sorted(set(a) | set(b)):
                walk(a.get(k), b.get(k), path + '/' + str(k))
        elif isinstance(a, list):
            if len(a) != len(b):
                diffs.append((path + ' (길이)', len(a), len(b)))
            else:
                for i, (x, y) in enumerate(zip(a, b)):
                    walk(x, y, '%s/%d' % (path, i))
        elif a != b:
            diffs.append((path, a, b))
    walk(g36, g)
    who = lambda k: ', '.join(refs.get(k, [])) or '읽는 파일을 찾지 못함'
    c.add('run:versions', 'run', '데이터 버전', '은총 데이터 36판과 37판의 차이',
          '다른 곳 %d개. 36판을 읽는 곳: %s' % (len(diffs), who('growth_quality36')),
          [table('다른 항목(36판 → 37판)', ['위치', '36판', '37판'], [[a, b, d] for a, b, d in diffs[:40]]),
           pairs('읽는 코드', [('36판', who('growth_quality36')), ('37판', who('growth_quality37'))])],
          src(p37))


# ------------------------------------------------------------------ permanent growth
def perm_entities(c):
    pp, tp = 'chapter1/data/character_progression.json', 'chapter1/data/skill_trees.json'
    prog, trees = read_json(pp), read_json(tp)
    tprog, ttrees = read(pp), read(tp)
    xp = prog['xp_thresholds']
    c.add('perm:levels', 'perm', '규칙', '레벨 곡선과 포인트',
          '레벨 %d까지, 레벨당 포인트 %d' % (prog['level_cap'], prog['points_per_level']),
          [table('레벨별 필요 경험치', ['레벨', '누적 경험치', '직전 대비'],
                 [[i + 1, v, v - (xp[i - 1] if i else 0)] for i, v in enumerate(xp)]),
           pairs('규칙', [('레벨 상한', prog['level_cap']), ('레벨당 포인트', prog['points_per_level']),
                         ('밸런스 상태', prog.get('balance_status', '')),
                         ('다시 찍기 비용(정수당)', prog['respec']['essence_per_point'])])],
          src(pp, tprog, '"xp_thresholds"'))
    s = prog['sources']
    c.add('perm:sources', 'perm', '규칙', '경험치를 얻는 곳',
          '봉인 %s · 수호자 %s · 우두머리 %s · 승리 %s' % ('/'.join(map(str, s['seal_xp'])), '/'.join(map(str, s['champion_xp'])), s['boss_xp'], s['victory_xp']),
          [pairs('원천별 경험치', [('구역 봉인(1·2·3구역)', ' / '.join(map(str, s['seal_xp']))),
                                  ('수호자(1·2번째)', ' / '.join(map(str, s['champion_xp']))),
                                  ('우두머리', s['boss_xp']), ('판 승리', s['victory_xp'])]),
           pairs('첫 처치 보상 포인트', list(prog['first_rewards'].items())),
           pairs('옛 저장 이전', [('한 판 완료당 경험치', prog['migration']['xp_per_completed_run']),
                                 ('최대 반영 판 수', prog['migration']['max_runs'])])],
          src(pp, tprog, '"sources"'))
    chars = prog['characters']
    c.add('perm:characters', 'perm', '규칙', '마녀별 대표 기술과 성장 나무',
          '%d명 중 성장 나무가 있는 마녀 %d명' % (len(chars), sum(1 for x in chars if x['tree_id'])),
          [table('마녀', ['식별자', '대표 기술', '성장 나무'],
                 [[x['id'], x['signature_skill_id'], x['tree_id'] or '아직 없음'] for x in chars])],
          src(pp, tprog, '"characters"'))
    for tree in trees['trees']:
        nodes = {n['id']: n for n in tree['nodes']}
        branches = {b['id']: b['name'] for b in tree['branches']}
        tiers = tree['tiers']
        c.add('perm:tree:' + tree['tree_id'], 'perm', '성장 나무', '성장 나무 ' + tree['tree_id'],
              '마녀 %s · 갈래 %d · 단 %d · 노드 %d' % (tree['character_id'], len(branches), len(tiers), len(nodes)),
              [table('단(잠금 레벨)', ['단', '이름', '필요 레벨'], [[i + 1, t['name'], t['level']] for i, t in enumerate(tiers)]),
               table('갈래', ['식별자', '이름', '색'], [[b['id'], b['name'], b['color']] for b in tree['branches']]),
               table('노드 목록', ['단', '갈래', '이름', '최대 랭크', '선행'],
                     [[n['tier'], branches.get(n['branch'], n['branch']), n['name'], n['max_rank'],
                       ', '.join('%s %d' % (nodes[k]['name'] if k in nodes else k, v) for k, v in n['requires'].items()) or '없음']
                      for n in tree['nodes']]),
               pairs('기타', [('버전', tree['revision']), ('밸런스 상태', tree.get('balance_status', '')),
                             ('시너지 수', len(tree.get('synergies', [])))])],
              src(tp, ttrees, '"%s"' % tree['tree_id']))
        for n in tree['nodes']:
            req = ', '.join('%s %d랭크' % (nodes[k]['name'] if k in nodes else k, v) for k, v in n['requires'].items()) or '없음'
            level = tiers[n['tier'] - 1]['level'] if 1 <= n['tier'] <= len(tiers) else '?'
            rank_rows = [[i + 1, ' / '.join(describe_block(b)) or '(표시할 효과 없음)'] for i, b in enumerate(n['ranks'])]
            c.add('perm:node:' + n['id'], 'perm', '성장 노드', n['name'],
                  '%s · %d단(레벨 %s) · 최대 %d랭크' % (branches.get(n['branch'], n['branch']), n['tier'], level, n['max_rank']),
                  [table('랭크별 효과(게임 표기와 같은 문구)', ['랭크', '효과'], rank_rows),
                   pairs('조건', [('선행 노드', req), ('먼저 써야 하는 포인트', n['min_spent']),
                                 ('새 규칙', n['new_rule'] or '없음'), ('나무', tree['tree_id'])]),
                   lines('설명 문구', [n['lore']])],
                  src(tp, ttrees, '"%s"' % n['id']))


# ------------------------------------------------------------------ combat tuning
def combat_entities(c):
    p = 'chapter1/data/combat_tuning.json'
    t = read_json(p)
    text = read(p)
    S = lambda needle: src(p, text, needle)
    names = {'walker': '보행형 적', 'ranged': '원거리 적', 'charger': '돌진형 적'}
    for kind, d in t['enemies'].items():
        n = len(d['hp'])
        rows = [['구역 %d' % (i + 1), d['hp'][i], d['damage'][i], d['speed'][i]] for i in range(n)]
        extra = [(k, v) for k, v in d.items() if k not in ('hp', 'damage', 'speed')]
        secs = [table('구역별 수치', ['구역', '체력', '피해', '속도'], rows)]
        if extra:
            secs.append(pairs('추가 값', extra))
        secs.append(pairs('시간이 지나며 체력 증가', [('%d초부터 초당' % t['hp_time_from_s'], hundredths(t['hp_time_bps_per_s']) + '%')]))
        c.add('combat:enemy:' + kind, 'combat', '적', names.get(kind, kind), '체력 %s → %s(구역 1→%d)' % (d['hp'][0], d['hp'][-1], n), secs, S('"%s"' % kind + ':'))
    cn = ['구역 1 수호자', '구역 2 수호자', '구역 3 우두머리']
    for i, ch in enumerate(t['champions']):
        c.add('combat:champion:%d' % i, 'combat', '수호자·우두머리', cn[i] if i < 3 else '수호자 %d' % (i + 1),
              '체력 %s · 피해 %s · 경험치 %s' % (ch['hp'], ch['damage'], ch['xp']),
              [pairs('수치', [('체력', ch['hp']), ('피해', ch['damage']), ('공격 준비(틱)', ch['windup']), ('공격 후 쉬는 시간(틱)', ch['recover']), ('경험치', ch['xp'])]),
               lines('참고', ['틱은 1/60초입니다. 데이터 순서가 구역 순서이고, 마지막이 우두머리라는 이름 붙이기는 첫 처치 보상 표기(champion:0, champion:1, boss)를 따른 해석입니다.'])],
              S('"champions"'))
    sp = t['spawn']
    c.add('combat:spawn', 'combat', '생성', '적 생성 구성',
          '동시 최대 %d마리' % t['alive_cap'],
          [pairs('공통', [('동시에 살아있는 적 상한', t['alive_cap']), ('아군 투사체 상한', t['friendly_projectile_cap']),
                         ('생성 거리(m)', '%s ~ %s' % (sp['ring_min_m'], sp['ring_max_m']))]),
           table('초반(시작 후)', ['몇 초까지', '한 번에'], [[o['until_s'], o['amount']] for o in sp['opening']]),
           table('구역별', ['구역', '한 번에', '간격(틱)'], [[i + 1, z['amount'], z['interval_ticks']] for i, z in enumerate(sp['zones'])]),
           pairs('우두머리 전투 중', [('한 번에', sp['boss_phase']['amount']), ('간격(틱)', sp['boss_phase']['interval_ticks'])]),
           pairs('종류 섞기', list(sp['mix'].items()))], S('"spawn"'))
    c.add('combat:seal_kills', 'combat', '규칙', '구역 봉인 해제 처치 수',
          ' / '.join(map(str, t['seal_kills'])), [table('구역별', ['구역', '처치 수'], [[i + 1, v] for i, v in enumerate(t['seal_kills'])])], S('"seal_kills"'))
    pot = t['potion']
    c.add('combat:potion', 'combat', '규칙', '회복 물약',
          '시작 %d개 · 최대 %d개 · 회복 %s%%' % (pot['start'], pot['carry_max'], hundredths(pot['heal_bps'])),
          [pairs('수치', [('시작 개수', pot['start']), ('최대 소지', pot['carry_max']), ('회복량(최대 생명 대비)', hundredths(pot['heal_bps']) + '%'),
                         ('재사용 대기(틱)', pot['cooldown_ticks']), ('떨어질 확률', '1/%d' % pot['drop_one_in']), ('봉인 해제 시 드랍', pot['seal_drops'])])], S('"potion"'))
    xp = t['xp_thresholds']
    c.add('combat:xp', 'combat', '규칙', '한 판의 경험치 임계(전투 수치 파일)', '레벨 %d까지, 마지막 %d' % (len(xp), xp[-1]),
          [table('레벨별', ['레벨', '누적 경험치'], [[i + 1, v] for i, v in enumerate(xp)]),
           pairs('규칙', [('우두머리 등장 시 최종 레벨', '예' if t.get('final_level_on_boss_spawn') else '아니오')])], S('"xp_thresholds"'))
    sk = {'chapter1.skill.ember': '잿불탄', 'chapter1.skill.frost': '서리창', 'chapter1.skill.arc': '번개'}
    for sid, stages in t['primary_bonus'].items():
        rows = []
        for stage, b in stages.items():
            eff = []
            for k, v in b.get('add', {}).items():
                eff.append('%s %+d' % (k, v))
            if 'mul_bps' in b:
                eff += ['피해 ×%s%%' % hundredths(v) for v in b['mul_bps'].values()]
            if 'cooldown_bps' in b:
                eff.append('시전 간격 ×%s%%' % hundredths(b['cooldown_bps']))
            rows.append(['진화' if stage == 'evo' else '랭크 ' + stage[1:], ' · '.join(eff)])
        c.add('combat:primary:' + sid, 'combat', '주력 보정', '주력 보정 · ' + sk.get(sid, sid),
              '주력으로 고른 기술에 단계별로 얹는 보정', [table('단계별 보정', ['단계', '내용'], rows),
                                                     lines('참고', ['항목 이름(projectiles, hit_budget 등)은 데이터 원문 그대로입니다.'])], S('"%s"' % sid))
    ch = t['children']
    c.add('combat:children', 'combat', '규칙', '진화 파생 투사체', '진화한 기술만 파생을 냅니다',
          [table('기술별', ['기술', '개수', '수명(틱)', '속도', '시전당 최대'], [[sk.get(k, k), v['count'], v['life_ticks'], v['speed'], v['per_cast']] for k, v in ch.items()])], S('"children"'))
    m, h, sec = t['marks'], t['heavy_hit'], t['secondary']
    c.add('combat:marks', 'combat', '규칙', '표식', '표식 %s%% · %d틱' % (hundredths(m['mark_bps']), m['mark_ticks']),
          [pairs('수치', [('추가 피해', hundredths(m['mark_bps']) + '%'), ('유지(틱)', m['mark_ticks'])])], S('"marks"'))
    c.add('combat:heavy', 'combat', '규칙', '큰 한 방 규칙', '최대 생명의 %s%% 이상 피해가 큰 한 방' % hundredths(h['heavy_bps']),
          [pairs('수치', [('큰 한 방 기준(최대 생명 대비)', hundredths(h['heavy_bps']) + '%'), ('큰 한 방 사이 최소 간격(틱)', h['gap_ticks']),
                         ('무적 시간(틱)', h['iframe_ticks']), ('간격 안에 또 맞을 때 비율', hundredths(h['graze_bps']) + '%'), ('수호 공격 간격(틱)', h['ward_gap_ticks'])])], S('"heavy_hit"'))
    c.add('combat:secondary', 'combat', '규칙', '보조 기술 보정', '보조 기술의 위력 비율과 한도',
          [pairs('수치', [('피해', hundredths(sec['damage_bps']) + '%'), ('명중 한도', hundredths(sec['hit_budget_bps']) + '%'),
                         ('시전 간격', hundredths(sec['cooldown_bps']) + '%'), ('연쇄 최대', sec['max_chain_targets']), ('분기 최대', sec['max_branches'])])], S('"secondary"'))
    c.add('combat:misc', 'combat', '규칙', '그 밖의 전투 값', '수호 공격·구슬·주인공 탄',
          [pairs('값', [('우두머리 방어 공격 피해', t['boss_ward']['damage']), ('경험 구슬 넘칠 때', t['orbs']['overflow']),
                       ('봉인 해제 시 구슬 빨아들임', '예' if t['orbs']['vacuum_on_seal'] else '아니오'),
                       ('주인공 탄 퍼짐(밀리라디안)', t['hero_shot']['spread_mrad']), ('번개 줄기 표시(틱)', t['presentation']['arc_stripe_ticks']),
                       ('밸런스 출처', t['provenance'])])], S('"boss_ward"'))


# ------------------------------------------------------------------ gear
QUALITY_NAMES = {'common': '일반', 'magic': '마법', 'rare': '희귀', 'legendary': '전설', 'unique': '고유'}
CLASS_NAMES = {'normal': '일반 적', 'elite': '정예', 'carrier': '운반자', 'champion': '수호자', 'boss': '우두머리', 'boss_first_kill': '우두머리 첫 처치'}


def gear_entities(c):
    p = 'chapter1/data/loot.json'
    L = read_json(p)
    text = read(p)
    S = lambda needle: src(p, text, needle)
    sn = dict(L['slot_names'], ring2='반지 2')
    c.add('gear:slots', 'gear', '규칙', '착용 칸과 등급', '착용 %d칸 · 등급 %d단계' % (len(L['equip_slots']), len(L['qualities'])),
          [table('착용 칸', ['식별자', '이름'], [[s, sn.get(s, s)] for s in L['equip_slots']]),
           table('등급(낮음 → 높음)', ['식별자', '이름'], [[q, QUALITY_NAMES.get(q, q)] for q in L['qualities']]),
           pairs('기타', [('최대 장비 레벨', L['max_item_level']), ('목걸이·반지 칸', ', '.join(sn.get(s, s) for s in L['jewelry_slots']))]),
           table('칸별 드랍 가중치', ['칸', '가중치'], [[sn.get(k, k), v] for k, v in L['slot_weights'].items()])], S('"equip_slots"'))
    c.add('gear:limits', 'gear', '규칙', '능력치 합계 한도', '장비로 올릴 수 있는 한계',
          [table('한도', ['능력치', '최소', '최대'], [[STAT_LABELS.get(k, k), v[0], v[1]] for k, v in L['limits'].items()])], S('"limits"'))
    for b in L['bases']:
        c.add('gear:base:' + b['id'], 'gear', '기본 장비', b['name'], '%s · 레벨 %d · %s' % (sn.get(b['slot'], b['slot']), b['level'], stats_text(b['stats'])),
              [pairs('정보', [('칸', sn.get(b['slot'], b['slot'])), ('나오는 레벨', b['level']), ('기본 능력', stats_text(b['stats']))])], S('"%s"' % b['id']))
    for a in L['affixes']:
        c.add('gear:affix:' + a['id'], 'gear', '접사', a['name'], '%s · %s %s~%s' % ('앞 접사' if a['kind'] == 'prefix' else '뒤 접사', STAT_LABELS.get(a['stat'], a['stat']), a['low'], a['high']),
              [pairs('정보', [('종류', '앞 접사' if a['kind'] == 'prefix' else '뒤 접사'), ('묶음', a['group']), ('능력', STAT_LABELS.get(a['stat'], a['stat'])),
                             ('범위(원값)', '%s ~ %s' % (a['low'], a['high'])), ('나오는 레벨', '%d ~ %d' % (a['level'], a['max_level'])),
                             ('붙는 칸', ', '.join(sn.get(s, s) for s in a['slots'])), ('가중치', a['weight'])])], S('"%s"' % a['id']))
    for l in L['legendaries']:
        c.add('gear:legendary:' + l['id'], 'gear', '전설 효과', l['name'], l['description'],
              [pairs('정보', [('붙는 칸', ', '.join(sn.get(s, s) for s in l['slots'])), ('나오는 레벨', l['level']), ('능력', stats_text(l['stats']))])], S('"%s"' % l['id']))
    for u in L['uniques']:
        c.add('gear:unique:' + u['id'], 'gear', '고유 장비', u['name'], u['description'],
              [pairs('정보', [('칸', sn.get(u['slot'], u['slot'])), ('나오는 레벨', u['level']), ('연결 기술', u['element']), ('능력', stats_text(u['stats']))])], S('"%s"' % u['id']))
    c.add('gear:names', 'gear', '규칙', '희귀 장비 이름 재료', '앞말 × 뒷말 조합',
          [lines('앞말', L['rare_names']['first']), lines('뒷말', L['rare_names']['second'])], S('"rare_names"'))
    for k, tc in L['treasure_classes'].items():
        q = tc['quality']
        total = sum(q.values()) or 1
        c.add('gear:treasure:' + k, 'gear', '보물 등급표', '보물 등급표 · ' + CLASS_NAMES.get(k, k),
              '한 번에 %d회 굴림 · 레벨 +%d' % (tc['picks'], tc['level_bonus']),
              [pairs('규칙', [('굴림 횟수', tc['picks']), ('안 떨어질 비중', tc['no_drop']), ('떨어질 비중', tc['drop']), ('아이템 레벨 가산', tc['level_bonus']),
                             ('확정', ', '.join(QUALITY_NAMES.get(x, x) for x in tc.get('guaranteed', [])) or '없음')]),
               table('등급 비중', ['등급', '비중(합 %d)' % total], [[QUALITY_NAMES.get(a, a), b] for a, b in q.items()])], S('"%s"' % k + ': {"picks"'))


# ------------------------------------------------------------------ zones and rituals
def world_entities(c, warnings):
    p = 'chapter1/core/chapter_core.gd'
    text = read(p)
    try:
        zones, zn, rituals = gd_const(text, 'ZONES'), gd_const(text, 'ZONE_NAMES'), gd_const(text, 'RITUALS')
    except ValueError as e:
        warnings.append('구역·의식을 읽지 못했습니다: %s (%s)' % (e, p))
        return
    t = read_json('chapter1/data/combat_tuning.json')
    for i, z in enumerate(zones):
        name = zn[i] if i < len(zn) else '구역 %d' % (i + 1)
        rows = [('위치', '(%s, %s)' % (num(z['x']), num(z['y']))), ('봉인 해제 처치 수', t['seal_kills'][i] if i < len(t['seal_kills']) else '?')]
        zs = t['spawn']['zones']
        if i < len(zs):
            rows.append(('적 생성', '%d마리씩, %d틱마다' % (zs[i]['amount'], zs[i]['interval_ticks'])))
        for kind, d in t['enemies'].items():
            if i < len(d['hp']):
                rows.append((kind, '체력 %s · 피해 %s · 속도 %s' % (d['hp'][i], d['damage'][i], d['speed'][i])))
        ch = t['champions'][i] if i < len(t['champions']) else None
        if ch:
            rows.append(('수호자/우두머리', '체력 %s · 피해 %s' % (ch['hp'], ch['damage'])))
        rl = [r['name'] for r in rituals if r.get('zone') == i]
        rows.append(('의식', ', '.join(rl) or '없음'))
        c.add('world:zone:%d' % i, 'world', '구역', '구역 %d · %s' % (i + 1, name), '봉인 해제 처치 %s' % (rows[1][1]), [pairs('구역 정보', rows)], src(p, text, 'const ZONES'))
    kinds = {'hold': '일정 시간 지키기', 'kill': '대상 처치'}
    for r in rituals:
        zi = r.get('zone', 0)
        c.add('world:ritual:' + r['id'], 'world', '의식', r['name'],
              '구역 %d · %s' % (zi + 1, kinds.get(r.get('kind'), r.get('kind'))),
              [pairs('정보', [('식별자', r['id']), ('구역', '%d · %s' % (zi + 1, zn[zi] if zi < len(zn) else '')), ('방식', kinds.get(r.get('kind'), r.get('kind'))),
                             ('위치', '(%s, %s)' % (num(r['position']['x']), num(r['position']['y'])))])], src(p, text, '"%s"' % r['id']))


# ------------------------------------------------------------------ reference scan
RES = re.compile(r'res://[^"\'\s)\]]+')
LIT = re.compile(r'"([^"\\\n]*)"')
SCAN_EXT = {'.gd', '.tscn', '.gdshader', '.tres', '.json'}


def scan_references():
    """Follow res:// strings from the entry. Returns (reached files, direct refs, folder refs, literals)."""
    def abspath(res):
        return res[len('res://'):]
    reached, queue = {ENTRY}, [ENTRY]
    direct, folders, literals = {}, {}, set()
    while queue:
        cur = queue.pop()
        f = ROOT / cur
        if not f.is_file():
            continue
        suffix = f.suffix.lower()
        if suffix not in SCAN_EXT:
            if suffix == '.glb':
                data = f.read_bytes()
                for sib in f.parent.iterdir():
                    if sib.suffix.lower() == '.png' and sib.name.encode() in data:
                        rel = sib.relative_to(ROOT).as_posix()
                        direct.setdefault(rel, []).append((cur, 0))
                        reached.add(rel)
            continue
        text = f.read_text(encoding='utf-8', errors='replace')
        local_dirs = []
        for n, line in enumerate(text.split('\n'), 1):
            for m in RES.finditer(line):
                rel = abspath(m.group())
                if rel.endswith('/'):
                    folders.setdefault(rel, []).append((cur, n))
                    local_dirs.append(rel)
                    continue
                if (ROOT / rel).is_file():
                    direct.setdefault(rel, []).append((cur, n))
                    if rel not in reached:
                        reached.add(rel)
                        queue.append(rel)
                elif (ROOT / rel).is_dir():
                    folders.setdefault(rel + '/', []).append((cur, n))
                    local_dirs.append(rel + '/')
        if suffix in ('.gd', '.tscn'):
            lits = [(n, m.group(1)) for n, line in enumerate(text.split('\n'), 1) for m in LIT.finditer(line)]
            for _, s in lits:
                literals.add(s)
            for d in local_dirs:
                for n, s in lits:
                    if s and '/' not in s and (ROOT / d / s).is_file():
                        direct.setdefault(d + s, []).append((cur, n))
                        if d + s not in reached:
                            reached.add(d + s)
                            queue.append(d + s)
    return reached, direct, folders, literals


def asset_usage(rel, direct, folders, literals):
    if rel in direct:
        notes = ['%s : %d줄' % (f, n) if n else f for f, n in direct[rel][:4]]
        return 'direct', notes
    d = rel.rsplit('/', 1)[0] + '/'
    hit = [k for k in folders if rel.startswith(k)]
    if hit:
        stem = re.sub(r'(_actions|_v\d+|_\d+)+$', '', Path(rel).stem)
        refs = folders[hit[0]]
        where = ['%s : %d줄 (폴더 %s)' % (f, n, hit[0]) for f, n in refs[:3]]
        if stem in literals:
            return 'composed', where + ['이름 「%s」이 코드에 문자열로 나옵니다.' % stem]
        return 'folder', where + ['파일 이름과 맞는 문자열을 코드에서 찾지 못했습니다.']
    sibling = any(k.rsplit('/', 1)[0] == rel.rsplit('/', 1)[0] and k.endswith('.glb') for k in direct)
    return 'none', (['같은 폴더의 3D 모델은 쓰입니다. 이 그림은 모델 안에 이미 포함됐거나 원본 보관용일 수 있습니다.'] if sibling else [])


def source_docs(rel):
    """ATTRIBUTION/ASSET/LICENSE/LEDGER/README files in the asset's folders (up to chapter1/art)."""
    out, folder = [], (ROOT / rel).parent
    art = ROOT / 'chapter1/art'
    pat = re.compile(r'^(ATTRIBUTION|ASSET|LICENSE|SYNTHESIZED|README|AUDIO-LEDGER)', re.I)
    while True:
        for f in sorted(folder.iterdir()):
            if f.is_file() and (pat.match(f.name) or 'LEDGER' in f.name.upper()) and f.suffix.lower() in ('.md', '.json', '.txt'):
                out.append({'label': f.name, 'path': f.relative_to(ROOT).as_posix()})
        if folder == art or art not in folder.parents:
            break
        folder = folder.parent
    return out


def glb_info(path):
    import struct
    data = path.read_bytes()
    try:
        n = struct.unpack_from('<I', data, 12)[0]
        doc = json.loads(data[20:20 + n].decode('utf-8'))
    except Exception:
        return None
    return {'meshes': len(doc.get('meshes', [])), 'materials': len(doc.get('materials', [])),
            'animations': [a.get('name', '(이름 없음)') for a in doc.get('animations', [])], 'skins': len(doc.get('skins', []))}


def png_size(path):
    import struct
    with path.open('rb') as f:
        h = f.read(24)
    if h[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', h[16:24])
    return None


def asset_entities(c):
    reached, direct, folders, literals = scan_references()
    art = ROOT / 'chapter1/art'
    cat_of = {'.glb': ('models', '3D 모델'), '.png': ('images', '그림'), '.svg': ('images', '아이콘'), '.wav': ('sounds', '소리')}
    for f in sorted(art.rglob('*')):
        if not f.is_file() or f.suffix.lower() not in cat_of:
            continue
        rel = f.relative_to(ROOT).as_posix()
        cat, typ = cat_of[f.suffix.lower()]
        if rel.startswith('chapter1/art/characters/'):
            cat, typ = 'characters', '주인공 원화'
        elif 'attempts/' in rel:
            typ = '시도작'
        elif f.suffix.lower() == '.png' and ('/actors/' in rel or 'cast' in f.name):
            typ = '스프라이트 시트'
        usage, notes = asset_usage(rel, direct, folders, literals)
        size = f.stat().st_size
        pairs_ = [('경로', rel), ('파일 크기', '%.1f KB' % (size / 1024))]
        previews = []
        if f.suffix.lower() == '.glb':
            info = glb_info(f)
            if info:
                pairs_ += [('메시', info['meshes']), ('재질', info['materials']), ('뼈대', info['skins']),
                           ('애니메이션', ', '.join(info['animations']) or '없음')]
            previews.append({'kind': 'glb', 'path': rel})
        elif f.suffix.lower() == '.png':
            wh = png_size(f)
            if wh:
                pairs_.append(('가로×세로', '%d×%d' % wh))
            previews.append({'kind': 'image', 'path': rel})
        elif f.suffix.lower() == '.svg':
            previews.append({'kind': 'image', 'path': rel})
        else:
            previews.append({'kind': 'audio', 'path': rel})
        sect = [pairs('파일 정보', pairs_)]
        links = source_docs(rel)
        c.add('asset:' + rel, cat, typ, f.name, '%s · %s' % (rel.rsplit('/', 1)[0].replace('chapter1/art/', ''), USAGE_LABELS[usage]),
              sect, src(rel), previews, usage, notes, links)
    return len(reached)


# ------------------------------------------------------------------ code
ROLE_FOLDERS = [
    ('chapter1/app', '조립·입력(app)'), ('chapter1/core', '코어(게임 규칙)'), ('chapter1/presentation', '표현(소리·프레임 측정)'),
    ('chapter1/view/hud', '표현: 화면 표시(hud)'), ('chapter1/view/fx', '표현: 효과(fx)'),
    ('chapter1/view/actors', '표현: 캐릭터(actors)'), ('chapter1/view/world', '표현: 바닥·배경(world)'),
    ('chapter1/view', '표현: 옛 층과 셰이더(view 바로 아래)'), ('chapter1/tests', '검사·측정 도구(tests)'), ('combat', '전투 모듈(combat)'),
]


def code_entities(c):
    reached, *_ = scan_references()
    files = [p for p in list((ROOT / 'chapter1').rglob('*.gd')) + list((ROOT / 'combat').rglob('*.gd')) + list((ROOT / 'chapter1').rglob('*.gdshader'))]
    groups = {}
    for p in sorted(files):
        rel = p.relative_to(ROOT).as_posix()
        for folder, label in ROLE_FOLDERS:
            if rel.startswith(folder + '/') and (folder != 'chapter1/view' or '/' not in rel[len(folder) + 1:]):
                groups.setdefault(folder, []).append(rel)
                break
    labels = dict(ROLE_FOLDERS)
    for folder, label in ROLE_FOLDERS:
        rels = groups.get(folder, [])
        if not rels:
            continue
        rows, total, hit = [], 0, 0
        for rel in rels:
            n = len((ROOT / rel).read_text(encoding='utf-8', errors='replace').split('\n'))
            total += n
            r = rel in reached
            hit += r
            rows.append([rel.split('/', 2)[-1] if folder == 'chapter1' else rel, n, '예' if r else '아니오'])
        c.add('code:' + folder, 'code', '스크립트 묶음', label, '%d개 파일 · %d줄 · 실행 진입점에서 이어짐 %d개' % (len(rels), total, hit),
              [table('파일', ['파일', '줄 수', '진입점에서 이어짐'], rows),
               lines('읽는 법', ['「이어짐」은 chapter1/ChapterOne.tscn에서 시작해 res:// 문자열을 따라간 정적 검사입니다. 아니오는 사용하지 않는다는 뜻이 아니라 이 검사로 연결을 못 찾았다는 뜻입니다(검사 도구는 원래 실행 경로 밖입니다).'])],
              src(folder if (ROOT / folder).exists() else rels[0]))
    return reached


# ------------------------------------------------------------------ agents
def parse_frontmatter(text):
    """Minimal `key: value` reader for the leading --- block (no YAML library, no eval)."""
    rows = text.replace('\r\n', '\n').split('\n')
    if not rows or rows[0].strip() != '---':
        raise ValueError('머리글(---)이 없습니다')
    out = {}
    for ln in rows[1:]:
        if ln.strip() == '---':
            return out
        if ':' in ln and not ln.startswith((' ', '\t')):
            k, v = ln.split(':', 1)
            out[k.strip()] = v.strip()
    raise ValueError('머리글이 닫히지 않았습니다')


def agent_entities(c):
    rows = []
    for f in sorted((ROOT / '.claude/agents').glob('*.md')):
        rel = f.relative_to(ROOT).as_posix()
        try:
            meta = parse_frontmatter(f.read_text(encoding='utf-8'))
        except ValueError as e:
            c.warnings.append('에이전트 정의를 읽지 못했습니다: %s (%s)' % (e, rel))
            continue
        desc = meta.get('description', '')
        rows.append((meta.get('name') or f.stem, re.split(r'(?<=[.])\s', desc, 1)[0], meta.get('model', '(지정 없음)'),
                     meta.get('tools', '(지정 없음)'), rel, desc))
    c.add('agents:overview', 'agents', '표', '에이전트 한눈에', '정의 %d개' % len(rows),
          [table('이름 · 모델 · 역할', ['이름', '모델', '역할'], [[n, m, r] for n, r, m, t, _, _ in rows]),
           lines('읽는 법', ['`.claude/agents/`의 정의 파일 머리글을 읽은 값입니다. 역할은 설명의 첫 문장입니다.'])])
    for n, r, m, t, rel, desc in rows:
        c.add('agents:' + n, 'agents', '에이전트 정의', n, '%s · %s' % (m, r),
              [pairs('정보', [('이름', n), ('모델', m), ('쓸 수 있는 도구', t), ('정의 파일', rel)]),
               lines('설명 전문', [desc])], src(rel), links=[{'label': '정의 파일 열기', 'path': rel}])


# ------------------------------------------------------------------ docs and quality
def doc_entities(c):
    docs = ROOT / 'docs'
    for f in sorted(docs.rglob('*')):
        if not f.is_file() or f.suffix.lower() not in ('.md', '.json'):
            continue
        rel = f.relative_to(ROOT).as_posix()
        parts = f.relative_to(docs).parts
        kind = {'specs': '명세', 'reviews': '검수', 'story': '세계관·스토리'}.get(parts[0], '옛 로드맵 문서' if parts[0].startswith('roadmap') else '문서')
        if len(parts) == 1 and 'STORY' in f.stem.upper():
            kind = '세계관·스토리'
        title, body = f.stem, ''
        if f.suffix.lower() == '.md':
            for ln in f.read_text(encoding='utf-8', errors='replace').split('\n'):
                s = ln.strip()
                if s.startswith('# ') and title == f.stem:
                    title = s[2:].strip()
                elif s and not s.startswith('#') and not body and title != f.stem:
                    body = s[:140]
        c.add('doc:' + rel, 'docs', kind, title, body or rel, [pairs('정보', [('경로', rel), ('종류', kind), ('크기', '%.1f KB' % (f.stat().st_size / 1024))])], src(rel), links=[{'label': '문서 열기', 'path': rel}])


def quality_entities(c, warnings):
    p = 'docs/QUALITY-TARGETS.ko.md'
    try:
        text = read(p)
    except OSError:
        warnings.append('품질 목표 문서를 읽지 못했습니다: ' + p)
        return
    heading, header, count, lst = '', None, 0, []

    def flush():
        nonlocal lst
        if lst:
            c.add('quality:list:' + heading, 'quality', '확인 항목', heading, '%d개 질문·항목' % len(lst), [lines(heading, lst)], src(p, text, heading))
        lst = []
    for ln in text.split('\n'):
        s = ln.strip()
        if s.startswith('#'):
            flush()
            heading, header = s.lstrip('#').strip(), None
            continue
        if s.startswith('|'):
            cells = [x.strip() for x in s.strip('|').split('|')]
            if header is None:
                header = cells
            elif not all(re.fullmatch(r':?-+:?', x) for x in cells):
                count += 1
                row = dict(zip(header, cells))
                cur = row.get('현재') or row.get('확인 방법', '')
                goal = row.get('목표') or row.get('기준', '')
                c.add('quality:%s:%s' % (heading.split('.')[0], cells[0]), 'quality', '목표 표', cells[0],
                      ('목표: %s' % goal) + (' · 현재: %s' % cur if row.get('현재') else ''),
                      [pairs(heading, list(row.items())), lines('읽는 법', ['문서에 적힌 값입니다. 이 툴이 직접 잰 값이 아니며 날짜는 문서의 설명을 확인하세요.'])], src(p, text, cells[0]), links=[{'label': '문서 열기', 'path': p}])
            continue
        header = None if s == '' else header
        m = re.match(r'^\d+\.\s+(.*)', s)
        if m:
            lst.append(m.group(1))
    flush()
    if not count:
        warnings.append('품질 목표 표를 하나도 읽지 못했습니다. 문서 링크만 표시합니다.')
        c.add('quality:doc', 'quality', '문서', '품질 목표 문서', '표를 읽지 못해 문서 링크만 제공합니다', [], src(p), links=[{'label': '문서 열기', 'path': p}])


# ------------------------------------------------------------------ entry
def generate():
    c = Catalog()
    warnings = c.warnings
    steps = [('한 판의 기술', growth_entities), ('영구 성장', perm_entities), ('전투 수치', combat_entities), ('장비', gear_entities),
             ('에셋', asset_entities), ('코드 구성', code_entities), ('에이전트', agent_entities), ('문서', doc_entities)]
    for label, fn in steps:
        try:
            fn(c)
        except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
            warnings.append('%s를 읽지 못했습니다: %s: %s' % (label, type(e).__name__, e))
    for label, fn in (('구역과 의식', world_entities), ('품질 목표', quality_entities)):
        try:
            fn(c, warnings)
        except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
            warnings.append('%s를 읽지 못했습니다: %s: %s' % (label, type(e).__name__, e))
    counts = {k: 0 for k, _ in CATEGORIES}
    for e in c.entities:
        counts[e['category']] += 1
    usage = {}
    for e in c.entities:
        if e.get('usage'):
            usage[e['usage']] = usage.get(e['usage'], 0) + 1
    return {'basis': '작업 폴더의 현재 파일', 'root': ROOT.name, 'generated_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'categories': [{'key': k, 'name': n, 'count': counts[k]} for k, n in CATEGORIES],
            'usage_labels': USAGE_LABELS, 'usage_counts': usage,
            'entities': c.entities, 'allowed': sorted(c.allowed), 'warnings': warnings}


if __name__ == '__main__':
    r = generate()
    print(json.dumps({k: r[k] for k in ('basis', 'categories', 'usage_counts', 'warnings')}, ensure_ascii=False, indent=1))
