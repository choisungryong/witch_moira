"""Human playtest log: questions read from the docs, answers saved as _local/playtests/<date-time>.json.

Never reads or writes the player's save folder. The play result is chosen by the user.
"""
import hashlib, json, os, re, subprocess, threading, time
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT

DIR = ROOT / '_local' / 'playtests'
LOCK = threading.Lock()
WITCHES = {'': '고르지 않음', 'frost': '냉기 마녀', 'ember': '불꽃 마녀', 'storm': '번개 마녀'}
RESULTS = {'': '고르지 않음', 'win': '승리', 'down': '쓰러짐', 'quit': '포기'}
SOUNDS = {'': '모름', 'on': '켰음', 'off': '껐음'}
SCALE = {1: '전혀 아니다', 2: '아니다', 3: '보통', 4: '그렇다', 5: '매우 그렇다'}
Q = 'docs/QUALITY-TARGETS.ko.md'
D6 = 'docs/specs/D6-loot-farming-spec.ko.md'
A4 = 'docs/specs/A4-ui-redesign-direction.ko.md'

# Used when a document cannot be read or its question section is not found.
DEFAULTS = {
    'combat': ('전투 화면', Q, ['맞았다는 느낌이 소리 없이도 드는가.', '가장 좋았던 순간은 언제였나.', '지루했던 구간은 어디였나.', '죽었다면 왜 죽었는지 알았나.', '한 판 더 하고 싶은가.']),
    'hud': ('화면 표시(HUD)', Q, ['처음 보는 사람이 설명 없이 생명·스킬·목표가 어디 있는지 짚을 수 있는가.']),
    'gear': ('장비와 득템', Q, ['좋은 장비가 떨어진 순간을 소리와 화면으로 알아챘는가. 주운 장비를 착용할지 3초 안에 판단할 수 있었는가.']),
    'compare': ('참고 대상과의 비교', Q, ['효과의 밀도', '빛과 대비', '캐릭터의 존재감', '화면 표시의 완성도', '큰 순간의 연출']),
    'loot': ('장비 파밍(D6)', D6, ['봉인을 깰 때 드러나는 장비가 기다려졌는가, 귀찮았는가', '도박에 재를 쓰고 싶었는가, 무엇을 노렸는가', '세트를 맞추려고 좋은 전설을 벗은 적이 있는가', '착용 창에서 바꿀지 말지 3초 안에 정했는가', '한 판 더 하고 싶은 이유가 장비였는가']),
    'ui': ('화면 재디자인(A4)', A4, ['캐릭터 선택에서 원화가 "고르고 싶은 사람"으로 보이는가. 의상 칸이 그 매력을 더하는가.', '전투 줄의 판을 지운 것이 "깔끔함"으로 읽히는가, "덜 만든 것"으로 읽히는가.', '세 목업 가운데 어느 쪽이 이 게임이라고 느껴지는가. (가)가 금박 화면처럼 과하게 보이지 않는가.']),
}
ORDER = ['combat', 'hud', 'gear', 'compare', 'loot', 'ui']
COMPARE_HINT = '1 뒤처짐 · 3 비슷함 · 5 앞섬'


def _read(rel, root):
    try:
        return (root / rel).read_text(encoding='utf-8')
    except OSError:
        return None


def _section(text, start, stop_re=r'^#{1,3} '):
    """Lines after the first line containing `start`, up to the next heading."""
    rows = text.replace('\r\n', '\n').split('\n')
    out, on = [], False
    for ln in rows:
        if not on:
            on = start in ln
            continue
        if re.match(stop_re, ln):
            break
        out.append(ln)
    return out if on else []


