"""「스킬 시험실」의 뒷면: 스킬·소리 자리 표를 데이터 파일에서 읽고, Godot 시험 창에 파일 두 개로 명령을 보내고, 소리 후보를 훑고, 채택을 부른다.

명세: docs/specs/T12-skill-lab-20261123.ko.md 2.2·2.4·3.4절. 표준 라이브러리만 쓴다. 게임·Godot를 이 모듈이 직접 실행하지 않는다
(창은 tools/dev/godot.py 를 하위 프로세스로, 채택은 tools/dev/audio_adopt.py 를 하위 프로세스로). 사용자 저장 폴더는 읽지도 쓰지도 않는다.
읽는 것: chapter1/data/{character_progression,growth_quality37,descent,audio_map}.json, chapter1/i18n/ko.po, chapter1/presentation/combat_audio.gd(상수만),
_local/audio/**/lab-candidates.json, _local/skill-lab/state.json. 쓰는 것: _local/skill-lab/{command.json,godot.log,launch.json}, 그리고 채택 때 picks.py 의 고름 기록.
모든 함수는 root(저장소 폴더)를 받아 검사가 임시 폴더로 돈다.
"""
import hashlib, json, os, re, subprocess, sys, threading, time
from pathlib import Path

try:
    from .catalog import ROOT, GROWTH_ROWS, parse_po, gd_const
    from . import picks as picks_mod
except ImportError:
    from catalog import ROOT, GROWTH_ROWS, parse_po, gd_const
    import picks as picks_mod

