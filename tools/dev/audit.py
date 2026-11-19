"""기록과 약속이 어긋났는가를 한 장으로 센다. 회귀(run_all.py)가 통과/실패를 본다면, 이것은 수를 세고 지난번과 견준다.

    python tools/dev/audit.py                       # 전부 돌리고 _local/audit/<날짜-시각>/ 에 audit.md, audit.json
    python tools/dev/audit.py --list                # 점검 줄 이름
    python tools/dev/audit.py --only wording,decisions
    python tools/dev/audit.py --strict              # 0이 아닌 구멍이 하나라도 있으면 종료 코드 1
    python tools/dev/audit.py --out=_local/audit/내이름   # 출력 폴더(_local 아래여야 한다)

이 점검은 기록의 유무와 일치만 본다. 품질·재미·저작권의 실제 여부는 보지 않는다.

기준선 방식: 종료 코드는 "지난번보다 나빠진 줄"이 있을 때만 1이다(--strict면 구멍이 하나라도 있으면 1).
지난번은 _local/audit/ 아래 가장 최근 audit.json 에서 줄마다 찾는다(--only로 일부만 돌린 기록도 그 줄에는 쓴다).
처음 실행은 기준선을 만들고 0이다. 도구 하나가 죽거나 읽을 수 없으면 그 줄만 "못 봄"으로 적고 나머지는 계속한다.
지난번에 보였는데 이번에 못 본 줄은 나빠짐으로 센다(구멍이 숨은 것일 수 있다).
표준 라이브러리만 쓴다. 게임·Godot를 실행하지 않고, 다른 도구의 본체와 데이터·문서를 고치지 않는다.
"""
from pathlib import Path
import argparse, concurrent.futures, datetime, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
NOTICE = '이 점검은 기록의 유무와 일치만 본다. 품질·재미·저작권의 실제 여부는 보지 않는다.'
TOOL_TIMEOUT = 300

LOWER, HIGHER, INFO = 'lower', 'higher', 'info'  # 늘면 나쁨 / 줄면 나쁨 / 비교만


class Unseen(Exception):
    """이 줄은 볼 수 없었다(도구가 죽음, 출력을 읽지 못함)."""


class Context:
    def __init__(self, root, local, work):
        self.root, self.local, self.work = Path(root), Path(local), Path(work)

    def run(self, args, timeout=TOOL_TIMEOUT):
        """파이썬 도구를 하위 프로세스로 부른다. (종료 코드, 표준 출력 글). 시간이 넘으면 Unseen."""
        env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
        try:
            done = subprocess.run([sys.executable] + [str(a) for a in args], cwd=self.root, capture_output=True, timeout=timeout, env=env)
        except subprocess.TimeoutExpired:
            raise Unseen('시간 제한(%d초)을 넘었다: %s' % (timeout, args[0]))
        except OSError as error:
            raise Unseen('실행하지 못했다: %s' % error)
        return done.returncode, done.stdout.decode('utf-8', 'replace'), done.stderr.decode('utf-8', 'replace')


def metric(key, label, value, direction=LOWER):
    return {'key': key, 'label': label, 'value': value, 'direction': direction}


# ---------------------------------------------------------------------------------------------------- 점검 줄