def parse_doc_questions(root=None):
    """{group: [question text]} for the groups the documents currently yield (empty groups omitted)."""
    root = root or ROOT
    found = {}
    q = _read(Q, root)
    if q:
        nums = [re.match(r'^\d+\.\s+(.*)', s.strip()) for s in _section(q, '### 사람이 플레이하고 답하는 것')]
        found['combat'] = [m.group(1) for m in nums if m]
        evals = {}
        for h, key in (('## 3. ', 'hud'), ('## 4. ', 'gear')):
            body = _section(q, h, r'^## ')
            evals[key] = [re.sub(r'^사람 평가:\s*', '', s.strip()) for s in body if s.strip().startswith('사람 평가:')]
        found.update(evals)
        body = '\n'.join(_section(q, '## 5. ', r'^## '))
        m = re.search(r'다음 다섯 가지를[^:]*:\s*([^.]+?)\.\s', body)
        if m:
            found['compare'] = [x.strip() for x in m.group(1).split(',') if x.strip()]
    d = _read(D6, root)
    if d:
        m = re.search(r'사용자 플레이 질문[^:：]*[:：]\s*([^\n]+)', '\n'.join(_section(d, '## 12. ', r'^## ')))
        if m:
            parts = re.split(r'[①②③④⑤⑥⑦⑧⑨]', m.group(1))
            found['loot'] = [p.strip().rstrip('.') for p in parts if p.strip()]
    a = _read(A4, root)
    if a:
        body = _section(a, '**사람만 판단할 것**', r'^## ')
        # 참고 대상 비교 항목은 위의 compare 질문과 겹치므로 문서 이름을 가리키는 줄은 뺀다
        found['ui'] = [re.sub(r'^-\s*', '', s.strip()) for s in body if s.strip().startswith('- ') and 'QUALITY-TARGETS' not in s]
    return {k: v for k, v in found.items() if v}


def qid(group, text):
    return '%s-%s' % (group, hashlib.sha1(text.encode('utf-8')).hexdigest()[:6])


def questions(root=None):
    """(groups, warnings). Each group {key,name,source,from_doc,items:[{id,text,hint}]}."""
    doc = parse_doc_questions(root)
    groups, warnings = [], []
    for key in ORDER:
        name, source, default = DEFAULTS[key]
        from_doc = key in doc
        texts = doc[key] if from_doc else default
        if not from_doc:
            warnings.append('「%s」 질문을 문서(%s)에서 읽지 못해 내장 기본 질문을 씁니다.' % (name, source))
        groups.append({'key': key, 'name': name, 'source': source, 'from_doc': from_doc,
                       'items': [{'id': qid(key, t), 'text': t, 'hint': COMPARE_HINT if key == 'compare' else ''} for t in texts]})
    return groups, warnings