PROTOCOL = 1
ELEMS = ('ember', 'frost', 'arc')
PRIMARY = {e: 'chapter1.skill.' + e for e in ELEMS}
PORTRAIT_FILE = {'ember': 'ember_witch_v02.png', 'frost': 'frost_witch_v02.png', 'arc': 'storm_witch_v02.png'}
FORMS = ('base', 'evolved', 'descent')
LAYOUTS = ('single', 'pack', 'line', 'elite', 'crowd')
MOTIONS = ('approach', 'hold')
SPEEDS = (0.25, 0.5, 1.0)
HEARTBEAT_OK_MS = 2000
CAND_PREFIXES = ('_local/audio/', 'chapter1/art/')
AUDIO_PREFIXES = ('_local/', 'chapter1/art/')
SLOT_RE = re.compile(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$')
KEY_RE = re.compile(r'^[A-Za-z0-9_.\-]{1,40}$')
SHOT_RE = re.compile(r'^[A-Za-z0-9_\-]{1,40}$')
ADOPT_TIMEOUT = 300
MOMENT_LABEL = {'cast': '시전', 'hit': '명중', 'shatter': '파쇄', 'land': '착지', 'call': '부름', 'sweep': '휩쓸기', 'end': '끝'}

# 경로마다 "원격에서 어디까지"를 한 곳에서 선언한다(명세 9.2·9.6, SL-E 가 이 표를 읽어 막는다. 이번 차수에는 판정하지 않는다).
# 값: 'view'(보기) · 'skill_lab.scene'(장면·소리 끼우기) · 'skill_lab.clip'(영상) · 'skill_lab.adopt'(채택) · LOCAL_ONLY(원격 금지)
LOCAL_ONLY = 'local_only'
ROUTE_POLICY = {
    ('GET', '/api/skill-lab'): 'view',
    ('GET', '/api/skill-lab/audio'): 'view',
    ('GET', '/api/skill-lab/portrait'): 'view',
    ('GET', '/api/skill-lab/shot'): LOCAL_ONLY,        # 창 화면 저장 그림
    ('GET', '/api/skill-lab/clips'): 'view',
    ('GET', '/api/skill-lab/clip/*'): 'view',          # 상태 JSON
    ('GET', '/api/skill-lab/clip/*/video'): 'view',
    ('POST', '/api/skill-lab/open'): LOCAL_ONLY,       # PC 화면에 Godot 창이 뜨게 하므로
    ('POST', '/api/skill-lab/shot'): LOCAL_ONLY,
    ('POST', '/api/skill-lab/scene'): 'skill_lab.scene',
    ('POST', '/api/skill-lab/cast'): 'skill_lab.scene',
    ('POST', '/api/skill-lab/close'): 'skill_lab.scene',
    ('POST', '/api/skill-lab/clip'): 'skill_lab.clip',
    ('POST', '/api/skill-lab/adopt'): 'skill_lab.adopt',
    ('POST', '/api/skill-lab/adopt-preview'): 'skill_lab.adopt',
    ('POST', '/api/skill-lab/revert'): 'skill_lab.adopt',
}


def route_policy(method, path):
    """(method, 경로) -> 정책 값. 모르는 경로는 None(호출한 쪽이 닫힌 쪽으로 처리)."""
    path = path.split('?', 1)[0]
    hit = ROUTE_POLICY.get((method, path))
    if hit:
        return hit
    m = re.fullmatch(r'/api/skill-lab/clip/[0-9a-f]{24}(/video)?', path)
    if m:
        return ROUTE_POLICY.get((method, '/api/skill-lab/clip/*/video' if m.group(1) else '/api/skill-lab/clip/*'))
    return None


class LabError(Exception):
    def __init__(self, status, message, extra=None):
        super().__init__(message)
        self.status, self.extra = status, extra or {}


class BusyError(Exception):
    pass


_CMD_LOCK = threading.Lock()
_ADOPT_LOCK = threading.Lock()
_LAUNCH = {'proc': None, 'at': 0.0}


def lab_dir(root=None):
    return Path(root or ROOT) / '_local' / 'skill-lab'


def _read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def _safe_rel(value, prefixes):
    """저장소 상대 경로 문자열 검사: 역슬래시·드라이브·절대·.. 금지, 허용 머리 아래만."""
    if not isinstance(value, str) or not value or '\\' in value or ':' in value or '\x00' in value or value.startswith('/'):
        return None
    if any(seg in ('', '.', '..') for seg in value.split('/')):
        return None
    return value if value.startswith(prefixes) else None


def _inside(root, rel):
    """rel 을 풀어서 root 안의 파일인지. 아니면 None."""
    base = Path(root).resolve()
    p = (base / rel).resolve()
    return p if p.is_relative_to(base) else None


def file_sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------------ 캐릭터·스킬(데이터에서 매번 읽음)
def _po(root):
    p = Path(root) / 'chapter1' / 'i18n' / 'ko.po'
    if not p.is_file():
        return {}
    return {e['id']: e['strs'].get(0, '') for e in parse_po(p.read_text(encoding='utf-8'))}


def characters_table(root=None, warnings=None):
    """캐릭터 셋과 각자의 스킬(주력·진화·강림 + 회색 '2차'의 고리)."""
    root = Path(root or ROOT)
    warnings = warnings if warnings is not None else []
    try:
        prog = _read_json(root / 'chapter1/data/character_progression.json')
        growth = _read_json(root / 'chapter1/data/growth_quality37.json')
    except (OSError, ValueError) as e:
        warnings.append('캐릭터·스킬 데이터를 읽지 못했습니다: %s' % e.__class__.__name__)
        return []
    try:
        descent = _read_json(root / 'chapter1/data/descent.json')
    except (OSError, ValueError):
        descent = {}
        warnings.append('descent.json 을 읽지 못해 강림의 수치를 보이지 못합니다.')
    po = _po(root)
    skills = {s['id']: s for s in growth.get('skills', [])}
    passives = {p['id']: p for p in growth.get('passives', [])}
    out = []
    for ch in prog.get('characters', []):
        elem = str(ch.get('id', '')).rsplit('.', 1)[-1]
        sid = ch.get('signature_skill_id')
        if elem not in ELEMS or sid not in skills:
            warnings.append('캐릭터 %s 의 주력 스킬을 데이터에서 찾지 못했습니다.' % ch.get('id'))
            continue
        s = skills[sid]
        stages = list(s['ranks']) + [s['evolution']]
        cols = ['단계'] + ['랭크 %d' % (i + 1) for i in range(len(s['ranks']))] + ['진화']
        rows = []
        for key, label, fmt in GROWTH_ROWS:       # catalog.growth_entities 와 같은 행·같은 표기
            vals = [st.get(key, 0) for st in stages]
            if key in ('damage_raw', 'cooldown_ticks') or any(vals):
                rows.append([label] + [fmt(v) for v in vals])
        base_name = po.get('skill.%s.name' % sid) or s.get('name', sid)
        evo_name = po.get('skill.%s.evolved_name' % sid) or s.get('evolution_name', '')
        pas = passives.get(s.get('passive_id'), {})
        base_desc = po.get('skill.%s.desc' % sid, '')          # 글 파일에 스킬 설명 키가 생기면 그것을 먼저 읽는다
        evo_desc = po.get('skill.%s.evolved_desc' % sid, '')
        ult = (descent.get('ultimates') or {}).get(elem, {})
        costs = descent.get('cost')
        forms = [
            {'form': 'base', 'label': '주력', 'name': base_name, 'available': True,
             'text': base_desc or '데이터에는 설명 문장이 없고 랭크별 수치만 있습니다(growth_quality37.json). 짝 패시브: %s' % pas.get('name', '?'),
             'table': {'columns': cols, 'rows': rows}},
            {'form': 'evolved', 'label': '진화', 'name': evo_name, 'available': True,
             'text': evo_desc or '진화 수치는 위 표의 마지막 열입니다.', 'table': {'columns': cols, 'rows': rows}},
            {'form': 'descent', 'label': '강림', 'name': po.get('descent.name.' + elem, ''), 'available': True,
             'text': po.get('descent.desc.' + elem, ''),
             'pairs': [[k, str(v)] for k, v in ult.items()] + ([['비용(데이터 값)', ' / '.join(str(x) for x in costs)]] if isinstance(costs, list) else []),
             'note': '데이터의 enabled 는 %s 입니다. 시험 창은 시험 스위치(--chapter1-trial=descent)로 부릅니다.' % str(descent.get('enabled')).lower() if 'enabled' in descent else ''},
            {'form': 'ring', 'label': '고리(2차)', 'name': po.get('skill.chapter1.skill.%s_ring.name' % elem, ''), 'available': False,
             'text': '2차에 더합니다.'},
        ]
        out.append({'id': ch['id'], 'elem': elem, 'name': po.get('character.%s.name' % elem, elem),
                    'title': po.get('character.%s.class' % elem, ''), 'primary': sid,
                    'portrait': (root / 'chapter1/art/characters' / PORTRAIT_FILE[elem]).is_file(), 'forms': forms})
    out.sort(key=lambda c: ELEMS.index(c['elem']))      # 테사·아일린·베로니카 차례(데이터 파일의 순서와 무관)
    return out


def portrait_path(root, elem):
    if elem not in PORTRAIT_FILE:
        return None
    p = Path(root) / 'chapter1/art/characters' / PORTRAIT_FILE[elem]
    return p if p.is_file() else None


# ------------------------------------------------------------------ 소리 자리 표
def map_info(root):
    """audio_map.json -> {'rev': sha256|None, 'schema': int, 'slots': {}, 'adopted': {}, 'error': str}"""
    p = Path(root) / 'chapter1/data/audio_map.json'
    info = {'rev': None, 'schema': 0, 'slots': {}, 'adopted': {}, 'error': ''}
    if not p.is_file():
        info['error'] = 'audio_map.json 이 없습니다.'
        return info
    raw = p.read_bytes()
    info['rev'] = hashlib.sha256(raw).hexdigest()
    try:
        d = json.loads(raw.decode('utf-8'))
    except ValueError:
        info['error'] = 'audio_map.json 을 읽지 못했습니다.'
        return info
    info['schema'] = d.get('schema_version', 1) if isinstance(d, dict) else 0
    if isinstance(d, dict) and isinstance(d.get('slots'), dict):
        info['slots'] = d['slots']
        info['adopted'] = d.get('adopted') if isinstance(d.get('adopted'), dict) else {}
    return info


def slot_owner(slot):
    """자리 이름 -> (원소, 형태) 또는 None. 자리 이름은 <무리>.<대상>.<순간>."""
    parts = slot.split('.')
    if len(parts) < 3:
        return None
    if parts[0] == 'skill' and parts[1] in ELEMS:
        return parts[1], 'base'
    if parts[0] == 'skill' and parts[1] == 'meteor':
        return 'ember', 'evolved'
    if parts[0] == 'descent' and parts[1] in ELEMS:
        return parts[1], 'descent'
    return None


def _gd_consts(root, warnings):
    p = Path(root) / 'chapter1/presentation/combat_audio.gd'
    out = {'PATH': 'res://chapter1/art/quality03_audio/', 'COUNTS': {}, 'DIRS': {}, 'SILENT': []}
    if not p.is_file():
        warnings.append('combat_audio.gd 가 없어 부모 소리의 파일을 보이지 못합니다.')
        return out
    text = p.read_text(encoding='utf-8', errors='replace')
    for name in out:
        try:
            out[name] = gd_const(text, name)         # `const SILENT: Array[String] = [...]` 꼴도 gd_const 가 읽는다
        except ValueError:
            if name != 'DIRS':
                warnings.append('combat_audio.gd 의 %s 상수를 읽지 못했습니다.' % name)
    return out


def _res_to_rel(res):
    return res[len('res://'):] if isinstance(res, str) and res.startswith('res://') else None


def current_sound(root, slot, info, consts):
    """그 자리에 지금 걸린 소리: 채택 → 부모 소리 → 없음. 관측한 파일만 낸다."""
    root = Path(root)
    ad = info['adopted'].get(slot)
    if isinstance(ad, dict) and ad.get('files'):
        files = [_res_to_rel(f) for f in ad['files']]
        files = [f for f in files if f and _safe_rel(f, ('chapter1/art/',)) and (root / f).is_file()]
        return {'kind': 'adopted', 'cue': '', 'files': files, 'candidate': ad.get('candidate', ''), 'date': ad.get('date', '')}
    parent = (info['slots'].get(slot) or {}).get('parent', '')
    if not parent:
        return {'kind': 'silent', 'cue': '', 'files': [], 'note': '채택 전에는 무음(부모 소리 없음)'}
    base = consts['DIRS'].get(parent, consts['PATH'])
    n = int(consts['COUNTS'].get(parent, 0))
    files = []
    for i in range(n):
        rel = _res_to_rel(base + '%s_%d.wav' % (parent, i))
        if rel and _safe_rel(rel, ('chapter1/art/',)) and (root / rel).is_file():
            files.append(rel)
    silent = parent in (consts['SILENT'] or [])
    note = ('부모 소리 "%s": 코드의 SILENT 때문에 일반 실행에서 무음' % parent) if silent else (
        '부모 소리 "%s"' % parent if files else '부모 소리 "%s": 파일이 없어 무음' % parent)
    return {'kind': 'silent' if (silent or not files) else 'parent', 'cue': parent, 'files': files, 'note': note}


def _num(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float('inf') else None


def mix_info(root, info, warnings):
    """게임이 한 소리에 곱하는 크기: master x mix_gain x GAINS[부모 소리]. 읽는 차례는 mix_gain 이 데이터(audio_map.json) -> 코드 상수 -> 코드의 곱셈 리터럴 -> 0.11."""
    import re
    root = Path(root)
    p = root / 'chapter1/presentation/combat_audio.gd'
    text = p.read_text(encoding='utf-8', errors='replace') if p.is_file() else ''
    out = {'master': 0.8, 'master_source': '못 읽어 기본값', 'mix_gain': 0.11, 'mix_source': '못 읽어 기본값', 'gains': {}, 'slot_default_gain': 1.0, 'silent': []}
    try:
        out['gains'] = {k: float(v) for k, v in (gd_const(text, 'GAINS') or {}).items()}
        out['silent'] = list(gd_const(text, 'SILENT') or [])
    except (ValueError, TypeError):
        warnings.append('combat_audio.gd 의 GAINS·SILENT 를 읽지 못해 게임 안 크기를 낼 수 없습니다.')
    try:
        sd = gd_const(text, 'SLOT_DEFAULT')
        if isinstance(sd, dict) and _num(sd.get('gain')) is not None:
            out['slot_default_gain'] = float(sd['gain'])
    except ValueError:
        pass
    m = re.search(r'^var\s+master_volume\s*(?::\s*float\s*)?:?=\s*([0-9.]+)', text, re.M)
    if m:
        out['master'], out['master_source'] = float(m.group(1)), '코드의 기본값'
    data_mix = None
    try:
        d = json.loads((root / 'chapter1/data/audio_map.json').read_text(encoding='utf-8'))
        data_mix = _num(d.get('mix_gain')) if isinstance(d, dict) else None
    except (OSError, ValueError):
        pass
    code_mix = None
    try:
        code_mix = _num(gd_const(text, 'MIX_GAIN_DEFAULT'))
    except ValueError:
        pass
    if code_mix is None:
        m = re.search(r'master_volume\s*\*\s*(\.?[0-9]*\.[0-9]+)\s*\*', text)
        code_mix = float(m.group(1)) if m else None
    if data_mix is not None and data_mix > 0:
        out['mix_gain'], out['mix_source'] = data_mix, '소리 표(audio_map.json)의 mix_gain'
    elif code_mix is not None and code_mix > 0:
        out['mix_gain'], out['mix_source'] = code_mix, '코드(combat_audio.gd)의 값'
    else:
        warnings.append('게임의 믹스 값을 못 읽어 0.11 로 가정합니다.')
    return out


def game_gain(mix, parent, slot):
    """그 자리의 소리가 게임에서 원본에 곱해지는 값(선형). 부모 소리가 없으면 자리 기본값."""
    g = mix['gains'].get(parent) if parent else None
    if g is None:
        g = mix['slot_default_gain']
    return mix['master'] * mix['mix_gain'] * g


def _db(x):
    import math
    return round(20 * math.log10(x), 1) if x > 0 else None


def slots_table(root, warnings):
    info = map_info(root)
    if info['error']:
        warnings.append(info['error'])
    consts = _gd_consts(root, warnings)
    mix = mix_info(root, info, warnings)
    rows = []
    for slot, spec in info['slots'].items():
        own = slot_owner(slot)
        moment = slot.split('.')[-1]
        parent = (spec or {}).get('parent', '')
        gg = game_gain(mix, parent, slot)
        rows.append({'slot': slot, 'label': MOMENT_LABEL.get(moment, moment), 'parent': parent,
                     'per_targets': (spec or {}).get('per_targets'), 'owner': {'elem': own[0], 'form': own[1]} if own else None,
                     'current': current_sound(root, slot, info, consts), 'game_gain': round(gg, 6), 'game_db': _db(gg)})
    og = game_gain(mix, '', '')
    return {'rev': info['rev'], 'schema': info['schema'], 'rows': rows,
            'mix': {'master': mix['master'], 'mix_gain': mix['mix_gain'], 'mix_source': mix['mix_source'], 'master_source': mix['master_source'],
                    'default_gain': round(og, 6), 'default_db': _db(og), 'silent_parents': mix['silent']},
            'note': '' if info['slots'] else '이 소리 표(audio_map.json)는 스키마 %s 라 소리 자리가 없습니다. 소리 자리가 들어오면 여기에 나옵니다.' % (info['schema'] or '?')}


# ------------------------------------------------------------------ 후보 목록
def scan_candidates(root=None, warnings=None):
    """_local/audio/**/lab-candidates.json (명세 3.4). 목록 안의 경로는 목록 파일 기준 상대이거나 저장소의 chapter1/art/ 경로.
    파일은 _local/audio/ 또는 chapter1/art/ 아래의 .wav 만. 어긋난 후보는 경고와 함께 뺀다."""
    root = Path(root or ROOT)
    warnings = warnings if warnings is not None else []
    base = root / '_local' / 'audio'
    found, seen = [], set()
    if not base.is_dir():
        return found
    lists = []
    for dirpath, dirnames, filenames in os.walk(base):
        depth = len(Path(dirpath).relative_to(base).parts)
        if depth >= 6:
            dirnames[:] = []
        if 'lab-candidates.json' in filenames:
            lists.append(Path(dirpath) / 'lab-candidates.json')
    for lf in sorted(lists):
        folder_rel = lf.parent.relative_to(base).as_posix()
        try:
            doc = _read_json(lf)
        except (OSError, ValueError):
            warnings.append('후보 목록을 읽지 못했습니다: %s' % folder_rel)
            continue
        if not isinstance(doc, dict) or doc.get('schema') != 1 or not isinstance(doc.get('candidates'), list):
            warnings.append('후보 목록의 꼴이 다릅니다(schema 1 아님): %s' % folder_rel)
            continue
        for c in doc['candidates']:
            key = c.get('key') if isinstance(c, dict) else None
            slot = c.get('slot') if isinstance(c, dict) else None
            if not isinstance(key, str) or not KEY_RE.match(key) or not isinstance(slot, str) or (slot != '' and not SLOT_RE.match(slot)) or not isinstance(c.get('files'), list) or not c['files']:
                warnings.append('%s: 후보 하나의 꼴이 다릅니다.' % folder_rel)
                continue
            cid = '%s/%s' % (folder_rel, key) if folder_rel != '.' else key
            if cid in seen:
                warnings.append('후보 id 가 겹칩니다: %s' % cid)
                continue
            paths, bad = [], False
            for f in c['files']:
                if isinstance(f, str) and f.startswith('chapter1/art/'):
                    rel = _safe_rel(f, ('chapter1/art/',))
                else:
                    try:
                        rel = _safe_rel((lf.parent.relative_to(root) / f).as_posix() if isinstance(f, str) and _safe_rel(f, ('',)) else None, CAND_PREFIXES)
                    except ValueError:
                        rel = None
                if rel is None or not rel.lower().endswith('.wav') or _inside(root, rel) is None:
                    bad = True
                    break
                paths.append(rel)
            if bad:
                warnings.append('후보 %s 의 파일 경로가 허용 범위 밖이거나 wav 가 아니라 뺐습니다.' % cid)
                continue
            missing = [p for p in paths if not (root / p).is_file()]
            seen.add(cid)
            ledger = c.get('ledger') if isinstance(c.get('ledger'), list) else []
            found.append({'id': cid, 'key': key, 'label': str(c.get('label', '')), 'slot': slot, 'title': str(doc.get('title', folder_rel)),
                          'delivered': str(doc.get('delivered', '')), 'by': str(doc.get('by', '')), 'listen_only': slot == '', 'paths': paths, 'missing': missing,
                          'origin_known': bool(ledger) and all(isinstance(x, dict) and x.get('source') for x in ledger)})
    return found


def find_candidate(root, cand_id):
    for c in scan_candidates(root):
        if c['id'] == cand_id:
            return c
    return None


def audio_file(root, id_=None, slot=None, n=0):
    """후보 id(또는 자리의 지금 소리)와 번호로만 파일을 찾는다. 경로를 받지 않는다."""
    root = Path(root)
    try:
        n = int(n)
    except (TypeError, ValueError):
        return None
    if id_:
        c = find_candidate(root, id_)
        paths = c['paths'] if c else []
    elif slot:
        w = []
        info = map_info(root)
        if slot not in info['slots']:
            return None
        paths = current_sound(root, slot, info, _gd_consts(root, w))['files']
    else:
        return None
    if not 0 <= n < len(paths):
        return None
    p = _inside(root, paths[n])
    return p if p and p.is_file() else None


# ------------------------------------------------------------------ 시험 창
def _pid_alive(pid):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if os.name == 'nt':        # Windows 의 os.kill(pid, 0) 은 프로세스를 끝내 버리므로 쓰지 않는다
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x1000, False, pid)     # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = ctypes.c_ulong()
        ok = k.GetExitCodeProcess(h, ctypes.byref(code))
        k.CloseHandle(h)
        return bool(ok) and code.value == 259     # STILL_ACTIVE
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_state(root):
    p = lab_dir(root) / 'state.json'
    if not p.is_file():
        return None, ''
    try:
        d = _read_json(p)
    except (OSError, ValueError):
        return None, 'unreadable'          # 쓰는 도중일 수 있다. 다음 차례에 다시 읽는다
    return (d if isinstance(d, dict) else None), ''


def window_status(root=None, now_ms=None, pid_alive=None):
    root = Path(root or ROOT)
    pid_alive = pid_alive or _pid_alive
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    script = (root / 'chapter1/tests/skill_lab.gd').is_file()
    state, err = read_state(root)
    age = None
    status = 'none'
    if state and isinstance(state.get('heartbeat_unix_ms'), (int, float)):
        age = max(0, now_ms - int(state['heartbeat_unix_ms']))
        if age <= HEARTBEAT_OK_MS and pid_alive(state.get('pid')):
            status = 'connected'
        else:
            status = 'lost'
    proc = _LAUNCH.get('proc')
    if status != 'connected' and proc is not None and proc.poll() is None and time.time() - _LAUNCH['at'] < 120:
        status = 'starting'
    ov = {}
    if status == 'connected' and state:
        ov = ((state.get('audio') or {}).get('overrides')) or {}
    cands = None
    return {'status': status, 'script_exists': script, 'heartbeat_age_ms': age, 'read_error': err, 'state': state if status in ('connected', 'lost') else (state if state else None),
            'overrides': ov, 'cands': cands}


def _next_seq(root):
    ld = lab_dir(root)
    seq = 0
    for name, key in (('command.json', 'seq'), ('state.json', 'applied_seq')):
        try:
            v = _read_json(ld / name).get(key, 0)
            if type(v) is int:
                seq = max(seq, v)
        except (OSError, ValueError, AttributeError):
            pass
    return seq + 1


def write_command(root, command):
    """command.json 을 임시 파일 + 이름 바꾸기로 쓴다. seq 는 여기서 붙인다."""
    ld = lab_dir(root)
    with _CMD_LOCK:
        ld.mkdir(parents=True, exist_ok=True)
        cmd = dict({'protocol': PROTOCOL, 'seq': _next_seq(root)}, **command)
        tmp = ld / 'command.json.tmp'
        with tmp.open('w', encoding='utf-8', newline='\n') as f:
            json.dump(cmd, f, ensure_ascii=False, indent=2)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, ld / 'command.json')
        return cmd


