"""「캐릭터」 화면의 서버 쪽(읽기 전용): 자리표의 주인공 몸, 걸음 계약, 코드 상수, 그림·영상의 자리를 모아 준다.

- 게임 파일은 쓰지 않는다. 읽기만 한다(asset_slots.json, hero.json, combat_core.gd, chapter_world.gd, combat_juice.gd, model.pack-report.json).
- 파일은 /media/<줄>/<키> 로만 준다. 키는 이 모듈이 그 줄에 대해 내놓은 목록(media_registry)의 것만 풀린다(URL에서 경로를 받지 않는다).
- 이동 속도·카메라 같은 코드 상수는 글로 읽는다. 못 읽으면 값을 지어내지 않고 오류 글을 낸다(화면에 「읽지 못함」).
- 계산 식은 tools/art/motion_math.py 의 것을 부른다(같은 식을 여기에 다시 쓰지 않는다).
"""
import json, os, re, struct, time
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
    ins, outs = tripo_files(line_id, root, work)
    for i, (name, p) in enumerate(ins):
        add(tripo_key('tripo_in', i), p, 'image', '보낼 그림 ' + name)
    for i, (name, p) in enumerate(outs):
        add(tripo_key('tripo_out', i), p, 'glb', '받은 모델 ' + name)
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


# ---------------------------------------------------------------- 3D 만들기(수동): 보낼 그림과 받은 모델
# 작업 뿌리의 pipeline/<id>/tripo_in (보낼 그림) 과 tripo_out (받은 모델). 경로는 (줄 id, 고정 낱말)로만 만든다. URL에서 경로를 받지 않는다.
TRIPO_FOLDERS = ('tripo_in', 'tripo_out')
GLB_LIMIT = 300 * 1024 * 1024
MAX_TRIPO_FILES = 24
NAME_KEEP = re.compile(r'[^A-Za-z0-9_-]')


def tripo_dir(line_id, which, root=ROOT, work=None):
    """폴더 경로(있든 없든). 줄 id 가 목록에 없거나 which 가 고정 낱말이 아니면 None."""
    if which not in TRIPO_FOLDERS:
        return None
    slots, _ = _slot_lines(root)
    if line_id not in slots:
        return None
    return (work or work_root()) / 'pipeline' / line_id / which


def safe_name(name):
    """올린 파일 이름 -> 영숫자·-·_ 만 남기고 나머지는 _ (확장자 뺌, 60자, 비면 model)."""
    stem = str(name or '').replace('\\', '/').split('/')[-1]
    if stem.lower().endswith('.glb'):
        stem = stem[:-4]
    stem = NAME_KEEP.sub('_', stem)[:60]
    return stem or 'model'