def build_info(root=None):
    """Commit hash and whether the working tree has changes, read with git. Values are None when git cannot answer."""
    root = root or ROOT

    def git(*args):
        try:
            done = subprocess.run(['git', *args], cwd=str(root), capture_output=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            return None
        return done.stdout.decode('utf-8', 'replace').strip() if done.returncode == 0 else None
    commit = git('rev-parse', '--short', 'HEAD')
    status = git('status', '--porcelain', '--untracked-files=no')
    return {'commit': commit, 'dirty': None if status is None else bool(status), 'changed_files': None if status is None else len([x for x in status.split('\n') if x])}


def _text(v, limit, field):
    if v is None:
        return ''
    if not isinstance(v, str) or len(v) > limit:
        raise ValueError('%s: text up to %d characters' % (field, limit))
    return v


def validate(payload, groups):
    """Return the record body to store (without id/build). Raises ValueError on anything unexpected."""
    allowed = {'played_at', 'witch', 'result', 'minutes', 'sound', 'resolution', 'answers', 'memo'}
    if not isinstance(payload, dict) or set(payload) - allowed:
        raise ValueError('Unexpected fields')
    played = payload.get('played_at')
    if not isinstance(played, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', played):
        raise ValueError('played_at must look like 2026-11-17 21:30')
    try:
        time.strptime(played, '%Y-%m-%d %H:%M')
    except ValueError:
        raise ValueError('played_at is not a real date')
    for key, table in (('witch', WITCHES), ('result', RESULTS), ('sound', SOUNDS)):
        if payload.get(key, '') not in table:
            raise ValueError('Invalid ' + key)
    minutes = payload.get('minutes')
    if minutes is not None and (type(minutes) is not int or not 0 <= minutes <= 600):
        raise ValueError('minutes must be 0-600')
    known = {i['id']: (g, i['text']) for g in groups for i in g['items']}
    answers = payload.get('answers', {})
    if not isinstance(answers, dict) or len(answers) > 200:
        raise ValueError('answers must be an object')
    stored = {}
    for k, v in answers.items():
        if k not in known or not isinstance(v, dict) or set(v) - {'score', 'note'}:
            raise ValueError('Unknown question or fields')
        score = v.get('score', 0)
        if type(score) is not int or not 0 <= score <= 5:
            raise ValueError('score must be 0-5')
        note = _text(v.get('note'), 400, 'note')
        if score or note:
            g, text = known[k]
            stored[k] = {'group': g['key'], 'group_name': g['name'], 'text': text, 'score': score, 'note': note}
    return {'played_at': played, 'witch': payload.get('witch', ''), 'result': payload.get('result', ''), 'minutes': minutes,
            'sound': payload.get('sound', ''), 'resolution': _text(payload.get('resolution'), 20, 'resolution').strip(),
            'answers': stored, 'memo': _text(payload.get('memo'), 12000, 'memo')}


def save(payload, groups, folder=None, build=None, now=None):
    folder = folder or DIR
    body = validate(payload, groups)
    body['build'] = build if build is not None else build_info()
    body['saved_at'] = now or time.strftime('%Y-%m-%d %H:%M:%S')
    stem = body['played_at'].replace(' ', '-').replace(':', '').replace('-', '')
    stem = stem[:8] + '-' + stem[8:]
    with LOCK:
        folder.mkdir(parents=True, exist_ok=True)
        n, name = 1, stem
        while (folder / (name + '.json')).exists():
            n += 1
            name = '%s-%d' % (stem, n)
        body['id'] = name
        path = folder / (name + '.json')
        temp = folder / (name + '.tmp')
        with temp.open('w', encoding='utf-8', newline='\n') as f:
            json.dump(body, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    return body


def load_all(folder=None):
    """(records newest first, skipped file names)."""
    folder = folder or DIR
    records, skipped = [], []
    if folder.is_dir():
        for p in sorted(folder.glob('*.json')):
            try:
                v = json.loads(p.read_text(encoding='utf-8'))
                if not isinstance(v, dict) or not isinstance(v.get('answers'), dict) or not isinstance(v.get('played_at'), str):
                    raise ValueError('shape')
                v['id'] = p.stem
                records.append(v)
            except (OSError, ValueError):
                skipped.append(p.name)
    records.sort(key=lambda r: (r['played_at'], r['id']), reverse=True)
    return records, skipped


def trend(records):
    """Per question, scores in play order (oldest first). Only answered (score > 0) points."""
    rows = {}
    for r in sorted(records, key=lambda r: (r['played_at'], r['id'])):
        for k, a in r['answers'].items():
            if isinstance(a, dict) and type(a.get('score')) is int and a['score'] > 0:
                row = rows.setdefault(k, {'id': k, 'group_name': a.get('group_name', ''), 'text': a.get('text', k), 'points': []})
                row['text'] = a.get('text', row['text'])
                row['points'].append({'record': r['id'], 'played_at': r['played_at'], 'score': a['score']})
    return sorted(rows.values(), key=lambda x: (x['group_name'], x['text']))


def overview(folder=None, root=None):
    groups, warnings = questions(root)
    records, skipped = load_all(folder)
    if skipped:
        warnings.append('읽지 못한 기록 파일: ' + ', '.join(skipped))
    return {'questions': groups, 'scale': {str(k): v for k, v in SCALE.items()},
            'options': {'witch': WITCHES, 'result': RESULTS, 'sound': SOUNDS},
            'build': build_info(root), 'records': records, 'trend': trend(records), 'warnings': warnings,
            'folder': '_local/playtests'}