def clean_scene(raw, chars):
    """페이지가 보낸 scene 을 명세 2.2의 꼴로 검사해 모든 칸을 채운다. 어긋나면 ValueError."""
    if not isinstance(raw, dict):
        raise ValueError('scene must be an object')
    allowed = {'character', 'skill', 'form', 'layout', 'count', 'motion', 'durable', 'repeat', 'interval_s', 'speed', 'juice'}
    if set(raw) - allowed:
        raise ValueError('Unknown scene field')
    by_id = {c['id']: c for c in chars}
    cid = raw.get('character')
    if cid not in by_id:
        raise ValueError('Unknown character')
    skill = raw.get('skill', by_id[cid]['primary'])
    if skill != by_id[cid]['primary']:
        raise ValueError('Skill does not belong to the character')
    form = raw.get('form', 'base')
    layout = raw.get('layout', 'single')
    motion = raw.get('motion', 'approach')
    if form not in FORMS or layout not in LAYOUTS or motion not in MOTIONS:
        raise ValueError('Invalid form, layout or motion')
    count = raw.get('count', 8)
    if type(count) is not int or not 1 <= count <= 40:
        raise ValueError('count must be 1..40')
    interval = raw.get('interval_s', 3.0)
    if type(interval) not in (int, float) or not 1.5 <= interval <= 6.0:
        raise ValueError('interval_s must be 1.5..6')
    speed = raw.get('speed', 1.0)
    if type(speed) not in (int, float) or float(speed) not in SPEEDS:
        raise ValueError('speed must be 0.25, 0.5 or 1')
    flags = {}
    for k, d in (('durable', False), ('repeat', True), ('juice', True)):
        v = raw.get(k, d)
        if type(v) is not bool:
            raise ValueError('%s must be boolean' % k)
        flags[k] = v
    return {'character': cid, 'skill': skill, 'form': form, 'layout': layout, 'count': count, 'motion': motion,
            'durable': flags['durable'], 'repeat': flags['repeat'], 'interval_s': float(interval), 'speed': float(speed), 'juice': flags['juice']}