def png_size(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(24)
        if head[:8] == b'\x89PNG\r\n\x1a\n' and head[12:16] == b'IHDR':
            return struct.unpack('>II', head[16:24])
    except OSError:
        pass
    return None


def glb_facts(path):
    """glb 머리의 JSON 칸에서 삼각형 수·질감·뼈대 유무. 읽지 못한 것은 None."""
    try:
        with open(path, 'rb') as f:
            if f.read(4) != b'glTF':
                return {'error': 'glb 머리가 아님'}
            f.read(8)
            length, ctype = struct.unpack('<II', f.read(8))
            if ctype != 0x4E4F534A or length > 64 * 1024 * 1024:
                return {'error': '머리 JSON 칸을 읽지 못함'}
            doc = json.loads(f.read(length).decode('utf-8'))
    except (OSError, ValueError, struct.error) as e:
        return {'error': str(e)}
    tris, ok = 0, True
    accessors = doc.get('accessors', [])
    for mesh in doc.get('meshes', []):
        for prim in mesh.get('primitives', []):
            if prim.get('mode', 4) != 4:
                ok = False
                continue
            try:
                idx = prim.get('indices')
                n = accessors[idx]['count'] if idx is not None else accessors[prim['attributes']['POSITION']]['count']
                tris += n // 3
            except (KeyError, IndexError, TypeError):
                ok = False
    return {'triangles': tris if ok else None, 'has_texture': bool(doc.get('images') or doc.get('textures')),
            'has_skin': bool(doc.get('skins')), 'animations': len(doc.get('animations', []))}


def tripo_files(line_id, root=ROOT, work=None):
    """(보낼 그림 [(이름, 경로)], 받은 모델 [(이름, 경로)]), 이름순."""
    out = []
    for which, suffix in (('tripo_in', '.png'), ('tripo_out', '.glb')):
        d = tripo_dir(line_id, which, root, work)
        files = []
        if d is not None and d.is_dir():
            files = sorted((p for p in d.iterdir() if p.is_file() and p.suffix.lower() == suffix), key=lambda p: p.name)[:MAX_TRIPO_FILES]
        out.append([(p.name, p) for p in files])
    return out[0], out[1]


def tripo_key(which, i):
    return ('tin_%d' if which == 'tripo_in' else 'tout_%d') % i


def tripo_info(line_id, root=ROOT, work=None):
    work = work or work_root()
    din = tripo_dir(line_id, 'tripo_in', root, work)
    if din is None:
        return None
    dout = tripo_dir(line_id, 'tripo_out', root, work)
    ins, outs = tripo_files(line_id, root, work)
    fwd = lambda p: str(p).replace('\\', '/')
    rows_in = []
    for i, (name, p) in enumerate(ins):
        size = png_size(p)
        key = tripo_key('tripo_in', i)
        rows_in.append({'name': name, 'key': key, 'url': '/media/%s/%s' % (line_id, key),
                        'width': size[0] if size else None, 'height': size[1] if size else None, 'bytes': p.stat().st_size, 'path': fwd(p)})
    rows_out = []
    for i, (name, p) in enumerate(outs):
        st = p.stat()
        key = tripo_key('tripo_out', i)
        row = {'name': name, 'key': key, 'url': '/media/%s/%s' % (line_id, key), 'bytes': st.st_size,
               'received': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(st.st_mtime)), 'path': fwd(p)}
        row.update(glb_facts(p))
        rows_out.append(row)
    return {'work_root': fwd(work), 'work_found': work.is_dir(), 'in_path': fwd(din), 'out_path': fwd(dout),
            'in_exists': din.is_dir(), 'out_exists': dout.is_dir(), 'inputs': rows_in, 'outputs': rows_out, 'limit_bytes': GLB_LIMIT,
            'split_cmd': 'python tools/art/sheet_split.py <시트.png> --out %s --names front,left,back --square' % fwd(din),
            'rule': '작업 뿌리는 환경 변수 MOIRA_WORK_ROOT, 없으면 D:/Project/witch-moira-work. 그 아래 pipeline/<캐릭터>/tripo_in(보낼 그림)·tripo_out(받은 모델).'}


class UploadError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def receive_glb(line_id, filename, stream, length, root=ROOT, work=None, limit=None):
    """받은 glb 를 tripo_out 에 저장한다. 덮어쓰지 않고, 임시 파일에 쓴 뒤 이름을 붙인다. 저장된 파일 이름을 돌려준다."""
    limit = GLB_LIMIT if limit is None else limit
    work = work or work_root()
    d = tripo_dir(line_id, 'tripo_out', root, work)
    if d is None:
        raise UploadError(404, '알 수 없는 캐릭터 줄')
    if not isinstance(filename, str) or not filename.lower().endswith('.glb'):
        raise UploadError(400, '.glb 파일만 받습니다')
    if not isinstance(length, int) or length <= 0:
        raise UploadError(411, '파일 크기를 알 수 없습니다')
    if length > limit:
        raise UploadError(413, '파일이 너무 큽니다(상한 %d MB)' % (limit // (1024 * 1024)))
    if not work.is_dir():
        raise UploadError(404, '작업 폴더를 찾지 못함')
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / ('.incoming-%d-%d.tmp' % (os.getpid(), time.time_ns()))
    left, first = length, True
    try:
        with tmp.open('wb') as f:
            while left > 0:
                chunk = stream.read(min(1024 * 1024, left))
                if not chunk:
                    raise UploadError(400, '파일이 중간에 끊겼습니다')
                if first:
                    if chunk[:4] != b'glTF':
                        raise UploadError(400, 'glb 파일이 아닙니다(머리 4글자가 glTF가 아님)')
                    first = False
                f.write(chunk)
                left -= len(chunk)
            f.flush()
            os.fsync(f.fileno())
        base = time.strftime('%Y%m%d-%H%M%S') + '_' + safe_name(filename)
        n = 1
        while True:
            final = d / (base + ('' if n == 1 else '-%d' % n) + '.glb')
            try:
                os.link(tmp, final)          # 이미 있으면 FileExistsError: 덮어쓰지 않는다
                break
            except FileExistsError:
                n += 1
        return final.name
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass


def _startfile(path):
    os.startfile(str(path))   # Windows 탐색기


def open_folder(line_id, which, root=ROOT, work=None):
    """(열렸나, 글). 폴더가 없으면 만들지 않고 없음을 답한다."""
    d = tripo_dir(line_id, which, root, work)
    if d is None:
        raise ValueError('알 수 없는 줄이나 폴더 낱말')
    if not d.is_dir():
        return False, '폴더가 아직 없습니다'
    _startfile(d)
    return True, str(d)
