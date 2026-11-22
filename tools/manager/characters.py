"""「캐릭터」 화면의 서버 쪽(읽기 전용): 자리표의 주인공 몸, 걸음 계약, 코드 상수, 그림·영상의 자리를 모아 준다.

- 게임 파일은 쓰지 않는다. 읽기만 한다(asset_slots.json, hero.json, combat_core.gd, chapter_world.gd, combat_juice.gd, model.pack-report.json).
- 파일은 /media/<줄>/<키> 로만 준다. 키는 이 모듈이 그 줄에 대해 내놓은 목록(media_registry)의 것만 풀린다(URL에서 경로를 받지 않는다).
- 이동 속도·카메라 같은 코드 상수는 글로 읽는다. 못 읽으면 값을 지어내지 않고 오류 글을 낸다(화면에 「읽지 못함」).
- 계산 식은 tools/art/motion_math.py 의 것을 부른다(같은 식을 여기에 다시 쓰지 않는다).
"""
import json, os, re, struct
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT
import sys
sys.path.insert(0, str(ROOT / 'tools' / 'art'))
import slot_paths  # noqa: E402
import motion_math  # noqa: E402

MEDIA_TYPES = {'.glb': 'model/gltf-binary', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp',
               '.mp4': 'video/mp4', '.json': 'application/json; charset=utf-8'}
CHARACTER_NAMES = {'frost': '냉기 마녀', 'ember': '불꽃 마녀', 'arc': '번개 마녀'}
# 슬롯 키 -> 원화·작업 폴더에서 쓰는 이름(번개 마녀는 슬롯에서 arc, 파일에서 storm)
FILE_KEYS = {'frost': 'frost', 'ember': 'ember', 'arc': 'storm'}
SLOT_RE = re.compile(r'^actor\.hero\.([a-z0-9_]+)\.model$')
CAMERA_SIZE_CANDIDATE = 14.0   # 사용자 결정 대기(OPEN-WORK 9절). 코드에는 없다.
FOOT_NAMES = ('LeftToeBase', 'RightToeBase')


def work_root():
    return Path(os.environ.get('MOIRA_WORK_ROOT') or 'D:/Project/witch-moira-work')


def _read_text(p):
    try:
        return Path(p).read_text(encoding='utf-8')
    except OSError:
        return None


def read_base_speed(root=ROOT):
    rel = 'chapter1/core/combat_core.gd'
    text = _read_text(root / rel)
    if text is None:
        return {'value': None, 'source': rel, 'error': '파일을 읽지 못함'}
    m = re.search(r'^const\s+BASE_SPEED\s*:?=\s*(-?\d+(?:\.\d+)?)\s*$', text, re.M)
    if not m:
        return {'value': None, 'source': rel, 'error': 'BASE_SPEED 상수를 글로 읽지 못함(코드가 바뀌었을 수 있음)'}
    return {'value': float(m.group(1)), 'source': rel, 'line': text[:m.start()].count('\n') + 1}


def read_camera(root=ROOT):
    out = {'offset': None, 'size': None, 'errors': []}
    rel = 'chapter1/view/world/chapter_world.gd'
    text = _read_text(root / rel)
    m = re.search(r'^const\s+CAMERA_OFFSET\s*:?=\s*Vector3\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)', text or '', re.M)
    if m:
        out['offset'] = [float(x) for x in m.groups()]
        out['offset_source'] = rel
    else:
        out['errors'].append('카메라 방향(CAMERA_OFFSET)을 글로 읽지 못함')
    rel = 'chapter1/view/fx/combat_juice.gd'
    text = _read_text(root / rel)
    m = re.search(r'camera\.size\s*=\s*(-?[\d.]+)', text or '')
    if m:
        out['size'] = float(m.group(1))
        out['size_source'] = rel
    else:
        out['errors'].append('카메라 세로 폭(camera.size)을 글로 읽지 못함')
    out['size_candidate'] = CAMERA_SIZE_CANDIDATE
    return out


def glb_info(path):
    """glb 머리의 JSON 칸만 읽어 클립 이름과 발끝 뼈 이름을 낸다(R6 확인용). 못 읽으면 {'error': ...}."""
    try:
        with open(path, 'rb') as f:
            head = f.read(12)
            if head[:4] != b'glTF':
                return {'error': 'glb 머리가 아님'}
            length, ctype = struct.unpack('<II', f.read(8))
            if ctype != 0x4E4F534A:
                return {'error': '첫 칸이 JSON이 아님'}
            doc = json.loads(f.read(length).decode('utf-8'))
    except (OSError, ValueError, struct.error) as e:
        return {'error': '%s' % e}
    nodes = [n.get('name', '') for n in doc.get('nodes', [])]
    toes = [n for n in nodes if 'ToeBase' in n]
    return {'animations': [a.get('name', '') for a in doc.get('animations', [])], 'toe_bones': toes,
            'node_count': len(nodes), 'skins': len(doc.get('skins', []))}