def clean_audio(raw, root):
    """audio: {자리: 후보 id | 저장소 상대 경로 목록 | None}. 반환: {자리: [저장소 상대 경로]} (빈 자리는 뺀다)."""
    if raw in (None, {}):
        return {}
    if not isinstance(raw, dict) or len(raw) > 40:
        raise ValueError('audio must be an object')
    info = map_info(root)
    if not info['slots']:
        raise ValueError('No sound slots in audio_map.json')
    out = {}
    for slot, val in raw.items():
        if not isinstance(slot, str) or not SLOT_RE.match(slot) or slot not in info['slots']:
            raise ValueError('Unknown sound slot')
        if val in (None, '', []):
            continue
        if isinstance(val, str):
            c = find_candidate(root, val)
            if c is None:
                raise ValueError('Unknown candidate')
            if c['slot'] != slot:
                raise ValueError('Candidate belongs to another slot')
            if c['missing']:
                raise ValueError('Candidate files are missing')
            out[slot] = list(c['paths'])
        elif isinstance(val, list) and 0 < len(val) <= 8:
            paths = []
            for p in val:
                rel = _safe_rel(p, AUDIO_PREFIXES)
                if rel is None or not rel.lower().endswith('.wav') or _inside(root, rel) is None:
                    raise ValueError('Path not allowed')
                paths.append(rel)
            out[slot] = paths
        else:
            raise ValueError('Invalid audio value')
    return out


