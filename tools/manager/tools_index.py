"""도구 색인: tools/dev, tools/art, tools/manager, chapter1/tests 의 측정·검사 도구를 파일 머리 주석에서 읽어 역할별로 보여 준다.

읽기 전용(파일을 쓰지 않는다. 내보내기 명령만 docs/TOOLS-INDEX.ko.md 를 쓴다). 코드를 실행하지도 불러오지도 않고 글만 읽는다.
한 줄 설명과 예시 명령은 파일 머리 주석(.py 는 모듈 설명, .gd 는 `##` 줄)에서 뽑은 것이고,
역할별 묶음과 「언제 쓰나」는 사람이 tools/manager/tools_index.json 에 적은 것이다. 이 도구가 쓰임새를 잰 것이 아니다.
"""
import ast, json, re, time
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT

INDEX_JSON = Path(__file__).resolve().parent / 'tools_index.json'
EXPORT_DOC = 'docs/TOOLS-INDEX.ko.md'
SCAN = [('tools/dev', '*.py'), ('tools/art', '*.py'), ('tools/manager', '*.py'), ('chapter1/tests', '*.gd')]
SKIP_NAMES = {'__init__.py', 'balance_lab_probe.py'}
CMD_START = re.compile(r'^(python|py|godot)\b')


def _example(line):
    s = line.strip()
    s = re.sub(r'\s{2,}#.*$|\s{3,}\S.*$', '', s)
    if s.startswith('godot'):
        s = 'python tools/dev/godot.py' + s[len('godot'):]
    return s.replace('--path <stage>', '--path .').replace('<stage>', '.')


def parse_py(text):
    try:
        doc = ast.get_docstring(ast.parse(text)) or ''
    except SyntaxError:
        doc = ''
    lines = [l for l in doc.splitlines()]
    first = next((l.strip() for l in lines if l.strip()), '')
    ex = [_example(l) for l in lines if CMD_START.match(l.strip())]
    return first, ex


def parse_gd(text):
    block, started = [], False
    for l in text.splitlines():
        s = l.strip()
        if s.startswith('##'):
            started = True
            block.append(s.lstrip('#').strip())
        elif started and s == '':
            break
        elif started:
            break
    first = next((l for l in block if l), '')
    ex = [_example(l) for l in block if CMD_START.match(l) and ('--script' in l or '.tscn' in l or l.startswith('python'))]
    if not ex:  # `--script res://… 설명` 꼴만 있는 머리 주석
        ex = ['python tools/dev/godot.py --headless --path . ' + _example(l) for l in block if l.startswith('--script')]
    return first, ex


def scan_files():
    found = {}
    tests_unit = 0
    for folder, pat in SCAN:
        d = ROOT / folder
        if not d.is_dir():
            continue
        for p in sorted(d.glob(pat)):
            if p.name in SKIP_NAMES:
                continue
            if p.name.startswith('test_'):
                if p.suffix == '.gd':
                    tests_unit += 1
                continue
            rel = p.relative_to(ROOT).as_posix()
            try:
                text = p.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            first, ex = parse_py(text) if p.suffix == '.py' else parse_gd(text)
            found[rel] = {'path': rel, 'header': first[:240], 'examples': ex[:3], 'kind': 'python' if p.suffix == '.py' else 'godot'}
    return found, tests_unit


def load_map(warnings):
    try:
        return json.loads(INDEX_JSON.read_text(encoding='utf-8'))
    except FileNotFoundError:
        warnings.append('tools_index.json이 없어 역할별 묶음 없이 파일 목록만 보여 줍니다.')
    except (OSError, ValueError) as e:
        warnings.append('tools_index.json을 읽지 못했습니다: %s: %s' % (type(e).__name__, e))
    return {}


def build():
    warnings = []
    files, unit_count = scan_files()
    m = load_map(warnings)
    mapped = set()
    roles = []
    for r in m.get('roles', []):
        tools = []
        for t in r.get('tools', []):
            path = t.get('path', '')
            info = files.get(path)
            if info is None:
                warnings.append('색인에는 있는데 파일이 없습니다: %s (%s)' % (path, r.get('label', r.get('id', ''))))
                tools.append({'path': path, 'use': t.get('use', ''), 'missing': True, 'header': '', 'examples': []})
                continue
            mapped.add(path)
            tools.append({**info, 'use': t.get('use', ''), 'missing': False})
        roles.append({'id': r.get('id', ''), 'label': r.get('label', ''), 'about': r.get('about', ''), 'tools': tools})
    unmapped = [files[p] for p in sorted(files) if p not in mapped]
    return {'basis': '작업 폴더의 현재 파일 머리 주석 + tools_index.json(사람이 묶음)', 'generated_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'reminders': m.get('reminders', []), 'roles': roles, 'unmapped': unmapped, 'tool_count': len(files),
            'unit_tests_note': 'chapter1/tests/test_*.gd %d개는 회귀 검사라 목록에서 뺐습니다. python tools/dev/run_all.py 가 돌립니다.' % unit_count,
            'warnings': warnings,
            'caveat': '설명과 예시 명령은 파일 머리 주석에서 그대로 뽑은 글이고, 역할 묶음은 사람이 적은 것입니다. 이 색인이 도구를 돌려 보거나 쓰임새를 잰 것이 아닙니다.'}


def _md_cell(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def to_markdown(data):
    out = ['# 도구 색인 (TOOLS-INDEX)', '',
           '`python tools/manager/catalog.py --tools-index`가 만든 파일이다. 손으로 고치지 않는다. 역할별 묶음은 `tools/manager/tools_index.json`에서 고친다.', '',
           data['caveat'], '', '생성: %s · 도구 %d개' % (data['generated_at'], data['tool_count']), '']
    if data['reminders']:
        out += ['## 이미 있는데 놓치기 쉬운 것', '']
        out += ['- %s%s' % (r.get('text', ''), (' (`%s`)' % r['path']) if r.get('path') else '') for r in data['reminders']]
        out.append('')
    for r in data['roles']:
        out += ['## %s' % r['label'], '']
        if r['about']:
            out += [r['about'], '']
        out += ['| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |', '|---|---|---|---|']
        for t in r['tools']:
            ex = '<br>'.join('`%s`' % _md_cell(e) for e in t['examples'][:2]) or ('파일 없음' if t['missing'] else '')
            out.append('| `%s` | %s | %s | %s |' % (t['path'], _md_cell(t['use']), _md_cell(t['header']), ex))
        out.append('')
    if data['unmapped']:
        out += ['## 아직 역할에 묶지 않은 도구', '', '| 도구 | 머리 주석 | 예시 명령 |', '|---|---|---|']
        for t in data['unmapped']:
            ex = '<br>'.join('`%s`' % _md_cell(e) for e in t['examples'][:2])
            out.append('| `%s` | %s | %s |' % (t['path'], _md_cell(t['header']), ex))
        out.append('')
    out += [data['unit_tests_note'], '']
    if data['warnings']:
        out += ['## 경고', ''] + ['- %s' % w for w in data['warnings']] + ['']
    return '\n'.join(out)


def export(path=None):
    p = Path(path) if path else ROOT / EXPORT_DOC
    if not p.is_absolute():
        p = ROOT / p
    data = build()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + '.tmp')
    tmp.write_text(to_markdown(data), encoding='utf-8', newline='\n')
    tmp.replace(p)
    return p, data