def read_report(glb_path):
    rep = Path(glb_path).with_suffix('.pack-report.json')
    try:
        doc = json.loads(rep.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None
    out = {}
    for name, c in (doc.get('clips') or {}).items():
        out[name] = {'length_s': c.get('length_s'), 'g_toe': c.get('ground_speed_toe_mps'), 'g_hips': c.get('ground_speed_mps'),
                     'hips_span_m': c.get('hips_span_m'), 'fbx': c.get('fbx')}
    return out


def _slot_lines(root=ROOT):
    slots, err = slot_paths.load_slots(root)
    out = {}
    for sid, s in slots.items():
        m = SLOT_RE.match(sid)
        if m:
            out[m.group(1)] = (sid, s)
    return out, err


def line_ids(root=ROOT):
    slots, _ = _slot_lines(root)
    return [k for k in slots]


def list_lines(root=ROOT):
    slots, err = _slot_lines(root)
    rows = []
    for key, (sid, s) in slots.items():
        rel = slot_paths.repo_path(s.get('file'))
        body = (root / rel) if rel else None
        rows.append({'id': key, 'name': CHARACTER_NAMES.get(key, key), 'slot': sid, 'has_body': bool(body and body.is_file()),
                     'planned': bool(s.get('planned'))})
    return {'lines': rows, 'error': err}


def media_registry(line_id, root=ROOT, work=None):
    """{키: {'path': Path, 'kind', 'label'}} 이 줄에 대해 지금 실제로 있는 파일만. 그림·영상 칸의 자리표 구실도 한다."""
    work = work or work_root()
    slots, _ = _slot_lines(root)
    if line_id not in slots:
        return {}
    sid, s = slots[line_id]
    fk = FILE_KEYS.get(line_id, line_id)
    reg = {}

    def add(key, p, kind, label):
        p = Path(p) if p else None
        if p and p.is_file() and p.suffix.lower() in MEDIA_TYPES:
            reg[key] = {'path': p, 'kind': kind, 'label': label}

    rel = slot_paths.repo_path(s.get('file'))
    if rel:
        add('body', root / rel, 'glb', '게임에 들어가는 몸')
        add('body_report', (root / rel).with_suffix('.pack-report.json'), 'json', '몸 보고서')
    add('motions', work / 'pipeline' / line_id / 'motions' / 'motions.glb', 'glb', '동작 후보 묶음')
    add('motions_report', work / 'pipeline' / line_id / 'motions' / 'motions.pack-report.json', 'json', '후보 묶음 보고서')
    add('main', root / 'chapter1' / 'art' / 'characters' / (fk + '_witch_v02.png'), 'image', '메인 이미지(게임에 있는 원화)')
    for view, label in (('front', '앞'), ('back', '뒤'), ('side', '옆')):
        add('apose_' + view, work / 'char3d' / 'gen3d' / fk / (view + '.png'), 'image', 'A자세 ' + label)
    idle = work / 'video' / 'idle'
    if idle.is_dir():
        for i, p in enumerate(sorted(idle.glob(fk + '_idle_*_pingpong.mp4'))[:6]):
            add('idle_video_%d' % (i + 1), p, 'video', '대기 영상 ' + p.stem)
    return reg


def media_path(line_id, key, root=ROOT, work=None):
    ent = media_registry(line_id, root, work).get(key)
    return ent['path'] if ent else None


def detail(line_id, root=ROOT, work=None):
    work = work or work_root()
    slots, err = _slot_lines(root)
    if line_id not in slots:
        return None
    sid, s = slots[line_id]
    reg = media_registry(line_id, root, work)
    contract = s.get('contract') if isinstance(s.get('contract'), dict) else None
    speed = read_base_speed(root)
    camera = read_camera(root)
    warnings = []
    if 'body' not in reg:
        warnings.append('이 줄의 몸 파일이 없습니다(몸 폴더는 저장소에 올라가지 않아 이 작업 폴더에 없을 수 있습니다).')
    if speed['value'] is None:
        warnings.append('이동 속도를 읽지 못함: ' + speed['error'])
    warnings += camera['errors']
    body = {'info': glb_info(reg['body']['path']) if 'body' in reg else None, 'clips': read_report(reg['body']['path']) if 'body' in reg else None}
    motions = None
    if 'motions' in reg:
        motions = {'info': glb_info(reg['motions']['path']), 'clips': read_report(reg['motions']['path'])}
    if body['info'] and not body['info'].get('error') and not body['info']['toe_bones']:
        warnings.append('몸 파일에서 발끝 뼈(ToeBase)를 찾지 못했습니다.')
    meta = None
    meta_rel = slot_paths.repo_path(s.get('meta'))
    if meta_rel and (root / meta_rel).is_file():
        try:
            meta = json.loads((root / meta_rel).read_text(encoding='utf-8'))
        except ValueError:
            warnings.append('hero.json 을 읽지 못함')
    pose = (contract or {}).get('pose') or {}
    run_clip = ((contract or {}).get('clips') or {}).get('run')
    rate_now = None
    if contract and speed['value'] and pose.get('run_time_scale') and pose.get('stride_world_m'):
        rate_now = motion_math.rate_from_contract(speed['value'], pose['run_time_scale'], pose['stride_world_m'])
    all_keys = ['main', 'apose_front', 'apose_back', 'apose_side'] + sorted(k for k in reg if k.startswith('idle_video_'))
    return {
        'id': line_id, 'name': CHARACTER_NAMES.get(line_id, line_id), 'slot': sid,
        'contract': contract, 'run_clip': run_clip, 'rate_now': rate_now,
        'game': {'base_speed': speed, 'camera': camera},
        'body': body, 'motions': motions, 'look': (meta or {}).get('look'),
        'media': {k: {'kind': v['kind'], 'label': v['label'], 'url': '/media/%s/%s' % (line_id, k)} for k, v in reg.items()},
        'missing_media': [k for k in all_keys if k not in reg],
        'stages': [], 'stages_note': '파이프라인 도구가 들어오면 이 칸이 채워집니다.',
        'subject': line_id + '/locomotion',
        'selfcheck': motion_math.selfcheck_cases(), 'ground_err': motion_math.GROUND_ERR,
        'foot_bone_names': list(FOOT_NAMES),
        'warnings': warnings, 'slots_error': err,
    }