def send_scene(root, scene, audio=None):
    root = Path(root)
    chars = characters_table(root)
    cmd = write_command(root, {'op': 'scene', 'scene': clean_scene(scene, chars), 'audio': clean_audio(audio, root)})
    return {'seq': cmd['seq'], 'command': cmd}


def send_simple(root, op, **extra):
    if op not in ('cast', 'reload_audio', 'quit', 'shot'):
        raise ValueError('Unknown op')
    cmd = write_command(root, dict({'op': op}, **extra))
    return {'seq': cmd['seq'], 'command': cmd}


def request_shot(root, name):
    if not isinstance(name, str) or not SHOT_RE.match(name):
        raise ValueError('Invalid shot name')
    rel = '_local/skill-lab/shots/%s.png' % name
    (lab_dir(root) / 'shots').mkdir(parents=True, exist_ok=True)
    r = send_simple(root, 'shot', shot=rel)
    r['path'] = rel
    return r


def shot_file(root, name):
    if not isinstance(name, str) or not SHOT_RE.match(name):
        return None
    p = lab_dir(root) / 'shots' / (name + '.png')
    return p if p.is_file() else None


def build_launch_args(root, primary, lab_rel='_local/skill-lab', hero_models=False):
    """명세 2.5의 명령. 셸 없음."""
    args = [sys.executable, str(Path(root) / 'tools/dev/godot.py'), '--timeout-s=14400', '--resolution', '1600x900', '--path', '.',
            '--script', 'res://chapter1/tests/skill_lab.gd', '--', '--chapter1-start', '--chapter1-profile-off', '--chapter1-qa-ignore-focus',
            '--chapter1-trial=descent', '--chapter1-descent-cost=1000', '--chapter1-seed=11', '--chapter1-primary=' + primary, '--lab-dir=' + lab_rel]
    if hero_models:
        args.append('--chapter1-hero-models')
    return args