def line_asset_ledger(ctx):
    code, out, err = ctx.run(['tools/art/asset_ledger.py', 'check'])
    errors = re.search(r'== 오류[^:\n]*: (\d+)', out)
    summary = re.search(r'== 요약: 항목 (\d+), 출처 기록 갖춤 (\d+), 배포 가능 (\d+), 미확인 있음 (\d+)', out)
    unfit = re.search(r'== 배포 불가로 봐야 하는 항목 (\d+)', out)
    if not (errors and summary and unfit):
        raise Unseen('출력을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    items, complete, ready, unknown = (int(x) for x in summary.groups())
    metrics = [metric('errors', '원장 오류', int(errors.group(1))),
               metric('unknown', '미확인 칸이 있는 항목', unknown),
               metric('not_ready', '배포 불가로 보는 항목', int(unfit.group(1))),
               metric('ready', '배포 가능(사람이 확인한 것)', ready, HIGHER),
               metric('items', '원장 항목', items, INFO)]
    # 자리표(asset_slots.json)와 원장의 대조(T7-2). 자리표가 없거나 옛 출력이면 이 줄들은 없다.
    slot_warn = re.search(r'== 자리표·소리 표 경고[^:\n]*: (\d+)', out)
    slotless = re.search(r'== 자리 없음[^:\n]*: (\d+)', out)
    if slot_warn:
        metrics.append(metric('slot_warnings', '자리표가 가리키는데 원장에 없거나 파일이 없는 것', int(slot_warn.group(1))))
    if slotless:
        metrics.append(metric('slotless', '원장에는 있는데 어느 자리에도 없는 파일(안 쓰임 후보일 뿐)', int(slotless.group(1)), INFO))
    return {'metrics': metrics,
            'detail': ['출처 기록을 갖춘 항목 %d. "미확인"은 구멍이지 오류가 아니다(에셋을 바꿀 계획이라 지금 메우지 않는다).' % complete]}


def line_model_records(ctx):
    code, out, err = ctx.run(['tools/art/asset_intake.py', '--scan', 'chapter1/art', '--json'])
    try:
        data = json.loads(out)
    except ValueError:
        raise Unseen('JSON을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    holes = [h for m in data.get('models', []) for h in m.get('holes', [])] + [h for r in data.get('other_records', []) for h in r.get('holes', [])]
    broken = [m for m in data.get('models', []) if m.get('error')]
    hole_errors = sum(1 for h in holes if h.get('severity') == '오류') + len(broken)
    hole_warns = sum(1 for h in holes if h.get('severity') != '오류')
    dirs = data.get('dirs_without_record', [])
    return {'metrics': [metric('errors', '기록 오류(가리키는 파일 없음 등)', hole_errors),
                        metric('warns', '기록 경고', hole_warns),
                        metric('dirs_without_record', '출처 기록 없는 폴더', len(dirs)),
                        metric('models', '모델(GLB)', len(data.get('models', [])), INFO)],
            'detail': ['출처 기록 없는 폴더: ' + ', '.join('%s(%d)' % (d['dir'].replace('chapter1/art/', ''), d['files']) for d in dirs)] if dirs else []}


def line_audio_ledger(ctx):
    path = ctx.work / 'audio-ledger.json'
    code, out, err = ctx.run(['tools/dev/audio_ledger_check.py', '--json', str(path)])
    if code == 2 or not path.is_file():
        raise Unseen('소리 원장을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    packs = json.loads(path.read_text(encoding='utf-8'))
    problems = sum(len(p.get(k, [])) for p in packs for k in ('no_entry', 'hash_mismatch', 'entry_without_file', 'entry_without_sha'))
    return {'metrics': [metric('problems', '원장 문제(항목 없음·해시 불일치·파일 없음)', problems),
                        metric('unverified', '출처 미확인 항목', sum(len(p.get('unverified', [])) for p in packs)),
                        metric('files', '소리 파일', sum(p.get('files', 0) for p in packs), INFO)],
            'detail': []}


def line_wording(ctx):
    code, out, err = ctx.run(['tools/dev/wording_lint.py', '--json'])
    try:
        data = json.loads(out)
    except ValueError:
        raise Unseen('JSON을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    return {'metrics': [metric('fail', '금지(실패)', int(data['fail'])), metric('warn', '주의(경고)', int(data['warn'])),
                        metric('pending', '결정 대기', int(data['pending'])), metric('texts', '검사한 글', int(data['texts']), INFO)],
            'detail': ['결정 대기는 규칙을 어긴 것이 아니라 사람의 판단을 기다리는 것이다.']}


def line_decisions(ctx):
    code, out, err = ctx.run(['tools/dev/decision_ledger.py', '--json'])
    try:
        data = json.loads(out)
        nxt = data['next_free']
    except (ValueError, KeyError):
        raise Unseen('JSON을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    return {'metrics': [metric('overlaps', '겹친 번호', len(data.get('overlaps', []))),
                        metric('overlaps_other', '겹침 후보(다른 체계 문서)', len(data.get('overlaps_other_systems', [])), INFO),
                        metric('numbers', '번호 수', len(data.get('entries', [])), INFO),
                        metric('next_n', '다음 빈 N 번호', int(nxt['N']['next']), INFO),
                        metric('next_u', '다음 빈 U 번호', int(nxt['U']['next']), INFO)],
            'detail': ['겹침은 제목의 한글 조각이 닮았는지로 한 추정이다.']}


def _judge_json(ctx):
    path = ctx.work / 'judge.json'
    if not path.is_file():
        code, out, err = ctx.run(['tools/dev/judge_targets.py', '--playtests', str(ctx.local / 'playtests'),
                                  '--out-json', str(path), '--out-md', str(ctx.work / 'judge.md')])
        if not path.is_file():
            raise Unseen('판정표를 만들지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    return json.loads(path.read_text(encoding='utf-8'))


def line_targets(ctx):
    code, out, err = ctx.run(['tools/dev/judge_targets.py', '--check-constants'])
    found = re.search(r'비교 (\d+)건, 일치 (\d+)건, 다른 것·결정이 필요한 것 (\d+)건', out)
    if not found:
        raise Unseen('출력을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    rows = _judge_json(ctx)['rows']
    conflicts = len({r['key'] for r in rows if r.get('conflict')})
    return {'metrics': [metric('mismatch', '박힌 상수가 목표 파일과 다른 것', int(found.group(3))),
                        metric('conflicts', '문서끼리 목표가 달라 후보로 갈린 항목', conflicts),
                        metric('compared', '비교한 상수', int(found.group(1)), INFO)],
            'detail': ['도구는 상수를 고치지 않는다. 어느 쪽이 맞는지는 수치 단계에서 결정 기록과 함께 정한다.']}


def line_refmap(ctx):
    out_dir = ctx.root / '_local' / 'audit-work' / 'refactor-map'  # refactor_map 은 저장소의 _local 아래에만 쓴다
    code, out, err = ctx.run(['tools/dev/refactor_map.py', '--out', str(out_dir), '--quiet'])
    path = out_dir / 'refmap.json'
    if not path.is_file():
        raise Unseen('참조 지도를 만들지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    s = json.loads(path.read_text(encoding='utf-8'))['summary']
    return {'metrics': [metric('layer_methods', '남은 옛 층 메서드', int(s['layer_methods'])),
                        metric('unreferenced_code', '참조 없는 코드 파일', int(s['unreferenced_code_files'])),
                        metric('unreachable_code', '뿌리에서 도달 못 하는 코드 파일', int(s['unreachable_from_roots_code_files'])),
                        metric('uncertain', '불확실(정적으로 못 가린 것)', int(s['uncertain'])),
                        metric('unreferenced_assets', '참조 없는 에셋', int(s['unreferenced_assets']), INFO),
                        metric('version_named', '버전 숫자 이름 파일', int(s['version_named_files']), INFO)],
            'detail': ['"참조 없음"은 죽은 코드가 아니라 삭제 후보일 뿐이다. 문자열로 조립한 경로는 이 지도가 보지 못한다.']}


def line_gallery(ctx):
    code, out, err = ctx.run(['tools/art/gallery.py', 'lint'])
    found = re.search(r'^summary: (\{.*\})', out, re.M)
    if not found:
        raise Unseen('출력을 읽지 못했다(종료 %d) %s' % (code, (err or out).strip()[-120:]))
    s = json.loads(found.group(1))
    problems = sum(int(s.get(k, 0)) for k in ('broken', 'no_id', 'duplicate_id', 'not_object', 'bad_file', 'prompt_file_missing',
                                              'prompt_file_not_txt', 'prompt_file_empty', 'selection_orphans'))
    return {'metrics': [metric('problems', '색인 문제 합계', problems),
                        metric('prompt_not_txt', '프롬프트 파일이 .txt 가 아님', int(s.get('prompt_file_not_txt', 0))),
                        metric('prompt_empty', '프롬프트 파일이 빔', int(s.get('prompt_file_empty', 0))),
                        metric('metas_not_in_index', '색인에 없는 시도 메타', int(s.get('attempt_metas_not_in_index', 0))),
                        metric('entries', '색인 항목', int(s.get('entries', 0)), INFO)],
            'detail': []}


def disabled_blocks(node, path=''):
    """JSON 안에서 "enabled": false 인 블록의 경로(점으로 이은 키)."""
    found = []
    if isinstance(node, dict):
        if node.get('enabled') is False:
            found.append(path or '(맨 위)')
        for key, value in node.items():
            found += disabled_blocks(value, (path + '.' if path else '') + key)
    elif isinstance(node, list):
        for i, value in enumerate(node):
            found += disabled_blocks(value, '%s[%d]' % (path, i))
    return found


def line_switches(ctx):
    data_dir = ctx.root / 'chapter1' / 'data'
    blocks = []
    for path in sorted(data_dir.glob('*.json')):
        try:
            tree = json.loads(path.read_text(encoding='utf-8'))
        except ValueError:
            raise Unseen('데이터 JSON을 읽지 못했다: ' + path.name)
        blocks += [(path.name, b) for b in disabled_blocks(tree)]
    notes = ''
    for name in ('CLAUDE.md', 'docs/DIRECTIVES-LEDGER.ko.md'):
        p = ctx.root / name
        if p.is_file():
            notes += p.read_text(encoding='utf-8') + '\n'
    unnoted = []
    for file, block in blocks:
        # 맨 위 블록은 파일 이름(run_spells)으로, 중첩은 점으로 이은 경로(rhythm.trial)로 적힌다.
        name = file[:-5] if block == '(맨 위)' else block
        if name + '.enabled' not in notes and ('`' + name + '`') not in notes:
            unnoted.append((file, block))
    shown = ['%s : %s' % (f, b if b != '(맨 위)' else f[:-5]) for f, b in blocks]
    return {'metrics': [metric('unnoted', 'CLAUDE.md(와 지시 장부)에 적히지 않은 꺼진 블록', len(unnoted)),
                        metric('disabled', '꺼진 블록("enabled": false)', len(blocks), INFO)],
            'detail': ['꺼진 블록: ' + '; '.join(shown), '적히지 않은 것: ' + ('; '.join('%s : %s' % u for u in unnoted) if unnoted else '없음')]}


PATH_ROOTS = ('chapter1/', 'combat/', 'docs/', 'tools/', 'art-archive/', '.claude/')
SKIP_WORDS = ('*', '<', '>', '{', '}', '|', '$', '%', '...', 'YYYY', 'NNN', 'XXX', '[', ']', '(', ')', '=', ',', ';')


def doc_paths(text):
    """백틱 안의 저장소 경로 후보. (경로, 원문) 목록. _local/ 은 git 밖이라 뺀다."""
    found = []
    for raw in re.findall(r'`([^`\n]+)`', text):
        s = raw.strip()
        if s.startswith('res://'):
            s = s[6:]
        s = re.sub(r'[#:]\S*$', '', s) if re.search(r'[#:]', s) else s
        s = s.rstrip('.,')
        if not s.startswith(PATH_ROOTS) or ' ' in s or any(w in s for w in SKIP_WORDS):
            continue
        found.append((s, raw))
    return found


def line_doc_paths(ctx):
    docs = [ctx.root / 'CLAUDE.md', ctx.root / 'chapter1' / 'art' / 'README.ko.md'] + sorted((ctx.root / 'docs').glob('*.md'))
    docs = [d for d in docs if d.is_file()]
    if not docs:
        raise Unseen('읽을 문서가 없다')
    missing, checked = [], 0
    for doc in docs:
        rel = doc.relative_to(ctx.root).as_posix()
        for path, raw in doc_paths(doc.read_text(encoding='utf-8')):
            checked += 1
            if not (ctx.root / path).exists():
                missing.append('%s -> %s' % (rel, path))
    missing = sorted(set(missing))
    return {'metrics': [metric('missing', '문서가 말하는데 없는 경로', len(missing)),
                        metric('checked', '확인한 경로(중복 포함)', checked, INFO), metric('docs', '읽은 문서', len(docs), INFO)],
            'detail': missing}


def similar_groups(names):
    """이름에서 숫자·버전 꼬리를 떼고 같아지는 것끼리 묶는다(셋 이상)."""
    groups = {}
    for name in names:
        stem = re.sub(r'(?i)([-_]?v?\d+|[-_][a-d])$', '', Path(name).stem)
        stem = re.sub(r'\d+', '#', stem)
        groups.setdefault(stem, []).append(name)
    return {k: v for k, v in groups.items() if len(v) >= 3}


def line_local_scripts(ctx):
    local = ctx.local
    per_folder, groups = {}, []
    if local.is_dir():
        for path in local.rglob('*'):
            if path.suffix.lower() in ('.py', '.gd', '.ps1', '.sh') and path.is_file():
                try:
                    top = path.relative_to(local).parts[0] if len(path.relative_to(local).parts) > 1 else '(맨 위)'
                except ValueError:
                    continue
                per_folder.setdefault(top, []).append(path.name)
        for folder, names in per_folder.items():
            groups += ['%s/ : %s*%d개 (%s…)' % (folder, stem, len(v), v[0]) for stem, v in similar_groups(names).items()]
    total = sum(len(v) for v in per_folder.values())
    ranked = sorted(per_folder.items(), key=lambda kv: -len(kv[1]))
    detail = ['폴더별: ' + ', '.join('%s %d' % (k, len(v)) for k, v in ranked[:12])] if ranked else ['_local/ 이 없거나 스크립트가 없다']
    detail += ['이름이 비슷한 묶음: ' + '; '.join(groups[:12])] if groups else []
    return {'metrics': [metric('scripts', '_local/ 일회용 스크립트(.py·.gd·.ps1·.sh)', total),
                        metric('similar', '이름이 비슷한 묶음(셋 이상)', len(groups)),
                        metric('folders', '스크립트가 든 폴더', len(per_folder), INFO)],
            'detail': detail}


def line_human(ctx):
    rows = [r for r in _judge_json(ctx)['rows'] if r.get('kind') == 'human']
    with_record = [r for r in rows if str(r.get('detail', '')).startswith('플레이 기록')]
    files = [p for p in (ctx.local / 'playtests').rglob('*') if p.is_file()] if (ctx.local / 'playtests').is_dir() else []
    return {'metrics': [metric('unrated', '사람 평가 항목 중 기록 없는 것', len(rows) - len(with_record)),
                        metric('with_record', '플레이 기록이 가리키는 항목', len(with_record), HIGHER),
                        metric('playtest_files', '_local/playtests/ 파일', len(files), HIGHER),
                        metric('human_total', '사람 평가 항목', len(rows), INFO)],
            'detail': ['기록이 있어도 이 도구는 판정하지 않는다. 재미·미감은 사용자 플레이로만 채운다.']}


LINES = [
    ('asset-ledger', '에셋 출처 원장', line_asset_ledger),
    ('model-records', '모델 출처 기록 구멍', line_model_records),
    ('audio-ledger', '소리 원장', line_audio_ledger),
    ('wording', '낱말 검사', line_wording),
    ('decisions', '결정 번호', line_decisions),
    ('targets', '목표 상수와 목표 충돌', line_targets),
    ('refmap', '참조 지도', line_refmap),
    ('gallery', '갤러리 색인', line_gallery),
    ('switches', '꺼진 스위치와 문서 대조', line_switches),
    ('doc-paths', '문서가 말하는 경로', line_doc_paths),
    ('local-scripts', '_local/ 일회용 스크립트', line_local_scripts),
    ('human', '사람 평가 미평가', line_human),
]


# ---------------------------------------------------------------------------------------------------- 기준선과 견주기

def is_worse(direction, delta):
    return (direction == LOWER and delta > 0) or (direction == HIGHER and delta < 0)


def compare(current, previous):
    """줄 하나(current)에 지난번 값을 붙인다. previous: 지난번의 같은 줄 또는 None. current 를 제자리에서 고친다."""
    prev_metrics = {m['key']: m for m in (previous or {}).get('metrics', [])}
    current['worse'] = False
    current['has_previous'] = previous is not None
    if current['status'] == 'unseen':
        # 지난번에 봤던 줄을 이번에 못 봤다면 구멍이 숨었을 수 있으므로 나빠짐으로 센다.
        current['worse'] = bool(previous) and previous.get('status') == 'seen'
        return current
    for m in current['metrics']:
        old = prev_metrics.get(m['key']) if previous and previous.get('status') == 'seen' else None
        m['previous'] = old['value'] if old else None
        m['delta'] = m['value'] - old['value'] if old else None
        m['worse'] = bool(old) and is_worse(m['direction'], m['delta'])
        current['worse'] = current['worse'] or m['worse']
    return current


def has_hole(line):
    """--strict: 늘면 나쁜 값이 0이 아니거나, 못 본 줄."""
    if line['status'] == 'unseen':
        return True
    return any(m['direction'] == LOWER and m['value'] > 0 for m in line['metrics'])


def collect(ctx, only=None, lines=None):
    """줄마다 도구를 불러 결과를 모은다. 한 줄이 어떻게 죽어도 그 줄만 'unseen'."""
    chosen = [l for l in (lines or LINES) if not only or l[0] in only]
    ctx.work.mkdir(parents=True, exist_ok=True)

    def one(entry):
        name, title, fn = entry
        base = {'id': name, 'title': title}
        try:
            result = fn(ctx)
            return dict(base, status='seen', metrics=result['metrics'], detail=result.get('detail', []))
        except Unseen as why:
            return dict(base, status='unseen', metrics=[], detail=[], reason=str(why))
        except Exception as error:  # 도구가 무엇으로 죽든 다른 줄은 계속한다
            return dict(base, status='unseen', metrics=[], detail=[], reason='%s: %s' % (type(error).__name__, error))

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return list(pool.map(one, chosen))


def previous_lines(audit_dir, skip=None, limit=30):
    """줄 이름 -> 가장 최근 기록의 그 줄. audit_dir/*/audit.json 을 이름 역순(최근 먼저)으로 본다."""
    found = {}
    if not Path(audit_dir).is_dir():
        return found, {}
    runs = {}
    for folder in sorted((p for p in Path(audit_dir).iterdir() if p.is_dir()), reverse=True)[:limit]:
        if skip and folder.resolve() == Path(skip).resolve():
            continue
        path = folder / 'audit.json'
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except ValueError:
            continue
        for line in data.get('lines', []):
            if line.get('id') not in found:
                found[line['id']] = line
                runs[line['id']] = folder.name
    return found, runs


def latest_result(audit_dir):
    """관리 툴용: 가장 최근 audit.json(없으면 None)."""
    if not Path(audit_dir).is_dir():
        return None
    for folder in sorted((p for p in Path(audit_dir).iterdir() if p.is_dir()), reverse=True):
        path = folder / 'audit.json'
        if path.is_file():
            try:
                return json.loads(path.read_text(encoding='utf-8'))
            except ValueError:
                continue
    return None


def fmt_delta(m):
    if m.get('delta') is None:
        return '처음'
    if m['delta'] == 0:
        return '='
    return ('▲ +%d' if m['delta'] > 0 else '▼ %d') % m['delta'] + (' (나빠짐)' if m.get('worse') else '')


def render_markdown(result):
    out = ['# 점검표', '', '> ' + result['notice'], '', '- 만든 때: %s' % result['made_at'],
           '- 비교 기준: 줄마다 `_local/audit/` 의 가장 최근 기록(처음 보는 줄은 이번이 기준선)', '']
    worse = [l['id'] for l in result['lines'] if l.get('worse')]
    out += ['- 지난번보다 나빠진 줄: ' + (', '.join(worse) if worse else '없음'), '']
    for line in result['lines']:
        out.append('## %s (`%s`)' % (line['title'], line['id']))
        out.append('')
        if line['status'] == 'unseen':
            out += ['**못 봄** — %s' % line.get('reason', ''), '']
            if line.get('worse'):
                out += ['지난번에는 볼 수 있었다. 나빠짐으로 센다.', '']
            continue
        out += ['| 항목 | 지금 | 지난번 | 차이 |', '|---|---|---|---|']
        for m in line['metrics']:
            prev = '-' if m.get('previous') is None else m['previous']
            out.append('| %s | %s | %s | %s |' % (m['label'], m['value'], prev, fmt_delta(m)))
        out.append('')
        for text in line.get('detail', [])[:60]:
            out.append('- ' + text)
        if line.get('detail'):
            out.append('')
    return '\n'.join(out) + '\n'


def write_atomic(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.replace(tmp, path)


def run_audit(root, local, out_dir, only=None, lines=None, strict=False):
    """(결과 사전, 종료 코드). 파일도 쓴다."""
    out_dir = Path(out_dir)
    ctx = Context(root, local, out_dir / 'work')
    current = collect(ctx, only, lines)
    prev_by_id, prev_run = previous_lines(Path(local) / 'audit', skip=out_dir)
    for line in current:
        compare(line, prev_by_id.get(line['id']))
        line['previous_run'] = prev_run.get(line['id'])
    result = {'version': 1, 'notice': NOTICE, 'made_at': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
              'only': sorted(only) if only else None, 'lines': current,
              'worse': [l['id'] for l in current if l.get('worse')],
              'holes': [l['id'] for l in current if has_hole(l)]}
    write_atomic(out_dir / 'audit.json', json.dumps(result, ensure_ascii=False, indent=1) + '\n')
    write_atomic(out_dir / 'audit.md', render_markdown(result))
    code = 1 if (result['holes'] if strict else result['worse']) else 0
    return result, code


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--only', default='', help='쉼표로 이은 점검 줄 이름(--list로 본다)')
    parser.add_argument('--list', action='store_true', help='점검 줄 이름을 찍고 끝낸다')
    parser.add_argument('--strict', action='store_true', help='0이 아닌 구멍이 하나라도 있으면 종료 코드 1')
    parser.add_argument('--out', default='', help='출력 폴더(기본 _local/audit/<날짜-시각>/, _local 아래여야 한다)')
    parser.add_argument('--local-dir', default='', help='_local 폴더(기본 저장소의 _local. 스크립트 수·플레이 기록·지난번 기록을 여기서 본다)')
    options = parser.parse_args(argv)
    if options.list:
        for name, title, _ in LINES:
            print('%-14s %s' % (name, title))
        return 0
    only = {w.strip() for w in options.only.split(',') if w.strip()}
    unknown = only - {name for name, _, _ in LINES}
    if unknown:
        raise SystemExit('알 수 없는 점검 줄: %s (있는 것: %s)' % (', '.join(sorted(unknown)), ', '.join(n for n, _, _ in LINES)))
    local = Path(options.local_dir) if options.local_dir else ROOT / '_local'
    out_dir = Path(options.out) if options.out else local / 'audit' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    if '_local' not in out_dir.resolve().parts:
        raise SystemExit('출력은 _local 아래에만 쓴다: ' + str(out_dir))
    result, code = run_audit(ROOT, local, out_dir, only or None, strict=options.strict)
    for line in result['lines']:
        if line['status'] == 'unseen':
            print('%-14s 못 봄 · %s%s' % (line['id'], line.get('reason', ''), ' · 나빠짐' if line.get('worse') else ''))
            continue
        shown = ' / '.join('%s %s' % (m['label'], m['value']) for m in line['metrics'] if m['direction'] != INFO)
        print('%-14s %s%s' % (line['id'], shown, ' · 나빠짐' if line.get('worse') else ''))
    print('AUDIT ' + json.dumps({'worse': result['worse'], 'holes': len(result['holes']), 'unseen': [l['id'] for l in result['lines'] if l['status'] == 'unseen'],
                                 'out': str(out_dir)}, ensure_ascii=False))
    return code


if __name__ == '__main__':
    sys.exit(main())