def open_window(root, scene, audio=None, hero_models=False, popen=None, pid_alive=None, now_ms=None, wait=None):
    """창이 살아 있으면 scene 명령만, 아니면 scene 을 command.json 에 먼저 쓰고 창을 띄운다."""
    root = Path(root)
    popen = popen or subprocess.Popen
    chars = characters_table(root)
    scene = clean_scene(scene, chars)
    audio_clean = clean_audio(audio, root)
    if not (root / 'chapter1/tests/skill_lab.gd').is_file():
        raise LabError(404, 'Test window script chapter1/tests/skill_lab.gd does not exist yet')
    ws = window_status(root, now_ms, pid_alive)
    ld = lab_dir(root)
    ld.mkdir(parents=True, exist_ok=True)
    launch_file = ld / 'launch.json'
    launched_models = None
    try:
        launched_models = bool(_read_json(launch_file).get('hero_models'))
    except (OSError, ValueError, AttributeError):
        pass
    if ws['status'] == 'connected' and launched_models is not None and launched_models != bool(hero_models):
        write_command(root, {'op': 'quit'})     # 3D 모델 켜기를 바꾸면 창을 다시 띄운다
        for _ in range(int((wait if wait is not None else 8) * 10)):
            time.sleep(0.1)
            if window_status(root, None, pid_alive)['status'] != 'connected':
                break
        else:
            raise LabError(409, 'The old window did not close in time')
        ws = {'status': 'none'}
    if ws['status'] in ('connected', 'starting'):
        r = send_scene(root, scene, audio_clean)
        r['launched'] = False
        return r
    cmd = write_command(root, {'op': 'scene', 'scene': scene, 'audio': audio_clean})
    log = (ld / 'godot.log').open('ab')
    try:
        proc = popen(build_launch_args(root, scene['skill'], hero_models=hero_models), cwd=str(root), stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, shell=False)
    finally:
        log.close()
    _LAUNCH['proc'], _LAUNCH['at'] = proc, time.time()
    launch_file.write_text(json.dumps({'hero_models': bool(hero_models), 'at': time.strftime('%Y-%m-%d %H:%M:%S')}), encoding='utf-8')
    return {'seq': cmd['seq'], 'command': cmd, 'launched': True}


# ------------------------------------------------------------------ 채택·되돌림
def _run_tool(root, args, runner):
    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    try:
        return runner([sys.executable, str(Path(root) / 'tools/dev/audio_adopt.py')] + args, cwd=str(root), capture_output=True, timeout=ADOPT_TIMEOUT, env=env)
    except subprocess.TimeoutExpired:
        raise LabError(504, 'The adopt tool exceeded %d seconds' % ADOPT_TIMEOUT)
    except OSError as e:
        raise LabError(500, 'Could not run the adopt tool: %s' % e.__class__.__name__)


def adopt_available(root):
    root = Path(root)
    if not (root / 'tools/dev/audio_adopt.py').is_file():
        return False, '채택 도구(tools/dev/audio_adopt.py)가 아직 없습니다.'
    if not map_info(root)['slots']:
        return False, '소리 표에 자리가 없습니다(audio_map.json 스키마 2가 아님).'
    return True, ''


def _parse_tool(done):
    out = done.stdout.decode('utf-8', 'replace')
    for line in reversed(out.splitlines()):
        if line.startswith('AUDIO_ADOPT '):
            try:
                return json.loads(line[len('AUDIO_ADOPT '):]), out
            except ValueError:
                break
    return None, out


def _diff_stat(root, runner):
    try:
        d = runner(['git', 'diff', '--stat', '--', 'chapter1/data/audio_map.json', 'chapter1/art/audio'], cwd=str(root), capture_output=True, timeout=30)
        return d.stdout.decode('utf-8', 'replace').strip()
    except (OSError, subprocess.SubprocessError):
        return '(git diff --stat 을 얻지 못했습니다)'


def _skill_of_slot(slot):
    own = slot_owner(slot)
    return PRIMARY[own[0]] if own else 'unknown'


def _record_pick(root, slot, verdict, note, picks_path, by='user'):
    """picks.py 에 한 줄. 실패해도 채택 자체는 이미 끝났으므로 문자열로 알린다. by: 로컬 user, 원격 user(remote:<이메일>)."""
    subject = 'skill/%s/sound/%s' % (_skill_of_slot(slot), slot)
    for _ in range(2):
        try:
            store = picks_mod.load(picks_path)
            status, v = picks_mod.update({'revision': store['revision'], 'action': 'add',
                                          'record': {'screen': 'skill', 'subject': subject, 'verdict': verdict, 'note': note, 'values': {'slot': slot}, 'proposals': []}}, picks_path, by=by)
            if status == 200:
                return ''
        except (ValueError, OSError) as e:
            return '고름 기록을 쓰지 못했습니다: %s' % e.__class__.__name__
    return '고름 기록의 revision 이 계속 어긋났습니다.'


def _after_tool(root, slot, op, verdict, note, done, runner, picks_path, window_alive, by='user'):
    result, out = _parse_tool(done)
    if done.returncode == 3:
        raise LabError(409, 'audio_map.json changed since you loaded this page', {'map_rev': map_info(root)['rev']})
    if done.returncode != 0:
        raise LabError(422, 'The %s tool failed (exit %d)' % (op, done.returncode),
                       {'output': (out + done.stderr.decode('utf-8', 'replace'))[-1500:]})
    pick_warning = _record_pick(root, slot, verdict, note, picks_path, by)
    reloaded = False
    if window_alive():
        send_simple(root, 'reload_audio')
        reloaded = True
    return {'result': result, 'output_tail': out[-800:], 'git_diff_stat': _diff_stat(root, runner), 'pick_warning': pick_warning,
            'reload_sent': reloaded, 'map_rev': map_info(root)['rev']}


def adopt_preview(root, slot, candidate, runner=None):
    """채택 확인 창에 보일 글: 도구의 `adopt --dry-run` 이 낸 confirm·warnings·files 를 그대로 전한다(아무것도 쓰지 않는다)."""
    root = Path(root)
    runner = runner or subprocess.run
    ok, why = adopt_available(root)
    if not ok:
        raise LabError(503, why)
    info = map_info(root)
    if slot not in info['slots']:
        raise LabError(400, 'Unknown sound slot')
    c = find_candidate(root, candidate) if isinstance(candidate, str) else None
    if c is None or c['slot'] != slot or c['missing']:
        raise LabError(400, 'Unknown candidate for this slot')
    done = _run_tool(root, ['adopt', '--slot', slot, '--candidate', candidate, '--dry-run'], runner)
    result, out = _parse_tool(done)
    if done.returncode != 0 or not isinstance(result, dict):
        raise LabError(422, 'The adopt tool refused the preview (exit %d)' % done.returncode, {'output': out[-1500:]})
    return {'confirm': result.get('confirm', ''), 'warnings': result.get('warnings') or [], 'files': result.get('files') or [],
            'parent': result.get('parent', ''), 'parent_silent_today': bool(result.get('parent_silent_today')), 'map_rev': info['rev']}


def adopt(root, slot, candidate, map_rev, runner=None, picks_path=None, pid_alive=None, by='user'):
    root = Path(root)
    runner = runner or subprocess.run
    ok, why = adopt_available(root)
    if not ok:
        raise LabError(503, why)
    info = map_info(root)
    if slot not in info['slots']:
        raise LabError(400, 'Unknown sound slot')
    c = find_candidate(root, candidate) if isinstance(candidate, str) else None
    if c is None or c['slot'] != slot or c['missing']:
        raise LabError(400, 'Unknown candidate for this slot')
    if not isinstance(map_rev, str) or map_rev != info['rev']:
        raise LabError(409, 'audio_map.json changed since you loaded this page', {'map_rev': info['rev']})
    if not _ADOPT_LOCK.acquire(blocking=False):
        raise BusyError('채택이 이미 돌고 있습니다.')
    try:
        # --yes 가 없으면 도구는 아무것도 쓰지 않고 종료 코드 6 으로 끝난다. 화면의 확인 창(adopt_preview 의 글)을 사용자가 누른 뒤에만 여기에 온다.
        done = _run_tool(root, ['adopt', '--slot', slot, '--candidate', candidate, '--expect-rev', map_rev, '--yes'], runner)
        return _after_tool(root, slot, 'adopt', 'pick', '시험실에서 채택: %s' % candidate, done, runner, picks_path,
                           lambda: window_status(root, None, pid_alive)['status'] == 'connected', by)
    finally:
        _ADOPT_LOCK.release()


def revert(root, slot, map_rev, runner=None, picks_path=None, pid_alive=None, by='user'):
    root = Path(root)
    runner = runner or subprocess.run
    ok, why = adopt_available(root)
    if not ok:
        raise LabError(503, why)
    info = map_info(root)
    if slot not in info['slots']:
        raise LabError(400, 'Unknown sound slot')
    if not isinstance(map_rev, str) or map_rev != info['rev']:
        raise LabError(409, 'audio_map.json changed since you loaded this page', {'map_rev': info['rev']})
    if not _ADOPT_LOCK.acquire(blocking=False):
        raise BusyError('채택이 이미 돌고 있습니다.')
    try:
        done = _run_tool(root, ['revert', '--slot', slot, '--expect-rev', map_rev], runner)
        return _after_tool(root, slot, 'revert', 'hold', '시험실에서 채택 취소', done, runner, picks_path,
                           lambda: window_status(root, None, pid_alive)['status'] == 'connected', by)
    finally:
        _ADOPT_LOCK.release()


# ------------------------------------------------------------------ 화면이 받는 전체 값
def overview(root=None, now_ms=None, pid_alive=None):
    root = Path(root or ROOT)
    warnings = []
    chars = characters_table(root, warnings)
    slots = slots_table(root, warnings)
    cands = scan_candidates(root, warnings)
    win = window_status(root, now_ms, pid_alive)
    ok, why = adopt_available(root)
    by_paths = {}
    for c in cands:
        by_paths[tuple(c['paths'])] = c['id']
    overrides = {slot: by_paths.get(tuple(files), '(후보 목록에 없는 파일)') for slot, files in (win.get('overrides') or {}).items()}
    win.pop('cands', None)
    win['override_ids'] = overrides
    return {'characters': chars, 'slots': slots, 'candidates': [{k: v for k, v in c.items()} for c in cands], 'window': win,
            'adopt': {'available': ok, 'reason': why}, 'map_rev': slots['rev'], 'warnings': warnings,
            'stage_note': '시험 창의 무대에서는 판의 다른 일(자연 생성, 구역 이동, 봉인, 레벨업 창 등)이 꺼져 있습니다. 시험 창이 그린 것이 게임 코드가 그린 것입니다.'}
